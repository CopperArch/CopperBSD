#include "InstallerBackend.h"

#include <unistd.h>

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QStandardPaths>

namespace {
// Candidate locations for the privileged backend driver. On the live ISO it is
// installed to /usr/local/libexec; during development it sits beside the binary.
const char *kBackendName = "copperarch-install.sh";
}

InstallerBackend::InstallerBackend(QObject *parent)
    : QObject(parent)
{
    m_liveMode = QFileInfo::exists(QStringLiteral("/etc/copperarch-live"));

    // Populate static choice lists from the backend (keymaps/timezones come
    // from the live system so they always match what bsdinstall accepts).
    QProcess p;
    p.start(backendPath(), { QStringLiteral("--keymaps") });
    if (p.waitForFinished(5000))
        m_keymaps = QString::fromUtf8(p.readAllStandardOutput())
                        .split('\n', Qt::SkipEmptyParts);
    if (m_keymaps.isEmpty())
        m_keymaps = { QStringLiteral("us"), QStringLiteral("uk"),
                      QStringLiteral("de"), QStringLiteral("fr") };

    QProcess tz;
    tz.start(backendPath(), { QStringLiteral("--timezones") });
    if (tz.waitForFinished(5000))
        m_timezones = QString::fromUtf8(tz.readAllStandardOutput())
                          .split('\n', Qt::SkipEmptyParts);
    if (m_timezones.isEmpty())
        m_timezones = { QStringLiteral("Europe/London"),
                        QStringLiteral("America/New_York"),
                        QStringLiteral("UTC") };

    connect(&m_proc, &QProcess::readyReadStandardOutput,
            this, &InstallerBackend::onReadyRead);
    connect(&m_proc, &QProcess::readyReadStandardError,
            this, &InstallerBackend::onReadyRead);
    connect(&m_proc, &QProcess::finished,
            this, &InstallerBackend::onProcessFinished);

    refreshDisks();
}

// The backend partitions disks, so it must run as root. The live session runs
// the GUI as an unprivileged user; doas (rule in /usr/local/etc/doas.conf,
// limited to this one script) elevates only the backend. -n: never prompt.
static void startBackend(QProcess &proc, const QString &backend, const QStringList &args)
{
    if (geteuid() == 0) {
        proc.start(backend, args);
        return;
    }
    proc.start(QStringLiteral("/usr/local/bin/doas"),
               QStringList{ QStringLiteral("-n"), backend } + args);
}

QString InstallerBackend::backendPath() const
{
    const QStringList candidates = {
        QStringLiteral("/usr/local/libexec/%1").arg(QString::fromLatin1(kBackendName)),
        QCoreApplication::applicationDirPath() + QStringLiteral("/../backend/") +
            QString::fromLatin1(kBackendName),
        QStringLiteral("./backend/%1").arg(QString::fromLatin1(kBackendName)),
    };
    for (const QString &c : candidates)
        if (QFileInfo::exists(c))
            return c;
    return candidates.first();
}

void InstallerBackend::refreshDisks()
{
    // Disconnect any prior scan to keep this re-entrant.
    m_scanProc.kill();
    m_scanProc.waitForFinished(1000);
    connect(&m_scanProc,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
                QList<DiskInfo> found;
                const QByteArray out = m_scanProc.readAllStandardOutput();
                const QJsonDocument doc = QJsonDocument::fromJson(out);
                for (const QJsonValue &v : doc.array()) {
                    const QJsonObject o = v.toObject();
                    found.push_back({ o.value("device").toString(),
                                      o.value("descr").toString(),
                                      static_cast<qint64>(
                                          o.value("bytes").toDouble()) });
                }
                m_disks.setDisks(std::move(found));
            },
            Qt::SingleShotConnection);
    m_scanProc.start(backendPath(), { QStringLiteral("--list-disks") });
}

void InstallerBackend::start(const QVariantMap &answers)
{
    if (m_installing)
        return;

    // Hand answers to the backend as key=value lines on stdin — trivial to parse
    // in POSIX sh, and secrets never touch argv (visible in ps) or a file. One
    // line per key; values may contain '=' (sh splits on the first only).
    QByteArray payload;
    for (auto it = answers.constBegin(); it != answers.constEnd(); ++it) {
        const QString v = it.value().toString();
        payload += it.key().toUtf8() + '=' + v.toUtf8() + '\n';
    }

    m_sawDone = false;
    setProgress(0);
    setStep(tr("Preparing…"));
    setInstalling(true);

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("COPPERARCH_GUI"), QStringLiteral("1"));
    m_proc.setProcessEnvironment(env);

    startBackend(m_proc, backendPath(), { QStringLiteral("--install") });
    if (!m_proc.waitForStarted(5000)) {
        setInstalling(false);
        emit finished(false, tr("Could not launch the install backend."));
        return;
    }
    m_proc.write(payload);
    m_proc.closeWriteChannel();
}

void InstallerBackend::abort()
{
    if (m_installing)
        m_proc.terminate();
}

void InstallerBackend::reboot()
{
    if (geteuid() == 0)
        QProcess::startDetached(backendPath(), { QStringLiteral("--reboot") });
    else
        QProcess::startDetached(QStringLiteral("/usr/local/bin/doas"),
                                { QStringLiteral("-n"), backendPath(),
                                  QStringLiteral("--reboot") });
}

void InstallerBackend::onReadyRead()
{
    for (const QByteArray &raw : m_proc.readAllStandardOutput().split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (!line.isEmpty())
            handleLine(line);
    }
    for (const QByteArray &raw : m_proc.readAllStandardError().split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (!line.isEmpty())
            emit logLine(line);
    }
}

void InstallerBackend::handleLine(const QString &line)
{
    if (line.startsWith(QLatin1String("PROGRESS "))) {
        setProgress(line.mid(9).trimmed().toInt());
    } else if (line.startsWith(QLatin1String("STEP "))) {
        setStep(line.mid(5).trimmed());
    } else if (line.startsWith(QLatin1String("LOG "))) {
        emit logLine(line.mid(4));
    } else if (line.startsWith(QLatin1String("DONE "))) {
        m_sawDone = true;
        const QString rest = line.mid(5).trimmed();
        const bool ok = rest.startsWith(QLatin1String("ok"));
        if (ok)
            setProgress(100);
        emit finished(ok, ok ? QString() : rest.mid(rest.indexOf(' ') + 1));
    } else {
        emit logLine(line);
    }
}

void InstallerBackend::onProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    setInstalling(false);
    if (!m_sawDone) {
        const bool ok = (status == QProcess::NormalExit && exitCode == 0);
        emit finished(ok, ok ? QString()
                              : tr("The installer exited unexpectedly (code %1).")
                                    .arg(exitCode));
    }
}

void InstallerBackend::setInstalling(bool v)
{
    if (m_installing == v)
        return;
    m_installing = v;
    emit installingChanged();
}

void InstallerBackend::setProgress(int v)
{
    v = qBound(0, v, 100);
    if (m_progress == v)
        return;
    m_progress = v;
    emit progressChanged();
}

void InstallerBackend::setStep(const QString &s)
{
    if (m_step == s)
        return;
    m_step = s;
    emit stepChanged();
}
