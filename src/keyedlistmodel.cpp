#include "keyedlistmodel.h"

#include <QHash>
#include <QSet>

namespace {
constexpr int kItemRole = Qt::UserRole + 1;
constexpr int kSectionRole = Qt::UserRole + 2;
}

KeyedListModel::KeyedListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int KeyedListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant KeyedListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    if (role == kItemRole)
        return m_items.at(index.row());
    if (role == kSectionRole)
        return m_items.at(index.row()).toMap().value(m_sectionKey);
    return {};
}

QHash<int, QByteArray> KeyedListModel::roleNames() const
{
    return {{kItemRole, "modelData"}, {kSectionRole, "section"}};
}

void KeyedListModel::setKey(const QString &key)
{
    if (m_key == key)
        return;
    m_key = key;
    emit keyChanged();
}

void KeyedListModel::setSectionKey(const QString &key)
{
    if (m_sectionKey == key)
        return;
    m_sectionKey = key;
    emit sectionKeyChanged();
    if (!m_items.isEmpty())
        emit dataChanged(index(0), index(int(m_items.size()) - 1), {kSectionRole});
}

QString KeyedListModel::keyOf(const QVariant &item) const
{
    return item.toMap().value(m_key).toString();
}

void KeyedListModel::sync(const QVariantList &items)
{
    const int before = int(m_items.size());

    // 1. Drop rows whose key is gone.
    QSet<QString> incoming;
    for (const QVariant &item : items)
        incoming.insert(keyOf(item));
    for (int row = int(m_items.size()) - 1; row >= 0; --row) {
        if (!incoming.contains(keyOf(m_items.at(row)))) {
            beginRemoveRows({}, row, row);
            m_items.removeAt(row);
            endRemoveRows();
        }
    }

    // 2. Walk the target order, moving, inserting or refreshing each row.
    for (int target = 0; target < items.size(); ++target) {
        const QVariant &item = items.at(target);
        const QString key = keyOf(item);
        if (target < m_items.size() && keyOf(m_items.at(target)) == key) {
            if (m_items.at(target) != item) {
                m_items[target] = item;
                emit dataChanged(index(target), index(target), {kItemRole, kSectionRole});
            }
            continue;
        }
        int found = -1;
        for (int row = target + 1; row < m_items.size(); ++row) {
            if (keyOf(m_items.at(row)) == key) {
                found = row;
                break;
            }
        }
        if (found >= 0) {
            beginMoveRows({}, found, found, {}, target);
            m_items.move(found, target);
            endMoveRows();
            if (m_items.at(target) != item) {
                m_items[target] = item;
                emit dataChanged(index(target), index(target), {kItemRole, kSectionRole});
            }
        } else {
            beginInsertRows({}, target, target);
            m_items.insert(target, item);
            endInsertRows();
        }
    }

    if (m_items.size() != before)
        emit countChanged();
}

void KeyedListModel::append(const QVariantList &items)
{
    if (items.isEmpty())
        return;
    beginInsertRows({}, int(m_items.size()), int(m_items.size() + items.size() - 1));
    m_items.append(items);
    endInsertRows();
    emit countChanged();
}

void KeyedListModel::clear()
{
    if (m_items.isEmpty())
        return;
    beginResetModel();
    m_items.clear();
    endResetModel();
    emit countChanged();
}

QVariant KeyedListModel::get(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items.at(row) : QVariant();
}

int KeyedListModel::indexOf(const QVariant &keyValue) const
{
    const QString wanted = keyValue.toString();
    for (int row = 0; row < m_items.size(); ++row) {
        if (keyOf(m_items.at(row)) == wanted)
            return row;
    }
    return -1;
}
