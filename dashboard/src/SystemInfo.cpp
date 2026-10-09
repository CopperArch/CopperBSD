#include "SystemInfo.h"

#include <QDateTime>
#include <QNetworkInterface>
#include <QRegularExpression>
#include <QStorageInfo>
#include <QSysInfo>

#include <sys/param.h>
#include <sys/resource.h> // CP_USER..CP_IDLE
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>

namespace {
constexpr int kRefreshMs = 2000;
constexpr int kPkgTimeoutMs = 180000;

QString sysctlString(const char *name)
{
    size_t len = 0;
    if (sysctlbyname(name, nullptr, &len, nullptr, 0) != 0 || len == 0)
        return {};
    QByteArray buf(int(len), '\0');
    if (sysctlbyname(name, buf.data(), &len, nullptr, 0) != 0)
        return {};
    return QString::fromLocal8Bit(buf.constData());
}

template<typename T> bool sysctlValue(const char *name, T &out)
{
    size_t len = sizeof(T);
    return sysctlbyname(name, &out, &len, nullptr, 0) == 0;
}
} // namespace

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
{
    m_osName = sysctlString("kern.ostype") + QLatin1Char(' ') + sysctlString("kern.osrelease");
    m_kernel = QSysInfo::kernelVersion();
    m_cpuModel = sysctlString("hw.model").simplified();
    int ncpu = 0;
    if (sysctlValue("hw.ncpu", ncpu))
        m_cores = ncpu;
    unsigned long phys = 0;
    if (sysctlValue("hw.physmem", phys))
        m_memTotal = qint64(phys);

    connect(&m_timer, &QTimer::timeout, this, &SystemInfo::refresh);
    m_timer.start(kRefreshMs);

    connect(&m_pkg, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        const QString out = QString::fromLocal8Bit(m_pkg.readAllStandardOutput());
        static const QRegularExpression count(
            QStringLiteral("Number of packages to be (?:upgraded|installed|reinstalled): (\\d+)"));
        if (out.contains(QStringLiteral("up to date"))) {
            m_updates = 0;
            m_updateState = tr("Up to date");
        } else if (const auto m = count.match(out); m.hasMatch()) {
            m_updates = m.captured(1).toInt();
            m_updateState = tr("%n update(s) available", nullptr, m_updates);
        } else {
            m_updates = -1;
            m_updateState = code == 0 ? tr("Up to date") : tr("Could not check (offline?)");
            if (code == 0)
                m_updates = 0;
        }
        emit updatesChanged();
    });
    connect(&m_pkg, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        m_updates = -1;
        m_updateState = tr("Could not check (offline?)");
        emit updatesChanged();
    });

    m_updateState = tr("Not checked yet");
    refresh();
    sampleCpu(); // prime the delta so the second sample is meaningful
}

QString SystemInfo::hostname() const { return QSysInfo::machineHostName(); }

void SystemInfo::refresh()
{
    sampleCpu();
    sampleMemory();
    sampleStorage();
    sampleUptime();
    sampleNetwork();
    emit changed();
}

void SystemInfo::sampleCpu()
{
    unsigned long cp[CPUSTATES] = {};
    size_t len = sizeof(cp);
    if (sysctlbyname("kern.cp_time", cp, &len, nullptr, 0) != 0)
        return;
    if (m_haveLastCp) {
        unsigned long total = 0, delta[CPUSTATES];
        for (int i = 0; i < CPUSTATES; ++i) {
            delta[i] = cp[i] - m_lastCp[i];
            total += delta[i];
        }
        if (total > 0)
            m_cpuUsage = 1.0 - double(delta[CP_IDLE]) / double(total);
    }
    for (int i = 0; i < CPUSTATES; ++i)
        m_lastCp[i] = cp[i];
    m_haveLastCp = true;
}

void SystemInfo::sampleMemory()
{
    unsigned int pageSize = 0, freeCount = 0, inactive = 0;
    if (!sysctlValue("vm.stats.vm.v_page_size", pageSize))
        return;
    sysctlValue("vm.stats.vm.v_free_count", freeCount);
    sysctlValue("vm.stats.vm.v_inactive_count", inactive);
    const qint64 avail = qint64(freeCount + inactive) * pageSize;
    m_memUsed = qMax<qint64>(0, m_memTotal - avail);
}

void SystemInfo::sampleStorage()
{
    const QStorageInfo root = QStorageInfo::root();
    m_storTotal = root.bytesTotal();
    m_storUsed = root.bytesTotal() - root.bytesAvailable();
    m_storName = QStringLiteral("%1 (%2)").arg(QString::fromUtf8(root.device()), QString::fromUtf8(root.fileSystemType()));
}

void SystemInfo::sampleUptime()
{
    struct timeval boot;
    size_t len = sizeof(boot);
    if (sysctlbyname("kern.boottime", &boot, &len, nullptr, 0) != 0)
        return;
    const qint64 secs = QDateTime::currentSecsSinceEpoch() - qint64(boot.tv_sec);
    const qint64 d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60;
    m_uptime = d > 0 ? tr("%1 d %2 h %3 min").arg(d).arg(h).arg(m)
                     : (h > 0 ? tr("%1 h %2 min").arg(h).arg(m) : tr("%1 min").arg(m));
}

void SystemInfo::sampleNetwork()
{
    QVariantList list;
    bool online = false;
    for (const QNetworkInterface &nic : QNetworkInterface::allInterfaces()) {
        if (nic.flags().testFlag(QNetworkInterface::IsLoopBack))
            continue;
        const QString name = nic.name();
        // Skip virtual plumbing (bridges, jail epairs, pf/wg pseudo-devices).
        if (name.startsWith(QLatin1String("bridge")) || name.startsWith(QLatin1String("bastille"))
            || name.startsWith(QLatin1String("epair")) || name.startsWith(QLatin1String("pflog"))
            || name.startsWith(QLatin1String("lo")))
            continue;
        QStringList v4, v6;
        for (const QNetworkAddressEntry &e : nic.addressEntries()) {
            const QHostAddress a = e.ip();
            if (a.protocol() == QAbstractSocket::IPv4Protocol)
                v4 << a.toString() + QLatin1Char('/') + QString::number(e.prefixLength());
            else if (!a.isLinkLocal())
                v6 << a.toString();
        }
        const bool up = nic.flags().testFlag(QNetworkInterface::IsUp)
                        && nic.flags().testFlag(QNetworkInterface::IsRunning);
        if (up && !v4.isEmpty())
            online = true;
        const bool wifi = name.startsWith(QLatin1String("wlan"));
        list.append(QVariantMap{
            {QStringLiteral("name"), name},
            {QStringLiteral("kind"), wifi ? tr("Wi-Fi") : tr("Ethernet")},
            {QStringLiteral("up"), up},
            {QStringLiteral("ipv4"), v4.join(QStringLiteral(", "))},
            {QStringLiteral("ipv6"), v6.join(QStringLiteral(", "))},
            {QStringLiteral("mac"), nic.hardwareAddress()},
        });
    }
    m_ifaces = list;
    m_online = online;
}

void SystemInfo::checkUpdates()
{
    if (m_pkg.state() != QProcess::NotRunning)
        return;
    m_updateState = tr("Checking...");
    m_updates = -1;
    emit updatesChanged();
    // Dry run, unprivileged: never changes the system.
    m_pkg.start(QStringLiteral("pkg"), {QStringLiteral("upgrade"), QStringLiteral("-n")});
    QTimer::singleShot(kPkgTimeoutMs, &m_pkg, [this] {
        if (m_pkg.state() != QProcess::NotRunning)
            m_pkg.kill();
    });
}

QString SystemInfo::formatBytes(qint64 bytes)
{
    static const char *units[] = {"B", "KiB", "MiB", "GiB", "TiB"};
    double v = double(bytes);
    int u = 0;
    while (v >= 1024.0 && u < 4) {
        v /= 1024.0;
        ++u;
    }
    return QStringLiteral("%1 %2").arg(v, 0, 'f', u == 0 ? 0 : 1).arg(QLatin1String(units[u]));
}
