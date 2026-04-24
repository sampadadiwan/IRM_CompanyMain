Feature: ReportBuilderSchedulerJob#due? — timezone-aware schedule evaluation

  Checks that the scheduler correctly determines when a scheduled report is
  due to run, based on frequency and last_run_at. Tests use Time.current
  so DST transitions are handled by Rails (no hardcoded UTC offsets).

  Background:
    Given a report builder entity and user
    And a report builder report exists for the entity

  # ── NIL last_run_at ──────────────────────────────────────────────────────

  Scenario: A schedule with no previous run is always due
    Given a "daily" schedule with last_run_at "nil"
    When I check if the schedule is due
    Then the schedule should be due

  # ── DAILY ────────────────────────────────────────────────────────────────

  Scenario: Daily schedule is due when last run was before today's 9 AM slot
    Given a "daily" schedule with last_run_at "2 days ago"
    When I check if the schedule is due
    Then the schedule should be due

  Scenario: Daily schedule is due when last run was before 9 AM today
    Given a "daily" schedule with last_run_at "today before 9am"
    When I check if the schedule is due
    Then the schedule should be due

  Scenario: Daily schedule is not due when already run after 9 AM today
    Given a "daily" schedule with last_run_at "today after 9am"
    When I check if the schedule is due
    Then the schedule should not be due

  # ── WEEKLY ───────────────────────────────────────────────────────────────

  Scenario: Weekly schedule is due when last run was before this Monday's 9 AM slot
    Given a "weekly" schedule with last_run_at "last Monday"
    When I check if the schedule is due
    Then the schedule should be due

  Scenario: Weekly schedule is not due when already run after this Monday's 9 AM slot
    Given a "weekly" schedule with last_run_at "this Monday after 9am"
    When I check if the schedule is due
    Then the schedule should not be due

  # ── MONTHLY ──────────────────────────────────────────────────────────────

  Scenario: Monthly schedule is due when last run was before this month's 1st 9 AM
    Given a "monthly" schedule with last_run_at "last month 1st"
    When I check if the schedule is due
    Then the schedule should be due

  Scenario: Monthly schedule is not due when already run after this month's 1st 9 AM
    Given a "monthly" schedule with last_run_at "this 1st after 9am"
    When I check if the schedule is due
    Then the schedule should not be due
