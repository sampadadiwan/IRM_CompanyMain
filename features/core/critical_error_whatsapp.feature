@critical_error_whatsapp @rack_test
Feature: Critical production errors page on WhatsApp and do not flood email
  As the person on call for production
  I want a WhatsApp message when the database, Redis or a disk fails
  So that an outage reaches me even when Grafana's webhook path is broken

  # 2026-09-27: the DB host's disk filled and Redis went down with it. The app emailed
  # ~1000 identical "Error writing file '/tmp/...' (Errcode: 28)" errors, and Grafana's
  # WhatsApp webhook was refused with a 403 at the WAF, so nobody was paged.
  # Design: docs/operations/critical_error_whatsapp_alerts.md

  Background:
    Given critical error WhatsApp paging is switched on with a recording transport

  # ── What pages ─────────────────────────────────────────────────────────────

  Scenario: The disk-full MySQL error from the incident pages once
    When a request fails with the MySQL error "Error writing file '/tmp/MYfd=81' (OS errno 28 - No space left on device)"
    Then 1 WhatsApp page should have been sent
    And the last WhatsApp page should mention "No space left on device"
    And the last WhatsApp page should be a single line

  Scenario: Repeats of the same error are muted even when the temp file name differs
    When a request fails with the MySQL error "Error writing file '/tmp/MYfd=81' (OS errno 28 - No space left on device)"
    And a request fails with the MySQL error "Error writing file '/tmp/MYfd=92' (OS errno 28 - No space left on device)"
    Then 1 WhatsApp page should have been sent

  Scenario Outline: Other ways MySQL reports a full disk also page
    When a request fails with the MySQL error "<message>"
    Then 1 WhatsApp page should have been sent

    Examples:
      | message                                                             |
      | Got error 28 from storage engine                                    |
      | Incorrect key file for table '/tmp/#sql_1a2b_0.MYI'; try to repair it |

  Scenario: Disk-full errors on different files count as one error
    When the disk fills while writing "/var/app/shared/tmp/cache/a1.tmp", "/var/app/shared/tmp/cache/b2.tmp" and "/var/app/shared/log/c3.log"
    Then 1 WhatsApp page should have been sent

  Scenario: An ordinary SQL bug does not page
    When a request fails with the MySQL error "Unknown column 'foo' in 'where clause'"
    Then 0 WhatsApp pages should have been sent

  Scenario: An application bug does not page
    When a request fails with a "ArgumentError" saying "wrong number of arguments"
    Then 0 WhatsApp pages should have been sent

  Scenario: A database-sounding message from something other than the database does not page
    When a request fails with a "RuntimeError" saying "SMTP 421 Too many connections from your IP"
    Then 0 WhatsApp pages should have been sent

  Scenario: Redis refusing connections pages
    When a request fails with a "RedisClient::CannotConnectError" saying "Connection refused - connect(2) for 10.0.3.214:6379"
    Then 1 WhatsApp page should have been sent
    And the last WhatsApp page should mention "RedisClient::CannotConnectError"

  Scenario: A Redis timeout does not page
    When a request fails with a "RedisClient::ReadTimeoutError" saying "Waited 1.0 seconds"
    Then 0 WhatsApp pages should have been sent

  Scenario: Redis refusing writes because its disk is full pages
    When a request fails with a "RedisClient::CommandError" saying "MISCONF Redis is configured to save RDB snapshots, but it's currently unable to persist to disk"
    Then 1 WhatsApp page should have been sent
    And the last WhatsApp page should mention "MISCONF"

  Scenario: An ordinary Redis command error does not page
    When a request fails with a "RedisClient::CommandError" saying "WRONGTYPE Operation against a key holding the wrong kind of value"
    Then 0 WhatsApp pages should have been sent

  Scenario: A cascade of different errors is capped per process
    When 8 different disk-full errors are raised
    Then 5 WhatsApp pages should have been sent

  # ── Failed sends ───────────────────────────────────────────────────────────

  Scenario: A page WATI rejects is not muted, so the next occurrence retries
    Given WATI rejects the next WhatsApp page
    When a request fails with the MySQL error "Error writing file '/tmp/MYfd=81' (OS errno 28 - No space left on device)"
    And a request fails with the MySQL error "Error writing file '/tmp/MYfd=92' (OS errno 28 - No space left on device)"
    Then 2 WhatsApp pages should have been attempted
    And 1 WhatsApp page should have been sent

  # ── Sidekiq losing Redis ───────────────────────────────────────────────────

  Scenario: Sidekiq losing Redis pages once when Redis is still down a minute later
    Given Redis will still be unreachable when rechecked
    When Sidekiq's fetch loop reports 8 Redis failures
    Then 1 WhatsApp page should have been sent
    And the last WhatsApp page should mention "Sidekiq cannot reach Redis"

  Scenario: A Redis blip that heals within the minute does not page
    Given Redis will be reachable again when rechecked
    When Sidekiq's fetch loop reports 8 Redis failures
    Then 0 WhatsApp pages should have been sent

  # ── Wiring and email grouping ──────────────────────────────────────────────

  Scenario: Every reported error reaches the pager, even ones email grouping holds back
    When the disk-full MySQL error is reported through exception_notification 3 times, with the WhatsApp mute expiring in between
    Then 3 WhatsApp pages should have been sent

  Scenario: Critical errors are emailed on their 1st, 2nd, 4th and 8th occurrence
    Then email grouping should send a critical error on occurrences "1,2,4,8" of 1 to 10

  Scenario: Ordinary errors are emailed on every occurrence
    Then email grouping should send an ordinary error on occurrences "1,2,3,4,5,6,7,8,9,10" of 1 to 10

  Scenario: Email grouping counts in process memory, not in the database-backed Rails.cache
    Then exception_notification should group errors in an in-memory store

  Scenario: Each failing request is reported once
    Then the middleware stack should contain ExceptionNotification::Rack exactly once

  Scenario: Nothing pages outside production
    Given critical error WhatsApp paging is left at its default
    When a request fails with the MySQL error "Error writing file '/tmp/MYfd=81' (OS errno 28 - No space left on device)"
    Then 0 WhatsApp pages should have been sent
