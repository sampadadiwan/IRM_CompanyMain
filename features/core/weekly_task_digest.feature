@rack_test
Feature: Weekly task digest email
  Every Friday, employees of an Investment Fund entity who are tagged "Tasks" receive
  one email summarising the week: tasks completed this week, tasks due next week and
  tasks that are delayed.

  The digest is scoped through TaskPolicy, so each recipient sees exactly the tasks
  they can already open in the app. See docs/modules/tasks/weekly_task_digest_prd.md.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the weekly task digest enabled
    And the user is tagged "Tasks"

  # ─────────────────────────────────────────────────────────────────────────
  # 1. The happy path — all three sections populated
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: A tagged fund employee receives a digest with all three sections
    Given the following digest tasks exist:
      | details              | due_date   | completed_on |
      | Close Q3 books       |            | 2026-09-09   |
      | Sign the SHA         | 2026-09-16 |              |
      | Chase the audit file | 2026-08-21 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 1 weekly digest email is sent
    And the weekly digest email subject contains "1 delayed, 1 due next week"
    And the weekly digest email body contains "Close Q3 books"
    And the weekly digest email body contains "Sign the SHA"
    And the weekly digest email body contains "Chase the audit file"
    And the weekly digest email body contains "21 days"

  # The digest is raised as a Noticed event, so it lands in the in-app bell and the
  # notifications report as well as the inbox, and picks up bounce tracking on the way.
  Scenario: The digest is delivered through the notifier, not straight to the mailer
    Given the following digest tasks exist:
      | details              | due_date   | completed_on |
      | Close Q3 books       |            | 2026-09-09   |
      | Sign the SHA         | 2026-09-16 |              |
      | Chase the audit file | 2026-08-21 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then an in-app weekly digest notification is recorded for the user
    And the in-app weekly digest notification message is "Weekly tasks: 1 delayed, 1 due next week"

  # The task's Response field is its running note. A delayed row that carries the latest
  # word on it is far more useful than one that only says it slipped.
  Scenario: A task's note is carried into the digest row
    Given the following digest tasks exist:
      | details              | due_date   | completed_on | note                                    |
      | Chase the audit file | 2026-08-21 |              | Auditor has the draft, signing Monday.  |
      | Sign the SHA         | 2026-09-16 |              |                                         |
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email body contains "Auditor has the draft, signing Monday."
    And the weekly digest email text body contains "Note: Auditor has the draft, signing Monday."

  Scenario: The stat band agrees with the rows beneath it
    Given the following digest tasks exist:
      | details              | due_date   | completed_on |
      | Close Q3 books       |            | 2026-09-09   |
      | Sign the SHA         | 2026-09-16 |              |
      | Chase the audit file | 2026-08-21 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email text body contains "1 done this week | 1 due next week | 1 delayed | 2 open total"

  # Regression guard for the EmailDateLocalization contract (CLAUDE.md): mailer views
  # render "Aug 21, 2026" whatever locale the triggering job was running under, and a
  # bare Date#to_s under Rails 8 would print ISO instead.
  Scenario: Dates render in the email format, not the screen format
    Given the following digest tasks exist:
      | details              | due_date   | completed_on |
      | Chase the audit file | 2026-08-21 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email body contains "Aug 21, 2026"
    And the weekly digest email body does not contain "21/08/2026"

  # ─────────────────────────────────────────────────────────────────────────
  # 2. Gating — entity type, entity setting, tag, active
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: A non-fund entity is not sent a digest
    Given the entity type is "Company"
    And the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  Scenario: An Angel Fund is out of scope for now
    Given the entity type is "Angel Fund"
    And the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  Scenario: An entity with the digest turned off sends nothing
    Given the entity has the weekly task digest disabled
    And the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  Scenario: An employee without the Tasks tag receives nothing
    Given the user is not tagged
    And the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  Scenario: An inactive employee receives nothing
    Given the user is inactive
    And the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  # ─────────────────────────────────────────────────────────────────────────
  # 3. What counts as a section
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: Nothing in any section means no email at all
    When the weekly task digest job runs on "2026-09-11"
    Then 0 weekly digest emails are sent

  Scenario: Completed work alone still earns a digest
    Given the following digest tasks exist:
      | details        | due_date | completed_on |
      | Close Q3 books |          | 2026-09-09   |
    When the weekly task digest job runs on "2026-09-11"
    Then 1 weekly digest email is sent
    And the weekly digest email subject contains "all on track, 0 due next week"

  Scenario: The delayed section reaches back 90 days and no further
    Given the following digest tasks exist:
      | details         | due_date   | completed_on |
      | Ancient task    | 2026-04-01 |              |
      | Recent overdue  | 2026-07-20 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email subject contains "1 delayed"
    And the weekly digest email body contains "Recent overdue"
    And the weekly digest email body does not contain "Ancient task"

  Scenario: A task with no due date appears in no section
    Given the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Undated task |            |              |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then 1 weekly digest email is sent
    And the weekly digest email body does not contain "Undated task"

  # A "View all" link that resolves its own week at click time would send a Monday
  # reader to a completely different set from the one the email counted.
  Scenario: Section links pin the digest's own dates
    Given the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email links to the pinned week "2026-09-14" through "2026-09-20"

  # The notification row is written when the job runs; the digest is rebuilt when the
  # mailer runs. If everything closes in between, that is a skip, not a failed send.
  Scenario: A digest that empties before delivery is recorded as a skip
    Given the following digest tasks exist:
      | details      | due_date   | completed_on |
      | Sign the SHA | 2026-09-16 |              |
    When every task is closed between the job and the delivery on "2026-09-11"
    Then 0 weekly digest emails are sent
    And the weekly digest notification records a skip reason

  Scenario: A capped section links to the rest
    Given 20 open tasks are due next week
    When the weekly task digest job runs on "2026-09-11"
    Then the weekly digest email subject contains "20 due next week"
    And the weekly digest email body contains "5 more tasks"

  # ─────────────────────────────────────────────────────────────────────────
  # 4. Per-recipient policy scoping
  # ─────────────────────────────────────────────────────────────────────────

  Scenario: An employee sees only their own tasks, an admin sees the fund
    Given there is another employee "Priya" tagged "Tasks" with role "employee"
    And the following digest tasks exist:
      | details         | due_date   | completed_on | assigned_to |
      | Admin only task | 2026-09-16 |              |             |
      | Priya task      | 2026-09-16 |              | other       |
    When the weekly task digest job runs on "2026-09-11"
    Then 2 weekly digest emails are sent
    And the weekly digest email to the other employee contains "Priya task"
    And the weekly digest email to the other employee does not contain "Admin only task"
    And the weekly digest email to the user contains "Admin only task"
    And the weekly digest email to the user contains "Priya task"
