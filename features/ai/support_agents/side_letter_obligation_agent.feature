Feature: Side letter obligation tracking
  As a fund manager
  I want side letter obligations extracted, reviewed, projected into tasks, and alerted on
  So that no covenant a side letter creates is ever missed

  # Extraction never activates anything: obligations wait in pending_review until
  # counsel approves them; only then do tasks and due-date alerts exist.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant GP as GP Ops
  #   participant A as SideLetterObligationAgent
  #   participant O as SideLetterObligation
  #   participant C as Counsel
  #   participant T as Task / TaskRecurrenceRule
  #   participant E as Enforcement (daily)
  #   GP->>A: run extraction on commitment
  #   A->>O: create obligations (pending_review, cited clauses only)
  #   C->>O: approve (owner required) / reject
  #   O->>T: approved + dated -> project tasks
  #   E->>T: scan upcoming / due / overdue
  #   E->>GP: consolidated owner email + ObligationReminder log
  #   GP->>T: complete task
  #   T->>O: ObligationFulfillment recorded
  # ```

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And a fund with a capital commitment exists
    And there is a side letter obligation support agent

  # ── Extraction mode ────────────────────────────────────────────────────────

  Scenario: Extraction creates pending obligations behind the review gate
    Given the commitment has a side letter document
    And the LLM extracts the standard side letter obligations
    When the extraction run processes the commitment
    Then 3 obligations should be pending review for the commitment
    And no tasks should exist for any obligation
    And the side letter record should have extraction status "ai_extracted"
    And the agent report should note that 1 extracted item was discarded for missing citation

  Scenario: Re-running extraction with unchanged content is idempotent
    Given the commitment has a side letter document
    And the LLM extracts the standard side letter obligations
    When the extraction run processes the commitment
    And the extraction run processes the commitment
    Then 3 obligations should be pending review for the commitment

  Scenario: Amendment surfaces a delta without touching the approved obligation
    Given the commitment has a side letter document
    And the LLM extracts the standard side letter obligations
    And the extraction run processes the commitment
    And the reporting obligation is approved by counsel
    When the LLM extracts a changed reporting obligation
    And the extraction run processes the commitment
    Then the approved reporting obligation should be unchanged
    And a pending delta obligation should exist for clause "Section 4.3(b)"

  Scenario: Commitment without a side letter document reports an informational issue
    When the extraction run processes the commitment
    Then no obligations should exist for the commitment
    And the agent report should note that no side letter document was found

  # ── Review gate & task projection ──────────────────────────────────────────

  Scenario: Approval is blocked when the obligation has no owner
    Given a pending "one_time" obligation without an owner
    When counsel approves the obligation
    Then the approval should fail because an owner is required
    And the obligation should still be pending review

  Scenario: Approving a recurring obligation schedules recurring compliance tasks
    Given a pending "calendar_event" obligation with rrule "FREQ=MONTHLY;INTERVAL=1" owned by team "ir"
    When counsel approves the obligation
    Then the obligation should be active with a recurrence rule
    When the recurring task generator job runs for obligations
    Then recurring tasks owned by the obligation should exist with category "Compliance"

  Scenario: Approving a one-time obligation creates exactly one dated task
    Given a pending "one_time" obligation owned by team "finance" due in 30 days
    When counsel approves the obligation
    Then exactly 1 task should exist for the obligation
    And the obligation task should be due in 30 days

  Scenario: Event-triggered obligations stay armed with no task
    Given a pending "fund_event" obligation owned by team "legal"
    When counsel approves the obligation
    Then the obligation should be armed
    And exactly 0 tasks should exist for the obligation

  Scenario: Rejected obligations never generate tasks
    Given a pending "one_time" obligation owned by team "finance" due in 30 days
    When counsel rejects the obligation
    Then the obligation should be rejected
    And exactly 0 tasks should exist for the obligation

  Scenario: Firing an armed obligation creates a dated task on the spot
    Given an approved armed obligation owned by team "legal"
    When the obligation is fired with a due date 5 days out
    Then exactly 1 task should exist for the obligation
    And the obligation task should be due in 5 days

  Scenario: Completing a projected task records the fulfillment
    Given a pending "one_time" obligation owned by team "finance" due in 30 days
    And counsel approves the obligation
    When the obligation's task is completed
    Then an obligation fulfillment should be recorded from the task
    And the obligation status should be "fulfilled"

  Scenario: Waiving an obligation removes open tasks but keeps history
    Given an approved recurring obligation with one completed and one open task
    When the obligation is waived
    Then the open task should be gone
    And the completed task and its fulfillment should remain
    And the obligation status should be "waived"

  Scenario: Reverting a wrongly waived obligation restores its projections
    Given an approved recurring obligation with one completed and one open task
    When the obligation is waived
    And the waive is reverted
    Then the obligation status should be "active"
    And the obligation should be active with a recurrence rule

  # ── Enforcement mode (due-date alerts) ─────────────────────────────────────

  Scenario: Daily enforcement sends one consolidated alert per owner
    Given an owner user "counsel@fund.test" exists
    And an approved obligation owned by "counsel@fund.test" with a task due in 3 days
    And an approved obligation owned by "counsel@fund.test" with a task due today
    And an approved obligation owned by "counsel@fund.test" with a task 2 days overdue
    When the enforcement run executes
    Then exactly 1 obligation alert email should be sent to "counsel@fund.test"
    And the alert email should list 3 obligations
    And 3 obligation reminders should be logged

  Scenario: Re-running enforcement the same day sends no duplicate alerts
    Given an owner user "counsel@fund.test" exists
    And an approved obligation owned by "counsel@fund.test" with a task due today
    When the enforcement run executes
    And the enforcement run executes
    Then exactly 1 obligation alert email should be sent to "counsel@fund.test"
    And 1 obligation reminders should be logged

  Scenario: Zero reminder lead time suppresses upcoming alerts only
    Given an owner user "counsel@fund.test" exists
    And an approved obligation owned by "counsel@fund.test" with a task due in 3 days and zero lead time
    When the enforcement run executes
    Then no obligation alert emails should be sent

  Scenario: Overdue alerts escalate to the notify tag group
    Given an owner user "counsel@fund.test" exists
    And an escalation user "ops-lead@fund.test" tagged "legal" exists
    And the agent notify tag is "legal"
    And an approved obligation owned by "counsel@fund.test" with a task 2 days overdue
    When the enforcement run executes
    Then exactly 1 obligation alert email should be sent to "counsel@fund.test"
    And exactly 1 obligation alert email should be sent to "ops-lead@fund.test"
