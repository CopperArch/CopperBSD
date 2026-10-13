#include "Backend.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace {
// status.json is rewritten every 10 s; asking every 2 s keeps the page within
// a couple of seconds of each collection. /api/live is the cheap host reading.
constexpr int kStatusMs = 2000;
constexpr int kLiveMs = 2000;
constexpr int kJobPollMs = 1500;
const char *kDefaultBase = "http://127.0.0.1:8099";
const char *kDefaultTerminal = "http://127.0.0.1:7682/";
} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    m_base = qEnvironmentVariable("COPPER_DASH_URL", QString::fromLatin1(kDefaultBase));
    while (m_base.endsWith(QLatin1Char('/')))
        m_base.chop(1);
    m_terminalUrl = qEnvironmentVariable("COPPER_TTYD_URL", QString::fromLatin1(kDefaultTerminal));
    if (!m_terminalUrl.endsWith(QLatin1Char('/')))
        m_terminalUrl += QLatin1Char('/');
    m_update = {{QStringLiteral("installed"), QStringLiteral("unknown")},
                {QStringLiteral("latest"), QStringLiteral("unknown")},
                {QStringLiteral("available"), QStringLiteral("unknown")}};

    connect(&m_statusTimer, &QTimer::timeout, this, &Backend::reload);
    m_statusTimer.start(kStatusMs);
    connect(&m_liveTimer, &QTimer::timeout, this, &Backend::reloadLive);
    m_liveTimer.start(kLiveMs);
    m_jobTimer.setInterval(kJobPollMs);
    connect(&m_jobTimer, &QTimer::timeout, this, &Backend::pollJob);

    reload();
    reloadLive();
    checkUpdate();
    loadPanes();
    loadAskTargets();
    // A repair started before this window opened (or from another one) is
    // still worth showing: attach to it.
    get(QStringLiteral("/api/job"), [this](int code, const QJsonObject &job, const QString &) {
        if (code == 200 && job.value(QLatin1String("running")).toBool() && !m_jobRunning) {
            m_fixes.clear();
            m_jobRunning = m_jobActive = true;
            m_jobTitle = tr("Repair running");
            m_jobNote = tr("A repair was already running when the dashboard opened.");
            emit jobChanged();
            m_jobTimer.start();
        }
    });
}

void Backend::request(bool isPost, const QString &path, const QJsonObject &body, Reply cb, int timeoutMs)
{
    QNetworkRequest req(QUrl(m_base + path));
    req.setTransferTimeout(timeoutMs);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    QNetworkReply *reply;
    if (isPost) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        reply = m_net.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    } else {
        reply = m_net.get(req);
    }
    connect(reply, &QNetworkReply::finished, this, [reply, cb] {
        reply->deleteLater();
        const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        // An HTTP error status still carries the server's JSON explanation.
        const QString err = code == 0 ? reply->errorString() : QString();
        cb(code, obj, err);
    });
}

void Backend::get(const QString &path, Reply cb, int timeoutMs)
{
    request(false, path, {}, std::move(cb), timeoutMs);
}

void Backend::post(const QString &path, const QJsonObject &body, Reply cb, int timeoutMs)
{
    request(true, path, body, std::move(cb), timeoutMs);
}

void Backend::reload()
{
    get(QStringLiteral("/status.json?_=%1").arg(QDateTime::currentMSecsSinceEpoch()),
        [this](int code, const QJsonObject &body, const QString &netError) {
            if (code == 200 && !body.isEmpty()) {
                const double gen = body.value(QLatin1String("generated_epoch")).toDouble();
                // Same collection as last time: nothing to redraw.
                if (m_reachable && gen == m_generatedExact)
                    return;
                m_status = body.toVariantMap();
                m_generatedExact = gen;
                m_generated = qint64(gen);
                m_reachable = true;
                m_error.clear();
            } else {
                const QString err = !netError.isEmpty() ? netError
                                    : code == 200 ? tr("status.json is empty") : tr("HTTP %1").arg(code);
                if (!m_reachable && err == m_error)
                    return;
                m_reachable = false;
                m_error = err;
            }
            emit statusChanged();
            rebuildLive();
        });
}

void Backend::reloadLive()
{
    get(QStringLiteral("/api/live?_=%1").arg(QDateTime::currentMSecsSinceEpoch()),
        [this](int code, const QJsonObject &body, const QString &) {
            // On any failure keep the last reading; reload() reports a dead server.
            if (code != 200 || body.isEmpty())
                return;
            m_live = body.toVariantMap();
            rebuildLive();
        }, 5000);
}

void Backend::rebuildLive()
{
    QVariantMap out = m_status;
    QVariantMap host = out.value(QStringLiteral("host")).toMap();
    if (!m_live.isEmpty() && !host.contains(QStringLiteral("error"))) {
        const QVariantMap live = m_live.value(QStringLiteral("host")).toMap();
        QVariantMap cpu = host.value(QStringLiteral("cpu")).toMap();   // keeps the model name
        const QVariantMap liveCpu = live.value(QStringLiteral("cpu")).toMap();
        for (auto it = liveCpu.constBegin(); it != liveCpu.constEnd(); ++it)
            cpu.insert(it.key(), it.value());
        host.insert(QStringLiteral("cpu"), cpu);
        for (const char *key : {"memory", "load", "sensors", "uptime_seconds"}) {
            const QString k = QString::fromLatin1(key);
            if (live.contains(k))
                host.insert(k, live.value(k));
        }
        out.insert(QStringLiteral("host"), host);
        const QVariantMap disks = m_live.value(QStringLiteral("disks")).toMap();
        if (disks.contains(QStringLiteral("filesystems")))
            out.insert(QStringLiteral("disks"), disks);
    }
    m_liveStatus = out;
    emit liveChanged();
}

void Backend::refresh()
{
    if (m_refreshing)
        return;
    m_refreshing = true;
    emit refreshingChanged();
    post(QStringLiteral("/api/refresh"), {}, [this](int, const QJsonObject &, const QString &) {
        m_refreshing = false;
        emit refreshingChanged();
        reload();
    }, 200000);
}

QString Backend::fixInfo(const QString &id)
{
    static const QHash<QString, QString> info = {
        {QStringLiteral("jail_start"), tr("Starting the stopped jail (bastille start).")},
        {QStringLiteral("jail_restart"), tr("Restarting the jail. If it's the vpn jail, this reroutes into a full VPN-group restart instead — restarting the tunnel alone would strip the route from the jails confined to it.")},
        {QStringLiteral("vpn_recreate"), tr("Restarting the vpn jail and the jails confined to its tunnel (qbittorrent, sonarr, radarr) together, hub first, so none of them lose their route.")},
        {QStringLiteral("vpn_rotate"), tr("Restarting the WireGuard tunnel (fresh handshake against the Endpoint wg0.conf currently names), then reporting the exit IP.")},
        {QStringLiteral("prowlarr_testall"), tr("Asking Prowlarr to test every indexer and reporting which ones still fail validation.")},
        {QStringLiteral("cloudflare_unblock"), tr("Rotating the VPN exit IP (up to 3 attempts, ~15s apart) to escape a Cloudflare IP/range ban, probing the blocked host after each rotation, then re-testing all indexers.")},
        {QStringLiteral("pkg_upgrade"), tr("Running pkg upgrade as root. Duration depends on how many packages are pending.")},
        {QStringLiteral("daily_routine_quick"), tr("Running the quick pass of the nightly daily-routine script.")},
        {QStringLiteral("restart_service"), tr("Restarting the rc.d service on the host (service <name> restart).")},
        {QStringLiteral("copperbsd_update"), tr("Downloading the latest CopperBSD from GitHub, replacing the media-server project and dashboard source, rebuilding the dashboard if it changed, then re-applying the media stack. This can take several minutes.")},
    };
    return info.value(id);
}

void Backend::runFixes(const QVariantList &fixes, const QString &title)
{
    if (m_jobRunning) {            // show the one already running
        m_jobActive = true;
        emit jobChanged();
        return;
    }
    if (fixes.isEmpty())
        return;
    m_fixes = fixes;
    m_jobRunning = m_jobActive = true;
    m_jobOk = false;
    m_jobCancelling = false;
    m_jobTitle = title;
    m_jobNote = tr("Running whitelisted repairs — this can take a minute.");
    rebuildRows({}, QString());
    emit jobChanged();

    QJsonArray list;
    for (const QVariant &f : fixes) {
        const QVariantMap m = f.toMap();
        list.append(QJsonObject{{QStringLiteral("id"), m.value(QStringLiteral("id")).toString()},
                                {QStringLiteral("args"), QJsonObject::fromVariantMap(m.value(QStringLiteral("args")).toMap())}});
    }
    post(QStringLiteral("/api/fix"), QJsonObject{{QStringLiteral("fixes"), list}},
         [this](int code, const QJsonObject &body, const QString &netError) {
             // 409 = a repair is already in flight server-side: attach to it.
             if (code != 202 && code != 200 && code != 409) {
                 const QString why = !netError.isEmpty() ? netError
                     : body.value(QLatin1String("error")).toString(tr("HTTP %1").arg(code));
                 m_jobRows = {QVariantMap{{QStringLiteral("label"), tr("Repair request failed")},
                                          {QStringLiteral("state"), QStringLiteral("bad")},
                                          {QStringLiteral("detail"), QString()},
                                          {QStringLiteral("output"), why}}};
                 finishJob(tr("Repair failed"), tr("Nothing was changed, or the run was interrupted."), false);
                 return;
             }
             m_jobTimer.start();
         });
}

void Backend::rebuildRows(const QVariantList &results, const QString &current)
{
    QVariantList rows;
    for (int i = 0; i < results.size(); ++i) {
        const QVariantMap r = results.at(i).toMap();
        const QVariantMap f = i < m_fixes.size() ? m_fixes.at(i).toMap() : QVariantMap();
        const bool ok = r.value(QStringLiteral("ok")).toBool();
        const bool cancelled = r.value(QStringLiteral("cancelled")).toBool();
        rows.append(QVariantMap{
            {QStringLiteral("label"), f.value(QStringLiteral("label"), r.value(QStringLiteral("id"))).toString()},
            {QStringLiteral("state"), ok ? QStringLiteral("ok") : cancelled ? QStringLiteral("cancelled") : QStringLiteral("bad")},
            {QStringLiteral("detail"), QStringLiteral("%1 · %2s").arg(cancelled ? tr("cancelled") : ok ? tr("fixed") : tr("failed"),
                                                                     r.value(QStringLiteral("seconds")).toString())},
            {QStringLiteral("output"), r.value(QStringLiteral("output")).toString().left(2500)}});
    }
    for (int i = results.size(); i < m_fixes.size(); ++i) {
        const QVariantMap f = m_fixes.at(i).toMap();
        const bool isCurrent = i == results.size() && m_jobRunning;
        const QString id = f.value(QStringLiteral("id")).toString();
        rows.append(QVariantMap{
            {QStringLiteral("label"), f.value(QStringLiteral("label"), id).toString()},
            {QStringLiteral("state"), isCurrent ? QStringLiteral("cur") : QStringLiteral("queued")},
            {QStringLiteral("detail"), isCurrent ? tr("running…") : tr("queued")},
            {QStringLiteral("output"), isCurrent ? fixInfo(id) : QString()}});
    }
    if (rows.isEmpty() && !current.isEmpty())
        rows.append(QVariantMap{{QStringLiteral("label"), current}, {QStringLiteral("state"), QStringLiteral("cur")},
                                {QStringLiteral("detail"), tr("running…")}, {QStringLiteral("output"), fixInfo(current)}});
    m_jobRows = rows;
}

void Backend::pollJob()
{
    get(QStringLiteral("/api/job?_=%1").arg(QDateTime::currentMSecsSinceEpoch()),
        [this](int code, const QJsonObject &job, const QString &netError) {
            if (!m_jobRunning)
                return;
            if (code != 200) {
                // The update fix can outlive a server restart; keep polling
                // through brief gaps instead of declaring failure at once.
                m_jobNote = tr("Waiting for the repair server… (%1)").arg(netError.isEmpty() ? tr("HTTP %1").arg(code) : netError);
                emit jobChanged();
                return;
            }
            const QVariantList results = job.value(QLatin1String("results")).toArray().toVariantList();
            const QString current = job.value(QLatin1String("current")).toString();
            const bool cancelled = job.value(QLatin1String("cancelled")).toBool();
            const bool done = job.value(QLatin1String("done")).toBool();
            if (!done) {
                rebuildRows(results, current);
                const int total = qMax(int(m_fixes.size()), job.value(QLatin1String("total")).toInt(1));
                const qint64 secs = QDateTime::currentSecsSinceEpoch() - qint64(job.value(QLatin1String("started")).toDouble());
                m_jobNote = cancelled ? tr("Stopping — waiting for the running step to exit…")
                                      : tr("Running repair %1 of %2 — %3s elapsed.")
                                            .arg(qMin(int(results.size()) + 1, total)).arg(total).arg(secs);
                emit jobChanged();
                return;
            }
            m_jobRunning = false;
            rebuildRows(results, QString());
            const QString error = job.value(QLatin1String("error")).toString();
            int fixed = 0;
            for (const QVariant &r : results)
                if (r.toMap().value(QStringLiteral("ok")).toBool())
                    ++fixed;
            const int failed = int(results.size()) - fixed;
            if (!error.isEmpty())
                finishJob(tr("Repair failed"), error, false);
            else if (cancelled)
                finishJob(tr("Cancelled — %1 finished before the stop").arg(fixed),
                          tr("Stopped by you. Status re-collected, so the panels show what was left behind."), false);
            else
                finishJob(tr("%1 fixed, %2 still failing").arg(fixed).arg(failed),
                          tr("Status re-collected — the panels are up to date."), failed == 0);
        });
}

void Backend::finishJob(const QString &title, const QString &note, bool ok)
{
    m_jobTimer.stop();
    m_jobRunning = false;
    m_jobCancelling = false;
    m_jobOk = ok;
    m_jobTitle = title;
    m_jobNote = note;
    emit jobChanged();
    reload();
    checkUpdate();
}

void Backend::cancelJob()
{
    if (!m_jobRunning || m_jobCancelling)
        return;
    m_jobCancelling = true;
    emit jobChanged();
    post(QStringLiteral("/api/cancel"), {}, [this](int code, const QJsonObject &, const QString &) {
        if (code != 200) {
            m_jobCancelling = false;
            emit jobChanged();
        }
    });
}

void Backend::dismissJob()
{
    if (m_jobRunning)
        return;
    m_jobActive = false;
    m_jobRows.clear();
    emit jobChanged();
}

void Backend::reboot()
{
    post(QStringLiteral("/api/reboot"), QJsonObject{{QStringLiteral("confirm"), QStringLiteral("REBOOT")}},
         [this](int code, const QJsonObject &body, const QString &netError) {
             const bool ok = code == 200 && body.value(QLatin1String("ok")).toBool();
             emit rebootResult(ok, ok ? tr("Rebooting…")
                                      : !netError.isEmpty() ? netError
                                      : body.value(QLatin1String("error")).toString(tr("HTTP %1").arg(code)));
         });
}

void Backend::openLink(const QString &id)
{
    post(QStringLiteral("/api/open"), QJsonObject{{QStringLiteral("id"), id}},
         [](int, const QJsonObject &, const QString &) {});
}

void Backend::loadPanes()
{
    get(QStringLiteral("/api/panes"), [this](int code, const QJsonObject &body, const QString &) {
        if (code != 200)
            return;
        m_panes = body.value(QLatin1String("panes")).toArray().toVariantList();
        m_panesLoaded = true;
        emit panesChanged();
    });
}

void Backend::loadAskTargets()
{
    get(QStringLiteral("/api/ask-targets"), [this](int code, const QJsonObject &body, const QString &) {
        if (code != 200)
            return;
        m_askTargets = body.value(QLatin1String("targets")).toArray().toVariantList();
        emit askTargetsChanged();
    });
}

void Backend::setVpnConfig(const QString &config, const QString &name)
{
    post(QStringLiteral("/api/vpn-config"),
         QJsonObject{{QStringLiteral("config"), config}, {QStringLiteral("name"), name}},
         [this](int code, const QJsonObject &body, const QString &netError) {
             const bool ok = code == 200 && body.value(QLatin1String("ok")).toBool();
             emit vpnConfigResult(ok, !netError.isEmpty() ? netError
                 : body.value(QLatin1String("output")).toString(ok ? tr("done") : tr("failed")));
             if (ok)
                 refresh();
         }, 120000);
}

void Backend::setSchedule(const QString &frequency, const QString &time)
{
    post(QStringLiteral("/api/schedule"),
         QJsonObject{{QStringLiteral("frequency"), frequency}, {QStringLiteral("time"), time}},
         [this](int code, const QJsonObject &body, const QString &netError) {
             const bool ok = code == 200 && body.value(QLatin1String("ok")).toBool();
             emit scheduleResult(ok, !netError.isEmpty() ? netError
                 : body.value(QLatin1String("output")).toString(ok ? tr("done") : tr("failed")));
             if (ok)
                 refresh();
         });
}

void Backend::checkUpdate()
{
    if (m_updateChecking)
        return;
    m_updateChecking = true;
    emit updateChanged();
    get(QStringLiteral("/api/update-check"), [this](int code, const QJsonObject &body, const QString &) {
        m_updateChecking = false;
        if (code == 200 && !body.isEmpty())
            m_update = body.toVariantMap();
        emit updateChanged();
    }, 60000);
}
