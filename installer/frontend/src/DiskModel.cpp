#include "DiskModel.h"

#include <QLocale>

DiskModel::DiskModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int DiskModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_disks.size());
}

QVariant DiskModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_disks.size())
        return {};

    const DiskInfo &d = m_disks.at(index.row());
    switch (role) {
    case DeviceRole:
        return d.device;
    case DescrRole:
        return d.descr;
    case BytesRole:
        return d.bytes;
    case SizeHumanRole:
        // 1000-based to match how drives are marketed (a "2TB" disk).
        return QLocale::system().formattedDataSize(
            d.bytes, 1, QLocale::DataSizeSIFormat);
    default:
        return {};
    }
}

QHash<int, QByteArray> DiskModel::roleNames() const
{
    return {
        { DeviceRole, "device" },
        { DescrRole, "descr" },
        { BytesRole, "bytes" },
        { SizeHumanRole, "sizeHuman" },
    };
}

void DiskModel::setDisks(QList<DiskInfo> disks)
{
    beginResetModel();
    m_disks = std::move(disks);
    endResetModel();
}

QString DiskModel::deviceAt(int row) const
{
    if (row < 0 || row >= m_disks.size())
        return {};
    return m_disks.at(row).device;
}
