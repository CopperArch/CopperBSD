#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include "DiskModel.h"

/*!
 * \brief Drives the real install. Owns a QProcess running the privileged
 *        backend script (\c copperarch-install.sh), which generates a
 *        bsdinstall scripted-install config and runs FreeBSD's own
 *        partition/distextract/zfsboot backend — so the GUI never reimplements
 *        partitioning, it only collects answers and streams progress.
 *
 * Protocol with the backend (one token per stdout line):
 *   \c PROGRESS <0..100>   — overall percent
 *   \c STEP <text>         — current phase label
 *   \c LOG <text>          — verbose line for the log pane
 *   \c DONE ok | DONE fail <msg>
 */
class InstallerBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(DiskModel *disks READ disks CONSTANT)
    Q_PROPERTY(QStringList keymaps READ keymaps CONSTANT)
    Q_PROPERTY(QStringList timezones READ timezones CONSTANT)
    Q_PROPERTY(bool installing READ installing NOTIFY installingChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString step READ step NOTIFY stepChanged)
    Q_PROPERTY(bool liveMode READ liveMode CONSTANT)

public:
    explicit InstallerBackend(QObject *parent = nullptr);

    DiskModel *disks() { return &m_disks; }
    QStringList keymaps() const { return m_keymaps; }
    QStringList timezones() const { return m_timezones; }
    bool installing() const { return m_installing; }
    int progress() const { return m_progress; }
    QString step() const { return m_step; }
    //! False when launched outside a live installer image (guards real writes).
    bool liveMode() const { return m_liveMode; }

    //! Rescan disks (async); emits disksChanged on the DiskModel when done.
    Q_INVOKABLE void refreshDisks();
    /** Switch the live X session to a console keymap's XKB layout, so the
     *  Keyboard page's test field types in the picked layout. */
    Q_INVOKABLE void applyKeymap(const QString &keymap);

    /*! Begin installation. \a answers carries the wizard's collected values:
     *  disk, zfsVdev, swapGiB, hostname, username, fullname, password,
     *  rootPassword, timezone, keymap, enableMediaStack (bool). */
    Q_INVOKABLE void start(const QVariantMap &answers);

    //! Request cancellation of an in-flight install.
    Q_INVOKABLE void abort();

    //! Reboot the freshly installed machine (called from the Finish page).
    Q_INVOKABLE void reboot();

signals:
    void installingChanged();
    void progressChanged();
    void stepChanged();
    void logLine(const QString &line);
    void finished(bool ok, const QString &message);

private slots:
    void onReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus status);

private:
    QString backendPath() const;
    void setInstalling(bool v);
    void setProgress(int v);
    void setStep(const QString &s);
    void handleLine(const QString &line);

    DiskModel m_disks;
    QStringList m_keymaps;
    QStringList m_timezones;
    QProcess m_proc;
    QProcess m_scanProc;
    bool m_installing = false;
    bool m_liveMode = false;
    bool m_sawDone = false;
    int m_progress = 0;
    QString m_step;
};
