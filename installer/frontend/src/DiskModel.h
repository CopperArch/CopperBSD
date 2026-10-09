#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QtQml/qqmlregistration.h>

/*! A detected installation target disk (one row of DiskModel). */
struct DiskInfo {
    QString device;   //!< e.g. "ada0", "nvd0"
    QString descr;    //!< human model string, e.g. "Samsung SSD 990 PRO 2TB"
    qint64  bytes;    //!< capacity in bytes
};

/*!
 * \brief List model of installable disks, populated from the install backend's
 *        `copperarch-install.sh --list-disks` (which reads geom/sysctl).
 *
 * Exposed to QML as a type in the CopperArch module; the Disk page binds a
 * ListView/ComboBox to it and reports the chosen row's \c device back.
 */
class DiskModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum Roles {
        DeviceRole = Qt::UserRole + 1,
        DescrRole,
        BytesRole,
        SizeHumanRole,
    };
    Q_ENUM(Roles)

    explicit DiskModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    //! Replace the disk list (called by InstallerBackend after a scan).
    void setDisks(QList<DiskInfo> disks);

    //! Device name for a row, or empty — convenience for QML selection.
    Q_INVOKABLE QString deviceAt(int row) const;

private:
    QList<DiskInfo> m_disks;
};
