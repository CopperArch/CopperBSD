#pragma once
// MediaStatus — state of the CopperBSD media stack (Bastille jails). Reads
// `jls` (unprivileged) for running jails and probes each service's TCP port on
// its jail address. Nothing here opens a browser or talks HTTP.

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>

class MediaStatus : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList services READ services NOTIFY changed)
    Q_PROPERTY(int running READ running NOTIFY changed)
    Q_PROPERTY(int total READ total NOTIFY changed)
    Q_PROPERTY(bool installed READ installed NOTIFY changed)

public:
    explicit MediaStatus(QObject *parent = nullptr);

    QVariantList services() const { return m_services; }
    int running() const { return m_running; }
    int total() const { return m_total; }
    bool installed() const { return m_installed; }

    Q_INVOKABLE void refresh();

signals:
    void changed();

private:
    struct Svc { QString jail, label, role; int ipSuffix; int port; };
    void parseJls(const QString &out);
    void probePorts();

    QList<Svc> m_defs;
    QString m_subnet;
    QStringList m_runningJails;
    QVariantList m_services;
    int m_running = 0, m_total = 0;
    bool m_installed = false;
    QProcess m_jls;
    QTimer m_timer;
    bool m_busy = false;
};
