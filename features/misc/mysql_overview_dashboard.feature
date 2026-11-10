@rack_test
Feature: MySQL Overview's replication panels read the replica metrics in both regions
  mysqld_exporter names the replica metrics after SHOW REPLICA STATUS columns, and the naming
  depends on the exporter: IN emits *_master / slave_*, US emits *_source / replica_*. The MySQL
  Overview board was hand-made per region and drifted - IN's "Binlog Accumulation" queried
  mysql_slave_status_master_log_pos, which neither region emits, and read "No data" (2026-11-10).
  rake grafana:provision:dashboards now patches the board (fix_mysql_overview_replication) so every
  replication query is "new name or old name" - one board, right in both regions.

  These scenarios patch the saved board JSON in memory - they touch no Grafana.

  # H1 — Happy path: every replication panel queries both namings, however often it is provisioned
  # E1 — Edge case: re-running the patch leaves the same queries (no "or ... or ..." pile-up)
  Scenario Outline: A replication panel queries the new and the old metric name
    When the MySQL Overview replication patch is applied twice to the "<region>" board
    Then the "<panel>" panel's "<ref>" query reads both "<new_name>" and "<old_name>"

    Examples:
      | region | panel                                       | ref | new_name                     | old_name                     |
      | in     | Replication Lag                             | A   | seconds_behind_source        | seconds_behind_master        |
      | in     | Replication Lag (Seconds Behind Master)     | A   | seconds_behind_source        | seconds_behind_master        |
      | in     | IO Thread Running                           | A   | replica_io_running           | slave_io_running             |
      | in     | SQL Thread Running                          | A   | replica_sql_running          | slave_sql_running            |
      | in     | Replication I/O & SQL Thread Status         | A   | replica_io_running           | slave_io_running             |
      | in     | Replication I/O & SQL Thread Status         | B   | replica_sql_running          | slave_sql_running            |
      | in     | Binlog Accumulation (Primary → Replica gap) | A   | read_source_log_pos          | read_master_log_pos          |
      | us     | Binlog Accumulation (Primary → Replica gap) | A   | exec_source_log_pos          | exec_master_log_pos          |

  # X1 — Error case (prod IN, 2026-11-10): the metric no exporter emits is gone
  Scenario Outline: No panel queries a metric neither region emits
    When the MySQL Overview replication patch is applied twice to the "<region>" board
    Then no MySQL Overview query reads "mysql_slave_status_master_log_pos"
    And the MySQL Overview panels other than replication are unchanged

    Examples:
      | region |
      | in     |
      | us     |
