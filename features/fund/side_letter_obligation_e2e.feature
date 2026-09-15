Feature: Side letter obligation lifecycle end-to-end
  As a fund manager and counsel
  I want the full covenant lifecycle to work through the UI
  So that a side letter upload reliably ends in tracked tasks, alerts, and an audit trail

  # The one journey that exercises every piece in sequence:
  #
  # ```mermaid
  # sequenceDiagram
  #   participant GP as GP Ops
  #   participant Doc as Document upload hook
  #   participant A as SideLetterObligationAgent
  #   participant UI as Obligation Matrix UI
  #   participant T as Task system
  #   participant E as Enforcement run
  #   GP->>Doc: upload "Side Letter" to commitment
  #   Doc->>A: auto-extract (agent config: on upload)
  #   A->>UI: 3 obligations pending review
  #   GP->>UI: assign owner, approve each
  #   UI->>T: recurring rule + one-time task; armed stays taskless
  #   GP->>UI: fire armed obligation with deadline
  #   E->>GP: consolidated due-date alert email
  #   GP->>T: complete task
  #   T->>UI: fulfillment visible on obligation page
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And a fund with a capital commitment exists
    And there is a side letter obligation support agent
    And the agent auto-extracts side letters on upload
    And the LLM extracts the standard side letter obligations

  Scenario: Upload to fulfillment — the full obligation lifecycle through the UI
    # 1. Uploading the side letter triggers extraction (production upload hook)
    When the side letter document is uploaded to the commitment
    Then 3 obligations should be pending review for the commitment
    And no tasks should exist for any obligation

    # 2. The commitment page surfaces the side letter and its review backlog
    When I visit the commitment page
    Then I should see the side letter card with 3 obligations pending review

    # 3. Counsel assigns an owner and approves the recurring obligation
    When I assign the obligation "Quarterly ESG report" to myself via the edit form
    And I approve the obligation "Quarterly ESG report" from the matrix
    Then the obligation "Quarterly ESG report" should be approved with a recurrence rule

    # 4. The nightly generator materializes recurring occurrences as board tasks
    When the recurring task generator job runs for obligations
    Then the task board should show a task for "Quarterly ESG report"

    # 5. The one-time obligation projects a single dated task on approval
    When I assign the obligation "Audited financials" to myself via the edit form
    And I approve the obligation "Audited financials" from the matrix
    Then the task board should show a task for "Audited financials"

    # 6. The event-triggered obligation stays armed until fired with a deadline
    When I assign the obligation "Key person departure notice" to myself via the edit form
    And I approve the obligation "Key person departure notice" from the matrix
    Then I should see the obligation row "Key person departure notice" with status "Armed"
    When I fire the obligation "Key person departure notice" with due date 5 days from now
    Then the task board should show a task for "Key person departure notice"

    # 7. Enforcement consolidates everything due into one email to the owner
    Given the task for "Audited financials" is due today
    When the enforcement run executes
    Then exactly 1 obligation alert email should be sent to me
    And 2 obligation reminders should be logged

    # 8. Completing the task records the fulfillment on the obligation page
    When the task for "Audited financials" is completed
    And I visit the obligation page for "Audited financials"
    Then I should see the fulfillment recorded for the completed task
    And the obligation "Audited financials" should have status "fulfilled"

    # 9. The side letter page lists every covenant task in the standard tasks grid
    When I visit the side letter page for the commitment
    Then the covenant tasks grid should list every covenant task
    And the covenant tasks filter bar should stay scoped to the side letter

    # 10. The obligation page's Tasks tab uses the same grid
    When I visit the obligation page for "Quarterly ESG report"
    Then the covenant tasks grid should list that obligation's tasks
    And I should see the "Fulfillment History" and "Alerts Sent" tabs

    # 11. The tasks board scoped to the side letter shows only its covenant tasks
    Given an unrelated task "Prepare quarterly newsletter" exists
    When I view the covenant tasks board for the side letter
    Then the board should list the covenant tasks but not "Prepare quarterly newsletter"
