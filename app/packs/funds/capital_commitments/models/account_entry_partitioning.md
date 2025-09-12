Got it 👍 — here’s a structured **documentation draft** in Markdown format that consolidates everything we discussed about **MySQL 8 partitioning for `account_entries`**.

You can drop this straight into your internal docs:

---

# Partitioning `account_entries` in MySQL 8

## 📌 Context

The `account_entries` table in our Rails app has grown beyond **2M rows** and continues to grow. To improve performance, simplify archiving, and keep query costs predictable, we are introducing **database-native partitioning** in MySQL 8.

---

## 🔑 What is Partitioning?

Partitioning splits a single logical table into multiple **physical partitions** on disk, based on rules (e.g., by year).

* Rails still queries **one table** (`account_entries`).
* MySQL decides which partitions to use.
* Partitioning is transparent to Rails.

---

## ⚙️ Partitioning Strategy

### Partition Key

We will partition by **`reporting_date`**, since:

* Business queries are reporting-driven (e.g., “show me last 6 months of reporting data”).
* Older reporting periods are immutable.
* Dropping/archiving old reporting periods becomes simple.

### Partition Scheme

We use **RANGE partitioning by year**:

```sql
CREATE TABLE account_entries (
    id BIGINT NOT NULL AUTO_INCREMENT,
    account_id BIGINT NOT NULL,
    amount DECIMAL(12,2),
    reporting_date DATE NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    PRIMARY KEY (id, reporting_date),
    INDEX(account_id, reporting_date)
)
PARTITION BY RANGE (YEAR(reporting_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

* Each partition corresponds to a **reporting year**.
* `pmax` is a **catch-all partition** to avoid insert errors.
* New partitions are added annually:

  ```sql
  ALTER TABLE account_entries
  ADD PARTITION (PARTITION p2026 VALUES LESS THAN (2027));
  ```

---

## 🧩 Query Behavior

### Partition Pruning

* If a query **includes `reporting_date` or a range on it**, MySQL only scans relevant partitions.
* Example:

  ```ruby
  AccountEntry.where(reporting_date: 6.months.ago.to_date..Date.today)
  ```

  → MySQL scans only the last 2 partitions (`p2025`, `p2026`).

### Queries Without `reporting_date`

* Still work — **no crash**.
* But MySQL must scan **all partitions**, which is slower.
* Example:

  ```ruby
  AccountEntry.where(account_id: 123)
  ```

  → All partitions scanned; index used locally in each.

### Best Practice

Encourage queries with `reporting_date` filters or provide Rails scopes like:

```ruby
scope :last_n_months, ->(n) { where(reporting_date: n.months.ago.to_date..Date.today) }
```

---

## 🗑️ Archiving & Maintenance

* **Drop old partitions** (instant archive/delete):

  ```sql
  ALTER TABLE account_entries DROP PARTITION p2020;
  ```
* **Add new partitions** yearly in January.
* **Automate via Rails migration or cron**.

---

## 🔒 Backup with XtraBackup

* XtraBackup fully supports partitioned InnoDB tables.
* Each partition is stored as a separate `.ibd` file:

  ```
  account_entries#p#p2023.ibd
  account_entries#p#p2024.ibd
  ```
* Backups and restores treat the table as a single logical entity.
* Incremental backups also work.
* **Selective restore of one partition** is not directly supported.

---

## 🔄 Replication

* Partitioned tables replicate seamlessly in MySQL.
* **Use row-based replication (`binlog_format=ROW`)** for safety.
* DDL changes (adding/dropping partitions) replicate as single events.
* Since older partitions are immutable, replication load is light — only “hot” partitions receive inserts.

---

## ⚠️ Limitations

1. **Primary/unique keys must include the partition key**.

   * We use `(id, reporting_date)` for compliance.
2. **No foreign keys** on partitioned tables.
3. **Global indexes not supported** — indexes are partition-local.
4. **Altering schema** is more complex than with non-partitioned tables.
5. **Queries without partition key** cause full partition scans.

---

## ✅ Summary

* Partition by **`reporting_date`** using yearly **RANGE partitions**.
* **Queries remain unchanged in Rails**, but best performance requires including `reporting_date`.
* **Backups (XtraBackup)** and **replication** work transparently.
* **Maintenance** is simplified: add a new partition yearly, drop/archive old ones instantly.
* **Trade-offs**: no foreign keys, partition key required in all unique constraints, potential performance hit if queries omit `reporting_date`.

---

## 📋 Operational Playbook

1. **January each year**: add new partition.
2. **Retention cutoff reached**: drop old partitions.
3. **Monitor queries**: ensure most queries include `reporting_date`.
4. **Backup & replication**: continue as-is, no special handling required.

---

