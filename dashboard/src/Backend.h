#pragma once
// Backend — the dashboard's link to the status collector and repair server
// (project/templates/dashboard/status-collect.py + status-dashboard-server.py),
// the same pair the Linux and FreeBSD web dashboards talk to. Everything goes
// over loopback HTTP: status.json for the panels, /api/* for the whitelisted
// repairs. Nothing here runs a command itself.

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool reachable READ reachable NOTIFY statusChanged)
    Q_PROPERTY(QString error READ error NOTIFY statusChanged)
    Q_PROPERTY(qint64 generatedEpoch READ generatedEpoch NOTIFY statusChanged)
    Q_PROPERTY(bool refreshing READ refreshing NOTIFY refreshingChanged)

    Q_PROPERTY(bool jobRunning READ jobRunning NOTIFY jobChanged)
    Q_PROPERTY(bool jobActive READ jobActive NOTIFY jobChanged)
    Q_PROPERTY(QString jobTitle READ jobTitle NOTIFY jobChanged)
    Q_PROPERTY(QString jobNote READ jobNote NOTIFY jobChanged)
    Q_PROPERTY(QVariantList jobRows READ jobRows NOTIFY jobChanged)
    Q_PROPERTY(bool jobOk READ jobOk NOTIFY jobChanged)
    Q_PROPERTY(bool jobCancelling READ jobCancelling NOTIFY jobChanged)

    Q_PROPERTY(QVariantMap update READ update NOTIFY updateChanged)
    Q_PROPERTY(bool updateChecking READ updateChecking NOTIFY updateChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    QVariantMap status() const { return m_status; }
    bool reachable() const { return m_reachable; }
    QString error() const { return m_error; }
    qint64 generatedEpoch() const { return m_generated; }
    bool refreshing() const { return m_refreshing; }

    bool jobRunning() const { return m_jobRunning; }
    bool jobActive() const { return m_jobActive; }
    QString jobTitle() const { return m_jobTitle; }
    QString jobNote() const { return m_jobNote; }
    QVariantList jobRows() const { return m_jobRows; }
    bool jobOk() const { return m_jobOk; }
    bool jobCancelling() const { return m_jobCancelling; }

    QVariantMap update() const { return m_update; }
    bool updateChecking() const { return m_updateChecking; }

    /*! Re-read status.json. */
    Q_INVOKABLE void reload();
    /*! Ask the server to re-collect now, then reload. */
    Q_INVOKABLE void refresh();
    /*! Run whitelisted fixes: a list of {id, args, label}. */
    Q_INVOKABLE void runFixes(const QVariantList &fixes, const QString &title);
    Q_INVOKABLE void cancelJob();
    /*! Forget a finished job (closes the result sheet for good). */
    Q_INVOKABLE void dismissJob();
    Q_INVOKABLE void reboot();
    /*! Open a whitelisted app link in the desktop browser. */
    Q_INVOKABLE void openLink(const QString &id);
    Q_INVOKABLE void setVpnConfig(const QString &config, const QString &name);
    Q_INVOKABLE void setSchedule(const QString &frequency, const QString &time);
    /*! Compare the installed CopperBSD version with the latest on GitHub. */
    Q_INVOKABLE void checkUpdate();
    /*! What a fix id does, for the running-job note. */
    Q_INVOKABLE static QString fixInfo(const QString &id);

signals:
    void statusChanged();
    void refreshingChanged();
    void jobChanged();
    void updateChanged();
    void vpnConfigResult(bool ok, const QString &message);
    void scheduleResult(bool ok, const QString &message);
    void rebootResult(bool ok, const QString &message);

private:
    using Reply = std::function<void(int httpStatus, const QJsonObject &body, const QString &netError)>;
    void get(const QString &path, Reply cb, int timeoutMs = 15000);
    void post(const QString &path, const QJsonObject &body, Reply cb, int timeoutMs = 60000);
    void request(bool isPost, const QString &path, const QJsonObject &body, Reply cb, int timeoutMs);
    void pollJob();
    void rebuildRows(const QVariantList &results, const QString &current);
    void finishJob(const QString &title, const QString &note, bool ok);

    QNetworkAccessManager m_net;
    QString m_base;
    QTimer m_statusTimer;
    QTimer m_jobTimer;

    QVariantMap m_status;
    bool m_reachable = false;
    QString m_error;
    qint64 m_generated = 0;
    bool m_refreshing = false;

    QVariantList m_fixes;
    bool m_jobRunning = false;
    bool m_jobActive = false;
    bool m_jobOk = false;
    bool m_jobCancelling = false;
    QString m_jobTitle;
    QString m_jobNote;
    QVariantList m_jobRows;

    QVariantMap m_update;
    bool m_updateChecking = false;
};
