#include "MediaStatus.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QTcpSocket>

namespace {
constexpr int kRefreshMs = 10000;
constexpr int kProbeMs = 400;
const char *kProfile = "/usr/local/share/copperbsd/profile.yaml";
const char *kDefaultSubnet = "10.17.0";

QString readSubnet()
{
    QFile f(QString::fromLatin1(kProfile));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        static const QRegularExpression re(QStringLiteral("^jail_subnet:\\s*([0-9.]+)"),
                                           QRegularExpression::MultilineOption);
        if (const auto m = re.match(QString::fromUtf8(f.readAll())); m.hasMatch())
            return m.captured(1);
    }
    return QString::fromLatin1(kDefaultSubnet);
}
} // namespace

MediaStatus::MediaStatus(QObject *parent)
    : QObject(parent)
{
    // Mirrors project/stacks/stack.yaml (jail name, address suffix, service port).
    m_defs = {
        {QStringLiteral("jellyfin"), QStringLiteral("Jellyfin"), tr("Media server"), 10, 8096},
        {QStringLiteral("plex"), QStringLiteral("Plex"), tr("Media server"), 11, 32400},
        {QStringLiteral("prowlarr"), QStringLiteral("Prowlarr"), tr("Indexer manager"), 12, 9696},
        {QStringLiteral("bazarr"), QStringLiteral("Bazarr"), tr("Subtitles"), 13, 6767},
        {QStringLiteral("caddy"), QStringLiteral("Caddy"), tr("Reverse proxy"), 15, 80},
    };
    m_subnet = readSubnet();
    m_total = int(m_defs.size());

    connect(&m_jls, &QProcess::finished, this, [this] {
        parseJls(QString::fromLocal8Bit(m_jls.readAllStandardOutput()));
        probePorts();
    });
    connect(&m_jls, &QProcess::errorOccurred, this, [this] {
        m_runningJails.clear();
        probePorts();
    });
    connect(&m_timer, &QTimer::timeout, this, &MediaStatus::refresh);
    m_timer.start(kRefreshMs);
    refresh();
}

void MediaStatus::refresh()
{
    if (m_busy)
        return;
    m_busy = true;
    m_jls.start(QStringLiteral("jls"), {QStringLiteral("-N"), QStringLiteral("-h"), QStringLiteral("name")});
}

void MediaStatus::parseJls(const QString &out)
{
    m_runningJails.clear();
    const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (int i = 1; i < lines.size(); ++i) // first line is the header
        m_runningJails << lines.at(i).trimmed();
}

void MediaStatus::probePorts()
{
    QVariantList list;
    int running = 0;
    bool anyInstalled = false;
    const QDir jails(QStringLiteral("/usr/local/bastille/jails"));
    for (const Svc &s : std::as_const(m_defs)) {
        const bool jailRunning = m_runningJails.contains(s.jail);
        // /usr/local/bastille may be unreadable to a normal user; if so we
        // simply cannot tell "stopped" from "not installed" and say "stopped".
        const bool exists = jailRunning || jails.exists(s.jail) || !jails.exists();
        bool serving = false;
        if (jailRunning) {
            QTcpSocket sock;
            sock.connectToHost(QStringLiteral("%1.%2").arg(m_subnet).arg(s.ipSuffix), quint16(s.port));
            serving = sock.waitForConnected(kProbeMs);
        }
        QString state = !exists ? tr("Not installed") : !jailRunning ? tr("Stopped")
                       : serving ? tr("Running") : tr("Starting");
        if (jailRunning && serving)
            ++running;
        if (exists)
            anyInstalled = true;
        list.append(QVariantMap{{QStringLiteral("jail"), s.jail}, {QStringLiteral("label"), s.label},
                                {QStringLiteral("role"), s.role}, {QStringLiteral("state"), state},
                                {QStringLiteral("ok"), jailRunning && serving},
                                {QStringLiteral("address"), QStringLiteral("%1.%2:%3").arg(m_subnet).arg(s.ipSuffix).arg(s.port)}});
    }
    m_services = list;
    m_running = running;
    m_installed = anyInstalled;
    m_busy = false;
    emit changed();
}
