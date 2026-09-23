#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// A list model of plain JS objects that updates in place. sync() diffs the
// incoming array against the current rows by `key` and emits the minimal
// inserts, removes, moves and dataChanged, so views keep their scroll
// position and delegates when data refreshes. Delegates read the object via
// `required property var modelData`. For ListView sections, set
// sectionKey and use section.property: "section".
class KeyedListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(QString sectionKey READ sectionKey WRITE setSectionKey NOTIFY sectionKeyChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    explicit KeyedListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString key() const { return m_key; }
    void setKey(const QString &key);
    QString sectionKey() const { return m_sectionKey; }
    void setSectionKey(const QString &key);

    Q_INVOKABLE void sync(const QVariantList &items);
    Q_INVOKABLE void append(const QVariantList &items);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QVariant get(int row) const;
    Q_INVOKABLE int indexOf(const QVariant &keyValue) const;

signals:
    void keyChanged();
    void sectionKeyChanged();
    void countChanged();

private:
    QString keyOf(const QVariant &item) const;

    QString m_key = QStringLiteral("id");
    QString m_sectionKey;
    QVariantList m_items;
};
