Feature: Portco KPI Self-Reporting Workflow
  As a fund admin I want to request KPI data from portfolio companies via email links
  As a portco user I want to save drafts and submit my report clearly
  So that both sides can track submission status without ambiguity

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the portfolio company has an approved portco user "first_name=PortCoUser"
    And the email queue is cleared

  # ─────────────────────────────────────────────────────────
  # 1. Status badge starts at shell_created
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_status
  Scenario: New KPI report shell shows shell_created status badge
    Given I am logged in as the fund admin
    When I create a KPI report shell for "TestStartup" as of "2025-03-31" with period "Quarter"
    Then I should see the status badge "Shell Created"

  # ─────────────────────────────────────────────────────────
  # 2. Send notification → link_sent + email with expiry date
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_notification
  Scenario: Sending a notification advances status to link_sent and email shows expiry date
    Given I am logged in as the fund admin
    And a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I send a portco notification for "TestStartup" with date "2025-03-31"
    Then the KPI report for "TestStartup" should have status "link_sent"
    And the portco user receives a reminder email
    And the reminder email body contains the link expiry date
    And the reminder email body contains "Save Draft"
    And the reminder email body contains "Submit Report"

  # ─────────────────────────────────────────────────────────
  # 3. Invalid date → inline error, no job enqueued
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_validation
  Scenario: Sending a notification with an invalid date shows an inline error
    Given I am logged in as the fund admin
    And a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I attempt to send a portco notification for "TestStartup" with invalid date "not-a-date"
    Then I should see "Invalid date format"
    And the portco user receives no email

  # ─────────────────────────────────────────────────────────
  # 4. Portco pending dashboard
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_dashboard
  Scenario: Portco pending dashboard shows outstanding reports
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And I am logged in as the portco user
    When I visit the portco pending dashboard
    Then I should see "VentureFund"
    And I should see "2025-03-31" within the pending reports table
    And I should see a "Fill Report" link

  # ─────────────────────────────────────────────────────────
  # 5. Save Draft → draft_saved, fund not notified
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_draft
  Scenario: Save Draft advances status to draft_saved and does not notify the fund
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I fill in "Notes" with "Work in progress"
    And I click "Save Draft"
    Then I should see "Kpi report was successfully updated"
    And the KPI report for "TestStartup" should have status "draft_saved"
    And the status badge shows "Draft Saved"
    And the fund admin receives no submission email

  # ─────────────────────────────────────────────────────────
  # 6. Submit Report → submitted + fund admin notified
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit
  Scenario: Submit Report advances status to submitted and notifies the fund admin
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I fill in "Notes" with "Final numbers"
    And I click "Submit Report" and confirm the dialog
    Then I should see "KPI report submitted"
    And the KPI report for "TestStartup" should have status "submitted"
    And the status badge shows "Submitted"
    And the submitted_at timestamp is set on the report
    And the fund admin receives a submission notification email
    And the submission email subject contains "KPIs submitted"

  # ─────────────────────────────────────────────────────────
  # 7. Submitted report is locked for portco
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_locked
  Scenario: Submitted report shows locked UI for portco user
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    Then I should see "Report Already Submitted"
    And I should not see a "Save Draft" button
    And I should not see a "Submit Report" button

  # ─────────────────────────────────────────────────────────
  # 8. Bulk send skips already-submitted portcos
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_bulk_send
  Scenario: Bulk send notification skips already-submitted portcos
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And there is an existing portfolio company "name=OtherStartup;category=Portfolio Company"
    And the portfolio company "OtherStartup" has an approved portco user "first_name=OtherPortCoUser"
    And a KPI report shell exists for "OtherStartup" as of "2025-03-31" with status "link_sent"
    And I am logged in as the fund admin
    When I send a portco notification to all portfolio companies with date "2025-03-31"
    Then the portco user for "OtherStartup" receives a reminder email
    And the portco user for "TestStartup" receives no email

  # ─────────────────────────────────────────────────────────
  # 9. Periodic reminder job skips submitted portcos
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_periodic
  Scenario: Periodic reminder job does not re-notify already-submitted portcos
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    When the periodic KPI reminder job runs
    Then the portco user receives no email

  # ─────────────────────────────────────────────────────────
  # 10. Fund admin marks report as reviewed
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed
  Scenario: Fund admin can mark a submitted report as reviewed
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the fund admin
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    Then I should see "Mark as Reviewed"
    When I click "Mark as Reviewed" and confirm the dialog
    Then the KPI report for "TestStartup" should have status "reviewed"
    And the status badge shows "Reviewed"
    And I should not see "Mark as Reviewed"

  # ─────────────────────────────────────────────────────────
  # 11. Designated KPI contact via user tag_list
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_contact
  Scenario: Only users tagged "Kpi" receive the reminder email when the tag is set
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31"
    And the portfolio company has a second approved portco user "first_name=OtherContact"
    And the user "PortCoUser" has the tag "Kpi"
    When the portco notification service runs for the report
    Then the portco user "PortCoUser" receives a reminder email
    And the user "OtherContact" receives no email

  # ─────────────────────────────────────────────────────────
  # 12. Expired magic link → friendly redirect
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_expired_link
  Scenario: Visiting an expired magic link shows a friendly error instead of crashing
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I visit the KPI report edit page with an expired signed link
    Then I should see "This link has expired or is invalid"
    And I should not see "KPI Report"

  # ─────────────────────────────────────────────────────────
  # 13. Valid magic link — unauthenticated end-to-end flow
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_magic_link
  Scenario: Portco user can submit a KPI report via magic link without logging in
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then I should see "KPI Report"
    And I should see a "Save Draft" button
    And I should see a "Submit Report" button
    When I fill in "Notes" with "Submitted unauthenticated"
    And I click "Submit Report" and confirm the dialog
    Then I should see "KPI report submitted"
    And the KPI report for "TestStartup" should have status "submitted"
