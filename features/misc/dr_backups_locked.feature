@rack_test
Feature: Replica backups cannot be deleted for 30 days, by anyone
  Backups and documents replicate to a second region, but the app's own keys (S3 full access)
  could delete every version in both copies. The replica buckets get S3 Object Lock in
  COMPLIANCE mode with a 30-day default retention: no key, not even AWS root, can delete or
  shorten the lock on anything written there. Primary buckets are never locked. These scenarios
  exercise Dr::BackupLock; the AWS behaviour is proven by the task's PROVE=1 step on staging.

  # H1 — Happy path: today's staging replica
  Scenario: An unlocked replica gets Object Lock and a 30-day compliance default
    When the lock plan is made for a replica with Object Lock "off"
    Then the plan is "enable Object Lock and set COMPLIANCE 30 days"

  # H2 — Happy path: running it again changes nothing
  Scenario: A replica already locked for 30 days in compliance mode is left alone
    When the lock plan is made for a replica with Object Lock "on", mode "COMPLIANCE" and 30 days
    Then the plan is "nothing to do"

  # E1 — Edge case: never weaken a longer lock
  Scenario: A longer compliance lock is left as it is
    When the lock plan is made for a replica with Object Lock "on", mode "COMPLIANCE" and 60 days
    Then the plan is "nothing to do"

  # E2 — Edge case: lock enabled but no default rule
  Scenario: A replica with Object Lock but no default retention gets the rule
    When the lock plan is made for a replica with Object Lock "on" and no default retention
    Then the plan is "set COMPLIANCE 30 days"

  # H3 — Happy path: readiness passes
  Scenario: A 30-day compliance lock passes readiness
    When the replica lock is graded with Object Lock "on", mode "COMPLIANCE" and 30 days
    Then the lock grade is "ok"

  # X1 — Error case: governance can be bypassed by the app's own keys
  Scenario: A governance lock fails readiness
    When the replica lock is graded with Object Lock "on", mode "GOVERNANCE" and 30 days
    Then the lock grade is "fail" mentioning "can be bypassed"

  # X2 — Error case: today's state
  Scenario: An unlocked replica fails readiness
    When the replica lock is graded with Object Lock "off"
    Then the lock grade is "fail" mentioning "can be deleted"

  # X5 — Error case
  Scenario: A lock shorter than 30 days fails readiness
    When the replica lock is graded with Object Lock "on", mode "COMPLIANCE" and 7 days
    Then the lock grade is "fail" mentioning "shorter than 30 days"

  # X3 — Error case: a primary bucket is never a target
  Scenario: Only the primaries' replication destinations are locked, never a primary
    Given the primary buckets "docs.altx.com.staging-backup-xtra" and "docs.altx.com.staging"
    And their replication destinations "docs.altx.com.staging-replica-backup-xtra", "docs.altx.com.staging-replica" and "docs.altx.com.staging"
    When the buckets to lock are chosen
    Then they are "docs.altx.com.staging-replica-backup-xtra" and "docs.altx.com.staging-replica"

  # X4 — Error case: production needs an explicit go-ahead
  Scenario Outline: Production is refused without ALLOW_PRODUCTION
    When locking is asked for "<env>" with ALLOW_PRODUCTION "<allow>"
    Then locking is "<verdict>"

    Examples:
      | env           | allow | verdict |
      | staging.in    |       | allowed |
      | production.in |       | refused |
      | production.in | 1     | allowed |

  # E3 — Edge case: replication into a locked bucket needs two read permissions on the role
  Scenario: The replication role gains the lock permissions once, and only once
    Given a replication role policy that reads source versions without the lock permissions
    When the lock permissions are added
    Then the reading statement includes "s3:GetObjectRetention" and "s3:GetObjectLegalHold"
    And adding them again changes nothing
