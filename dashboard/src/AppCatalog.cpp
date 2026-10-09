#include "AppCatalog.h"

#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>
#include <algorithm>

namespace {
// FreeBSD installs ports under /usr/local; XDG_DATA_DIRS is not always set to
// include it, so make sure both prefixes are searched.
QStringList applicationDirs()
{
    QStringList dirs = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const char *extra : {"/usr/local/share/applications", "/usr/share/applications"})
        if (!dirs.contains(QLatin1String(extra)))
            dirs << QString::fromLatin1(extra);
    return dirs;
}

QString stripFieldCodes(QString exec)
{
    exec.replace(QStringLiteral("%%"), QStringLiteral("\x01"));
    static const QStringList codes = {"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"};
    for (const QString &c : codes)
        exec.remove(c);
    exec.replace(QStringLiteral("\x01"), QStringLiteral("%"));
    return exec.simplified();
}
} // namespace

AppCatalog::AppCatalog(QObject *parent)
    : QAbstractListModel(parent)
{
    reload();
}

int AppCatalog::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_visible.size());
}

QVariant AppCatalog::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_visible.size())
        return {};
    const AppEntry &a = m_visible.at(index.row());
    switch (role) {
    case IdRole: return a.id;
    case NameRole: return a.name;
    case CommentRole: return a.comment;
    case IconRole: return a.icon;
    case CategoriesRole: return a.categories;
    }
    return {};
}

QHash<int, QByteArray> AppCatalog::roleNames() const
{
    return {{IdRole, "appId"}, {NameRole, "name"}, {CommentRole, "comment"},
            {IconRole, "iconName"}, {CategoriesRole, "categories"}};
}

bool AppCatalog::parseDesktopFile(const QString &path, const QString &id, AppEntry &out)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    bool inEntry = false, noDisplay = false, hidden = false;
    QString type, onlyShowIn, notShowIn;
    out = AppEntry{};
    out.id = id;
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inEntry = (line == QLatin1String("[Desktop Entry]"));
            continue;
        }
        if (!inEntry || line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq < 0)
            continue;
        const QString key = line.left(eq).trimmed(), val = line.mid(eq + 1).trimmed();
        if (key == QLatin1String("Name") && out.name.isEmpty()) out.name = val;
        else if (key == QLatin1String("Comment") && out.comment.isEmpty()) out.comment = val;
        else if (key == QLatin1String("Icon")) out.icon = val;
        else if (key == QLatin1String("Exec")) out.exec = val;
        else if (key == QLatin1String("Type")) type = val;
        else if (key == QLatin1String("NoDisplay")) noDisplay = (val == QLatin1String("true"));
        else if (key == QLatin1String("Hidden")) hidden = (val == QLatin1String("true"));
        else if (key == QLatin1String("Terminal")) out.terminal = (val == QLatin1String("true"));
        else if (key == QLatin1String("Categories")) out.categories = val.split(QLatin1Char(';'), Qt::SkipEmptyParts);
        else if (key == QLatin1String("OnlyShowIn")) onlyShowIn = val;
        else if (key == QLatin1String("NotShowIn")) notShowIn = val;
        else if (key == QLatin1String("TryExec") && !val.isEmpty()
                 && QStandardPaths::findExecutable(val).isEmpty() && !QFile::exists(val))
            return false; // advertised binary is not actually installed
    }
    if (type != QLatin1String("Application") || noDisplay || hidden || out.name.isEmpty() || out.exec.isEmpty())
        return false;
    if (!onlyShowIn.isEmpty() && !onlyShowIn.split(QLatin1Char(';')).contains(QLatin1String("KDE")))
        return false;
    if (notShowIn.split(QLatin1Char(';')).contains(QLatin1String("KDE")))
        return false;
    return true;
}

void AppCatalog::reload()
{
    QList<AppEntry> found;
    QSet<QString> seen;
    for (const QString &dir : applicationDirs()) {
        QDirIterator it(dir, {QStringLiteral("*.desktop")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            QString id = QDir(dir).relativeFilePath(path);
            id.replace(QLatin1Char('/'), QLatin1Char('-'));
            if (seen.contains(id)) // earlier dirs (user) override later (system)
                continue;
            AppEntry e;
            if (parseDesktopFile(path, id, e)) {
                seen.insert(id);
                found.append(e);
            }
        }
    }
    std::sort(found.begin(), found.end(), [](const AppEntry &a, const AppEntry &b) {
        return a.name.compare(b.name, Qt::CaseInsensitive) < 0;
    });
    beginResetModel();
    m_all = found;
    m_visible = found;
    endResetModel();
    emit reloaded();
    if (!m_filter.isEmpty())
        applyFilter();
}

void AppCatalog::setFilter(const QString &f)
{
    if (f == m_filter)
        return;
    m_filter = f;
    applyFilter();
    emit filterChanged();
}

void AppCatalog::applyFilter()
{
    beginResetModel();
    if (m_filter.isEmpty()) {
        m_visible = m_all;
    } else {
        m_visible.clear();
        for (const AppEntry &a : std::as_const(m_all))
            if (a.name.contains(m_filter, Qt::CaseInsensitive) || a.comment.contains(m_filter, Qt::CaseInsensitive))
                m_visible.append(a);
    }
    endResetModel();
}

const AppEntry *AppCatalog::find(const QString &id) const
{
    const QString want = id.endsWith(QLatin1String(".desktop")) ? id : id + QStringLiteral(".desktop");
    for (const AppEntry &a : m_all)
        if (a.id == want)
            return &a;
    return nullptr;
}

bool AppCatalog::has(const QString &desktopId) const { return find(desktopId) != nullptr; }

QString AppCatalog::firstInstalled(const QStringList &candidates) const
{
    for (const QString &c : candidates)
        if (const AppEntry *a = find(c))
            return a->id;
    return {};
}

bool AppCatalog::launch(const QString &desktopId)
{
    const AppEntry *a = find(desktopId);
    if (!a)
        return false;
    QStringList argv = QProcess::splitCommand(stripFieldCodes(a->exec));
    if (argv.isEmpty())
        return false;
    if (a->terminal) {
        argv = QStringList{QStringLiteral("konsole"), QStringLiteral("-e")} + argv;
    }
    const QString program = argv.takeFirst();
    return QProcess::startDetached(program, argv);
}

bool AppCatalog::launchFirst(const QStringList &candidates)
{
    const QString id = firstInstalled(candidates);
    return !id.isEmpty() && launch(id);
}

bool AppCatalog::openHome()
{
    // Prefer the installed KDE file manager; fall back to the desktop's handler.
    if (launchFirst({QStringLiteral("org.kde.dolphin")})) {
        return true;
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(QDir::homePath()));
}

QVariantList AppCatalog::appsInCategories(const QStringList &categories) const
{
    QVariantList out;
    for (const AppEntry &a : m_all) {
        for (const QString &c : categories) {
            if (a.categories.contains(c)) {
                out.append(QVariantMap{{QStringLiteral("appId"), a.id}, {QStringLiteral("name"), a.name},
                                       {QStringLiteral("iconName"), a.icon}, {QStringLiteral("comment"), a.comment}});
                break;
            }
        }
    }
    return out;
}

bool AppCatalog::runCommand(const QString &program, const QStringList &args)
{
    return QProcess::startDetached(program, args);
}
