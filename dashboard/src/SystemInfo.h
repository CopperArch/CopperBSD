#pragma once
// SystemInfo — live host facts for the dashboard, read natively (sysctl(3),
// QStorageInfo, QNetworkInterface) -- no scraping of commands or web pages.
// The one exception is the pending-update count, which asks pkg(8) once in
// the background and degrades to "unknown" when there is no network.

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>

class SystemInfo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString hostname READ hostname CONSTANT)
    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString cpuModel READ cpuModel CONSTANT)
    Q_PROPERTY(int cpuCores READ cpuCores CONSTANT)
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY changed)
    Q_PROPERTY(qint64 memTotal READ memTotal CONSTANT)
    Q_PROPERTY(qint64 memUsed READ memUsed NOTIFY changed)
    Q_PROPERTY(qint64 storageTotal READ storageTotal NOTIFY changed)
    Q_PROPERTY(qint64 storageUsed READ storageUsed NOTIFY changed)
    Q_PROPERTY(QString storageName READ storageName NOTIFY changed)
    Q_PROPERTY(QString uptime READ uptime NOTIFY changed)
    Q_PROPERTY(QVariantList interfaces READ interfaces NOTIFY changed)
    Q_PROPERTY(bool online READ online NOTIFY changed)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY updatesChanged)
    Q_PROPERTY(QString updateState READ updateState NOTIFY updatesChanged)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    QString hostname() const;
    QString osName() const { return m_osName; }
    QString kernel() const { return m_kernel; }
    QString cpuModel() const { return m_cpuModel; }
    int cpuCores() const { return m_cores; }
    double cpuUsage() const { return m_cpuUsage; }
    qint64 memTotal() const { return m_memTotal; }
    qint64 memUsed() const { return m_memUsed; }
    qint64 storageTotal() const { return m_storTotal; }
    qint64 storageUsed() const { return m_storUsed; }
    QString storageName() const { return m_storName; }
    QString uptime() const { return m_uptime; }
    QVariantList interfaces() const { return m_ifaces; }
    bool online() const { return m_online; }
    int updateCount() const { return m_updates; }
    QString updateState() const { return m_updateState; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void checkUpdates();
    Q_INVOKABLE static QString formatBytes(qint64 bytes);

signals:
    void changed();
    void updatesChanged();

private:
    void sampleCpu();
    void sampleMemory();
    void sampleStorage();
    void sampleUptime();
    void sampleNetwork();

    QString m_osName, m_kernel, m_cpuModel, m_uptime, m_storName, m_updateState;
    int m_cores = 0;
    double m_cpuUsage = 0;
    qint64 m_memTotal = 0, m_memUsed = 0, m_storTotal = 0, m_storUsed = 0;
    QVariantList m_ifaces;
    bool m_online = false;
    int m_updates = -1;
    unsigned long m_lastCp[5] = {0, 0, 0, 0, 0};
    bool m_haveLastCp = false;
    QTimer m_timer;
    QProcess m_pkg;
};
