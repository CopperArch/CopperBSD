#pragma once
// AppCatalog — standard freedesktop .desktop discovery. Lists the applications
// installed on this machine (KDE, CopperBSD profile, anything else) and
// launches them. No hard-coded binary paths: everything comes from the
// application entries the desktop itself uses.

#include <QAbstractListModel>
#include <QList>
#include <QString>

struct AppEntry {
    QString id;       // desktop-file id, e.g. "org.kde.dolphin.desktop"
    QString name;
    QString comment;
    QString icon;
    QString exec;
    QStringList categories;
    bool terminal = false;
};

class AppCatalog : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY reloaded)

public:
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, CommentRole, IconRole, CategoriesRole };

    explicit AppCatalog(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    int totalCount() const { return m_all.size(); }

    Q_INVOKABLE void reload();
    /*! Launch by desktop-file id ("org.kde.dolphin" or "org.kde.dolphin.desktop"). */
    Q_INVOKABLE bool launch(const QString &desktopId);
    Q_INVOKABLE bool has(const QString &desktopId) const;
    /*! First installed app whose id matches any of the candidates, or "". */
    Q_INVOKABLE QString firstInstalled(const QStringList &candidates) const;
    /*! Launch the first installed candidate. */
    Q_INVOKABLE bool launchFirst(const QStringList &candidates);
    /*! Open the user's home directory in the default file manager. */
    Q_INVOKABLE bool openHome();
    /*! Apps whose Categories include any of the given ones (for the Media page). */
    Q_INVOKABLE QVariantList appsInCategories(const QStringList &categories) const;
    Q_INVOKABLE bool runCommand(const QString &program, const QStringList &args);

signals:
    void filterChanged();
    void reloaded();

private:
    const AppEntry *find(const QString &id) const;
    void applyFilter();
    static bool parseDesktopFile(const QString &path, const QString &id, AppEntry &out);

    QList<AppEntry> m_all;
    QList<AppEntry> m_visible;
    QString m_filter;
};
