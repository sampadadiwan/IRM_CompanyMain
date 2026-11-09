@rack_test
Feature: The MySQL replica refuses writes, and a promoted replica accepts them again
  The prod US replica ran with read_only = 0 and super_read_only = 0 (2026-11-09): any client - the
  app logs in as root, which read_only alone does not stop - could write to it and make it drift
  from the primary. rake "ops:replica_read_only[<env>]" sets both, persisted; reset_replication sets
  them on every replica it connects, and dr:fix:promote_replica clears them on promotion.

  These scenarios exercise the pure guard (lib/replica_read_only.rb) - they touch no box.

  # H1 — Happy path: the US replica as found
  Scenario: A healthy replica of the primary is made read-only
    Given a replica "10.0.4.28" replicating from "10.0.3.214" with IO "Yes" and SQL "Yes"
    When making it read-only is planned with primary "10.0.3.214", read_only "0" and super_read_only "0"
    Then the read-only plan is "apply"

  # E1 — Edge case: a re-run finds it done
  Scenario: A replica already read-only is left alone
    Given a replica "10.0.4.28" replicating from "10.0.3.214" with IO "Yes" and SQL "Yes"
    When making it read-only is planned with primary "10.0.3.214", read_only "1" and super_read_only "1"
    Then the read-only plan is "unchanged"

  # X1 — Error case: staging's "replica" is the primary itself - never read-only
  Scenario: The primary is never made read-only
    Given a replica "10.0.3.138" replicating from "10.0.3.214" with IO "Yes" and SQL "Yes"
    When making it read-only is planned with primary "10.0.3.138", read_only "0" and super_read_only "0"
    Then the read-only plan is "refused" mentioning "no separate replica"

  # X2 — Error case: a box that does not replicate is not a replica, whatever the credentials say
  Scenario: A box without replication is refused
    Given a box "10.0.4.28" with no replication
    When making it read-only is planned with primary "10.0.3.214", read_only "0" and super_read_only "0"
    Then the read-only plan is "refused" mentioning "not replicating"

  # X3 — Error case: replicating from somewhere else
  Scenario: A replica of another source is refused
    Given a replica "10.0.4.28" replicating from "10.0.9.9" with IO "Yes" and SQL "Yes"
    When making it read-only is planned with primary "10.0.3.214", read_only "0" and super_read_only "0"
    Then the read-only plan is "refused" mentioning "not the primary"

  # X4 — Error case: broken replication is fixed first
  Scenario: Unhealthy replication is refused
    Given a replica "10.0.4.28" replicating from "10.0.3.214" with IO "Yes" and SQL "No"
    When making it read-only is planned with primary "10.0.3.214", read_only "0" and super_read_only "0"
    Then the read-only plan is "refused" mentioning "not healthy"

  # H2 — Happy path: SHOW REPLICA STATUS\G is read field by field
  Scenario: Replica status lines are parsed, the row banner ignored
    When the replica status text is "*************************** 1. row ***************************\n  Source_Host: 10.0.3.214\n  Replica_IO_Running: Yes\nread_only: 0"
    Then the parsed Source_Host is "10.0.3.214" and there is no "read_only" field

  # H3 — Happy path: the DR paths keep the setting consistent
  Scenario: Replication setup turns read-only on and promotion turns it off
    Then reset_replication sets "SET PERSIST super_read_only = ON" unless the replica is the primary
    And promote_replica runs "SET PERSIST super_read_only = OFF; SET PERSIST read_only = OFF;"
