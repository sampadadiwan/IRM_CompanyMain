Feature: ReportBuilderSchedulerJob — automated report delivery

  ReportSchedule shares its due-date math with AgentSchedule via the Schedulable
  concern + NextRunCalculator: creating/editing a schedule precomputes next_run_at,
  and the scheduler job just polls ReportSchedule.due (next_run_at <= now, enabled).

  Background:
    Given a report builder entity and user
    And a report builder report exists for the entity

  # ── Cron wiring ──────────────────────────────────────────────────────────
  # No DB needed: parses config/schedule.rb the same way `whenever` does at
  # deploy time, without touching the real system crontab.

  Scenario: config/schedule.rb wires ReportBuilderSchedulerJob into the hourly cron
    When I render the whenever crontab from config/schedule.rb
    Then the rendered crontab should invoke "ReportBuilderSchedulerJob.perform_later"

  # ── next_run_at calculation (shared with AgentSchedule via Schedulable) ───

  Scenario: Creating a schedule computes a future next_run_at
    Given a "daily" schedule for the report
    Then the schedule's next_run_at should be in the future

  # ── ReportBuilderSchedulerJob#perform — end-to-end ────────────────────────
  # ReportBuilderSchedulerJob#perform is what config/schedule.rb invokes hourly
  # in production via `runner "ReportBuilderSchedulerJob.perform_later"`. These
  # scenarios cover the full chain: scheduler -> export job -> document + email.

  Scenario: Running the scheduler triggers an export and emails recipients for a due schedule
    Given the entity has a root folder
    And a "daily" schedule for the report
    And the schedule's next_run_at is in the past
    And the email queue is empty
    When I run the report builder scheduler job
    Then an email should be delivered
    And the delivered email subject should include "Test Report"
    And the schedule's last_run_at should be updated
    And the schedule's next_run_at should be in the future

  Scenario: Running the scheduler does nothing for a schedule that is not due yet
    Given the entity has a root folder
    And a "daily" schedule for the report
    And the schedule's next_run_at is in the future
    And the email queue is empty
    When I run the report builder scheduler job
    Then no email should be delivered
    And the schedule's last_run_at should not have changed
    And the schedule's next_run_at should not have changed

  Scenario: Running the scheduler skips disabled schedules even when due
    Given the entity has a root folder
    And a "daily" schedule for the report
    And the schedule's next_run_at is in the past
    And the schedule is disabled
    And the email queue is empty
    When I run the report builder scheduler job
    Then no email should be delivered
    And the schedule's last_run_at should not have changed
