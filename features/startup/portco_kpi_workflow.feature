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
  @kpi_workflow @kpi_notification @rack_test
  Scenario: Sending a notification advances status to link_sent and email shows expiry date
    Given I am logged in as the fund admin
    And a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I send a portco notification for "TestStartup" with date "2025-03-31"
    Then the KPI report for "TestStartup" should have status "link_sent"
    And the portco user receives a reminder email
    And the reminder email body contains the link expiry date
    And the reminder email body contains "Save Draft"
    And the reminder email body contains "Submit Report"
    And the reminder email body contains "VentureFund"
    And the reminder email subject contains "VentureFund"

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
  @kpi_workflow @kpi_dashboard @rack_test
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
    And I go to the "Additional Details" step of the KPI report wizard
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
    And the KPI report has a valid KPIs workbook attached
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
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
  @kpi_workflow @kpi_locked @rack_test
  Scenario: Submitted report shows locked UI for portco user
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    Then I should see the KPIs submitted page instead of the wizard

  # ─────────────────────────────────────────────────────────
  # 8. Bulk send skips already-submitted portcos
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_bulk_send @rack_test
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
  # 10. Fund admin approves all KPIs and marks report as reviewed from show page
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed @rack_test
  Scenario: Fund admin sees a "View Including Staged" link on a submitted report show page
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2025-03-31"
    Then I should see a "View Including Staged" link

  # ─────────────────────────────────────────────────────────
  # 11. Designated KPI contact via user tag_list
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_contact @rack_test
  Scenario: Only users tagged "Kpi" receive the reminder email when the tag is set
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31"
    And the portfolio company has a second approved portco user "first_name=OtherContact"
    And the user "PortCoUser" has the tag "Kpi"
    And the user "OtherContact" has the tag "Approval"
    When the portco notification service runs for the report
    Then the portco user "PortCoUser" receives a reminder email
    And the user "OtherContact" receives no email

  # ─────────────────────────────────────────────────────────
  # 12. Expired magic link → friendly redirect
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_expired_link @rack_test
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
    And the KPI report has a valid KPIs workbook attached
    When I open the KPI report edit page as the portco user via a valid signed link
    Then I should see "KPI Report"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I should see a "Save Draft" button
    And I should see a "Submit Report" button
    When I fill in "Notes" with "Submitted unauthenticated"
    And I click "Submit Report" and confirm the dialog
    Then I should see "KPI report submitted"
    And the KPI report for "TestStartup" should have status "submitted"

  # ─────────────────────────────────────────────────────────
  # 14. Submit guard — invalid XLSX structure blocks submission
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit_guard @kpi_magic_link
  Scenario: Uploading an XLSX with no date headers disables the submit buttons for portco users
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I upload a KPI XLSX with no date-like headers
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    Then I should see "Please fix these errors before submitting"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save Draft" button should be disabled
    And the "Submit Report" button should be disabled

  # ─────────────────────────────────────────────────────────
  # 15. Submit guard — uploading a corrected XLSX re-enables submission
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit_guard @kpi_magic_link
  # The valid workbook must contain the period the shell asks for (Q1 2025) and the portco must have
  # KPI mappings — the server-side check (KpiWorkbookReader#validate) blocks submission otherwise.
  Scenario: Uploading a corrected XLSX re-enables the submit buttons for portco users
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I upload a KPI XLSX with no date-like headers
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Save Draft" button should be disabled
    When I upload a KPI XLSX with valid date headers
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Save Draft" button should be enabled
    And the "Submit Report" button should be enabled
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I should see "1 of 1 expected KPIs found"

  # ─────────────────────────────────────────────────────────
  # 16. Re-send notification — idempotency (Manual QA 1.6)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_notification @rack_test
  Scenario: Re-sending a notification does not create a duplicate shell or regress the status
    Given I am logged in as the fund admin
    And a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    When I send a portco notification for "TestStartup" with date "2025-03-31"
    Then the KPI report for "TestStartup" should have status "link_sent"
    And there is only one KPI report for "TestStartup" as of "2025-03-31"

  # ─────────────────────────────────────────────────────────
  # 17. Admin-only fields are not editable by portco user (Manual QA 2.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_magic_link
  Scenario: Portco user cannot see or edit fund-admin-only fields via magic link
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then the portfolio company selector is not visible
    And the KPI tag selector is not visible

  # ─────────────────────────────────────────────────────────
  # 18. Save Draft redirects back to edit page (Manual QA 3.1)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_draft
  Scenario: Save Draft redirects the portco user back to the edit page not the show page
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Additional Details" step of the KPI report wizard
    And I fill in "Notes" with "Work in progress"
    And I click "Save Draft"
    Then I should be on the edit page for the KPI report

  # ─────────────────────────────────────────────────────────
  # 19. submitted_at timestamp visible on the form (Manual QA 4.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit
  Scenario: Submitted report shows submitted_at timestamp visibly on the form
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a valid KPIs workbook attached
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report" and confirm the dialog
    Then the submitted_at timestamp is visible on the form

  # ─────────────────────────────────────────────────────────
  # 20. The fund admin's Save button is never gated on "no file yet", but a workbook with blocking
  #     errors cannot be saved by anyone (Manual QA 5.5, revised)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit_guard
  Scenario: The fund admin's Save button is disabled only while the uploaded workbook has blocking errors
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    And I am logged in as the fund admin
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Save" button should be enabled
    When I upload a KPI XLSX with no date-like headers
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    Then the workbook check panel shows "Please fix these errors before submitting"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save" button should be disabled
    When I upload a KPI XLSX with valid date headers
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Save" button should be enabled

  # ─────────────────────────────────────────────────────────
  # 21. Double-submit guard — magic link shows locked state (Manual QA 6.1)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_locked @kpi_magic_link @rack_test
  Scenario: Opening a submitted report via magic link shows the locked state
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then I should see the KPIs submitted page instead of the wizard

  # ─────────────────────────────────────────────────────────
  # 22. Double-submit guard — no second fund notification (Manual QA 6.2)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit @rack_test
  Scenario: A second submission attempt does not re-notify the fund admin
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the portco user
    And the email queue is cleared
    When I attempt to submit the already-submitted KPI report directly
    Then the fund admin receives no submission email
    And the KPI report for "TestStartup" should have status "submitted"

  # ─────────────────────────────────────────────────────────
  # 23. View Including Staged absent on non-submitted reports (Manual QA 7.3)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed
  Scenario: View Including Staged link is not shown for non-submitted reports
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "shell_created"
    And I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2025-03-31"
    Then I should not see a "View Including Staged" link

  # ─────────────────────────────────────────────────────────
  # 25. Periodic reminder skips reviewed portcos (Manual QA 8, row 7.2)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_periodic
  Scenario: Periodic reminder job does not re-notify already-reviewed portcos
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "reviewed"
    When the periodic KPI reminder job runs
    Then the portco user receives no email

  # ─────────────────────────────────────────────────────────
  # 26. Tampered (non-expired) magic link → friendly error (Manual QA 8.1)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_expired_link @rack_test
  Scenario: Visiting a tampered magic link shows a friendly error instead of crashing
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I visit the KPI report edit page with a tampered signed link
    Then I should see "This link has expired or is invalid"
    And I should not see "KPI Report"

  # ─────────────────────────────────────────────────────────
  # 27. Portco pending dashboard excludes submitted and reviewed reports (Manual QA 11.2)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_dashboard
  Scenario: Portco pending dashboard does not list submitted or reviewed reports
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the portco user
    When I visit the portco pending dashboard
    Then I should not see "2025-03-31" within the pending reports table

  # ─────────────────────────────────────────────────────────
  # 28. Portco pending dashboard — company isolation (Manual QA 11.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_dashboard @rack_test
  Scenario: Portco pending dashboard shows only the logged-in user's own company reports
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And there is an existing portfolio company "name=OtherStartup;category=Portfolio Company"
    And the portfolio company "OtherStartup" has an approved portco user "first_name=OtherPortCoUser"
    And a KPI report shell exists for "OtherStartup" as of "2025-06-30" with status "link_sent"
    And I am logged in as the portco user
    When I visit the portco pending dashboard
    Then I should see "2025-03-31" within the pending reports table
    And I should not see "2025-06-30" within the pending reports table

  # ─────────────────────────────────────────────────────────
  # 29. Non-KPI notifications unaffected by Kpi tag (Manual QA 12)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_contact @rack_test
  Scenario: Non-KPI notifications reach all approved users regardless of the Kpi tag
    Given the portfolio company has a second approved portco user "first_name=OtherContact"
    And the user "PortCoUser" has the tag "Kpi"
    Then all approved users are reachable for non-KPI notifications at "TestStartup"

  # ─────────────────────────────────────────────────────────
  # 30. link_sent_at timestamp is set when notification is sent (Manual QA 1.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_notification @rack_test
  Scenario: Sending a notification sets the link_sent_at timestamp on the report
    Given I am logged in as the fund admin
    And a KPI report shell exists for "TestStartup" as of "2025-03-31"
    When I send a portco notification for "TestStartup" with date "2025-03-31"
    Then the link_sent_at timestamp is set on the KPI report for "TestStartup"

  # ─────────────────────────────────────────────────────────
  # 31. Magic link page shows Link Sent badge and editable fields (Manual QA 2.2 + 2.3)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_magic_link
  Scenario: Magic link edit page shows the Link Sent status badge and editable notes field
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then the status badge shows "Link Sent"
    And I go to the "Additional Details" step of the KPI report wizard
    And the notes field is editable

  # ─────────────────────────────────────────────────────────
  # 32. Save Draft a second time stays draft_saved (Manual QA 3.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_draft
  Scenario: Clicking Save Draft a second time succeeds silently and status stays draft_saved
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "draft_saved"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Save Draft"
    Then I should see "Kpi report was successfully updated"
    And the KPI report for "TestStartup" should have status "draft_saved"
    And the fund admin receives no submission email

  # ─────────────────────────────────────────────────────────
  # 33. Submit Report dialog contains the correct warning text (Manual QA 4.1)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit
  Scenario: Clicking Submit Report opens a confirmation dialog with the correct warning
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a valid KPIs workbook attached
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report"
    Then I should see "cannot be undone" in the confirmation dialog

  # ─────────────────────────────────────────────────────────
  # 34. Form fields are read-only for portco after submission (Manual QA 4.6)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_locked
  Scenario: KPI report form fields are read-only for the portco user after submission
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    Then the notes field is not editable

  # ─────────────────────────────────────────────────────────
  # 35. Upload valid XLSX then invalid → buttons disable again (Manual QA 5.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit_guard @kpi_magic_link
  Scenario: Uploading an invalid XLSX after a valid one re-disables the portco submit buttons
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I upload a KPI XLSX with valid date headers
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Save Draft" button should be enabled
    When I upload a KPI XLSX with no date-like headers
    Then the "Save Draft" button should be disabled
    And the "Submit Report" button should be disabled

  # ─────────────────────────────────────────────────────────
  # 36. Clicking View Including Staged navigates to filtered grid view (Manual QA 7.4)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed @rack_test
  Scenario: Clicking View Including Staged navigates to the grid view filtered to the portco with staged data visible
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2025-03-31"
    And I click the "View Including Staged" link
    Then I should be on the KPI grid view for "TestStartup" with staged data visible

  # ─────────────────────────────────────────────────────────
  # 37. Fund admin approves all staged KPIs via Approve All (Manual QA 7.5)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed @rack_test
  Scenario: Fund admin can approve all staged KPIs and the data is promoted to approved
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And the KPI report has an unapproved KPI
    And I am logged in as the fund admin
    When I approve all staged KPIs for "TestStartup"
    Then the staged KPI for "TestStartup" should be approved

  # ─────────────────────────────────────────────────────────
  # 38. Periodic reminder sends for link_sent and draft_saved (Manual QA 8, row 7.3)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_periodic @rack_test
  Scenario Outline: Periodic reminder job sends a reminder to portcos that have not yet submitted
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "<status>"
    When the periodic KPI reminder job runs
    Then the portco user receives a reminder email

    Examples:
      | status      |
      | link_sent   |
      | draft_saved |

  # ─────────────────────────────────────────────────────────
  # 40. Submission notification goes only to Kpi-tagged fund employees when any exist
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit
  Scenario: Submission notification is sent only to Kpi-tagged fund employees when the tag is set
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a valid KPIs workbook attached
    And there is a second fund employee "first_name=FundEmployee2"
    And the fund employee "FundEmployee2" has the tag "Kpi"
    And the email queue is cleared
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report" and confirm the dialog
    Then the fund admin receives no submission email
    And the fund employee "FundEmployee2" receives a submission notification email

  # ─────────────────────────────────────────────────────────
  # 39. Removing the Kpi tag means all approved users receive the next reminder (Manual QA 9.3)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_contact @rack_test
  Scenario: Removing the Kpi tag from all users means all approved users receive the next reminder
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31"
    And the portfolio company has a second approved portco user "first_name=OtherContact"
    And the user "PortCoUser" has the tag "Kpi"
    And the user "PortCoUser" has the tag "Kpi" removed
    When the portco notification service runs for the report
    Then the portco user "PortCoUser" receives a reminder email
    And the portco user "OtherContact" receives a reminder email

  # ─────────────────────────────────────────────────────────
  # 41. Submit gate — no workbook, or a workbook with blocking errors, cannot be submitted (§2.1 / §2.2)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_submit_gate
  Scenario: Submit Report is disabled until a workbook has been checked, and a bare submit is refused by the server
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Submit Report" button should be disabled
    And the "Save Draft" button should be enabled
    When I force a final submit of the KPI report form
    Then I should see "Not submitted"
    And the KPI report for "TestStartup" should have status "draft_saved"
    And the fund admin receives no submission email

  @kpi_workflow @kpi_submit_gate
  Scenario: A workbook with blocking errors is saved as a draft but not submitted, even if the buttons are forced
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue"
    And the KPI report has a KPIs workbook attached that is missing the requested period
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Submit Report" button should be disabled
    When I force a final submit of the KPI report form
    Then I should see "Not submitted"
    And the KPI report for "TestStartup" should have status "draft_saved"
    And the fund admin receives no submission email

  # ─────────────────────────────────────────────────────────
  # 42. Read-only fields are enforced on the server for portco actors (§2.8)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_params
  Scenario: A portco PATCH carrying fund-only fields has them ignored
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has an unapproved KPI
    And there is a second portfolio company "name=OtherStartup;category=Portfolio Company"
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I send a crafted PATCH for the KPI report with fund-only fields
    Then the KPI report for "TestStartup" as of "2025-03-31" is unchanged apart from notes "tampered"
    And no approved KPI was created on the KPI report

  @kpi_workflow @kpi_params
  Scenario: A fund user cannot re-point a report to another fund's portfolio company
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And a portfolio company "ForeignStartup" of another fund exists
    And I am logged in as the fund admin
    When I send a PATCH re-pointing the KPI report to "ForeignStartup"
    Then the KPI report for "TestStartup" as of "2025-03-31" still points at "TestStartup"

  # ─────────────────────────────────────────────────────────
  # 43. Notify-after-import: the fund hears "submitted" only once the workbook is staged (§2.2 E)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_import_lifecycle
  Scenario: A clean submission is imported, marked imported, and the fund is notified once
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a valid KPIs workbook attached
    And I am logged in as the portco user
    When I open the KPI report for "TestStartup" as of "2025-03-31"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report" and confirm the dialog
    Then the KPI report for "TestStartup" should have status "submitted"
    And the KPI report import status is "imported"
    And the fund admin receives a submission notification email
    And the KPI report has an unapproved KPI "Revenue" as of "2025-03-31" with value 600

  @kpi_workflow @kpi_import_lifecycle @rack_test
  Scenario: A submission whose import fails after the gate is reopened for the portco and the fund is told why
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a KPIs workbook attached that is missing the requested period
    And the KPI report is marked submitted with a pending import
    When the KPI import job runs for the report
    Then the KPI report for "TestStartup" should have status "draft_saved"
    And the KPI report import status is "failed"
    And the fund admin receives an email with subject containing "KPI import failed"
    And the fund admin receives no submission email

  # ─────────────────────────────────────────────────────────
  # 44. Fund reopens a submitted report and asks the portco to upload again (§3.4 Q)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reopen
  Scenario: Fund admin reopens a submitted report and the portco gets a fresh link
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And the email queue is cleared
    And I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2025-03-31"
    And I click "Reopen & ask to re-upload" and confirm the dialog
    Then I should see "Report reopened"
    # Reopening re-sends the magic link, so the lifecycle restarts at link_sent (not draft_saved)
    And the KPI report for "TestStartup" should have status "link_sent"
    And the portco user "PortCoUser" receives a reminder email

  # ─────────────────────────────────────────────────────────
  # 45. Sending a notification to a portco with no KPI mappings warns the fund (§2.7)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_notification
  Scenario: Sending a notification to a portco without KPI mappings shows a warning to the fund
    Given I am logged in as the fund admin
    When I send a KPI notification to "TestStartup" as of "2025-03-31" with period "Quarter"
    Then I should see "No KPI mappings configured for: TestStartup"

  # ─────────────────────────────────────────────────────────
  # 46. Template download (§3.4 P)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_template @kpi_magic_link @rack_test
  Scenario: The portco can download a pre-filled template that the importer reads back exactly
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the target KPIs are "Revenue, EBITDA"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then I should see "Download KPI template"
    And the generated KPI template for the report has header "Jan-Mar 2025" and rows "Revenue, EBITDA"
    And validating the generated template reports the requested period as present but blank

  # ─────────────────────────────────────────────────────────
  # 50. After submitting, the portco sees a confirmation — not the wizard's "Let's get started" — on the same
  #     link, until the fund reopens the report
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_locked @kpi_magic_link
  Scenario: After submitting, the portco's link shows KPIs submitted until the fund reopens the report
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "link_sent"
    And the KPI report has a valid KPIs workbook attached
    When I open the KPI report edit page as the portco user via a valid signed link
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report" and confirm the dialog
    Then I should see the KPIs submitted page instead of the wizard
    And the KPIs submitted page shows the import finished
    When I open the KPI report edit page as the portco user via a valid signed link
    Then I should see the KPIs submitted page instead of the wizard
    When the fund reopens the KPI report
    And I open the KPI report edit page as the portco user via a valid signed link
    Then I should see "Let's get started"

  # ─────────────────────────────────────────────────────────
  # 51. The staged review has no empty KPIs chart (the chart plots approved values only)
  # ─────────────────────────────────────────────────────────
  @kpi_workflow @kpi_reviewed @rack_test
  Scenario: The grid's KPIs chart is hidden while reviewing staged values and shown otherwise
    Given a KPI report shell exists for "TestStartup" as of "2025-03-31" with status "submitted"
    And the KPI report has an unapproved KPI
    And I am logged in as the fund admin
    When I open the KPI grid for "TestStartup" including staged values
    Then the grid shows no KPIs chart
    When I open the KPI grid for "TestStartup"
    Then the grid shows the KPIs chart
