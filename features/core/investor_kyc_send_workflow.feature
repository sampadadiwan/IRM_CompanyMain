Feature: Investor KYC Send Workflow
  As a fund admin I want to send KYC forms to investors via magic links and track completion status
  As an investor I want to save drafts and submit my KYC clearly via a secure link
  So that both sides have a clear, auditable view of KYC progress

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=KycTestFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=KycInvestor1" with "1" users
    And the email queue is cleared

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. New KYC shows not_sent status
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_status
  Scenario: Newly created KYC has not_sent submission status
    Given there is a KYC for the investor with submission_status "not_sent"
    Then the investor kyc submission_status should be "not_sent"

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. Send KYC link → link_sent + email
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Sending the KYC form link advances status to link_sent and emails the investor
    Given there is a KYC for the investor with submission_status "not_sent"
    When the fund admin sends the KYC form to the investor
    Then the investor kyc submission_status should be "link_sent"
    And the link_sent_at timestamp is set on the investor kyc
    And the investor user receives a KYC email

  # ─────────────────────────────────────────────────────────────────────────────
  # 3. Investor opens magic link — form is editable
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link
  Scenario: Investor opens a valid magic link and sees an editable KYC form
    Given there is a KYC for the investor with submission_status "link_sent"
    When I open the KYC edit page as the investor via a valid signed link
    Then I should see a "Save Draft" button
    And I should see a "Submit KYC" button

  # ─────────────────────────────────────────────────────────────────────────────
  # 4. Save Draft via magic link → draft_saved, fund not notified
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link @notification
  Scenario: Investor saves a draft via magic link — status advances to draft_saved, fund not notified
    Given there is a KYC for the investor with submission_status "link_sent"
    And the email queue is cleared
    When I open the KYC edit page as the investor via a valid signed link
    And I click "Save Draft"
    Then the investor kyc submission_status should be "draft_saved"
    And the fund admin receives no KYC submission email

  # ─────────────────────────────────────────────────────────────────────────────
  # 5. Submit KYC via magic link → completed, redirected to show, fund notified
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link @notification
  Scenario: Investor submits KYC via magic link — status advances to completed and fund is notified
    Given there is a KYC for the investor with submission_status "link_sent"
    And the email queue is cleared
    When I open the KYC edit page as the investor via a valid signed link
    And I click "Submit KYC" and confirm the dialog
    Then the investor kyc submission_status should be "completed"
    And the submitted_at timestamp is set on the investor kyc
    And the fund admin receives a KYC submission notification email
    And I should be on the investor kyc show page

  # ─────────────────────────────────────────────────────────────────────────────
  # 6. Locked state — investor is redirected to show page, not the edit form
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link
  Scenario: Completed KYC redirects investor to the show page when edit link is opened
    Given there is a KYC for the investor with submission_status "completed"
    When I open the KYC edit page as the investor via a valid signed link
    Then I should be on the investor kyc show page
    And I should not see a "Save Draft" button
    And I should not see a "Submit KYC" button

  # ─────────────────────────────────────────────────────────────────────────────
  # 6b. Show page via magic link — no fund-admin buttons visible
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link
  Scenario: Investor viewing show page via magic link sees no fund-admin action buttons
    Given there is a KYC for the investor with submission_status "completed"
    When I open the KYC show page as the investor via a valid signed link
    Then I should not see an "Edit" button
    And I should not see a "Delete" button
    And I should not see a "KYC Actions" button

  # ─────────────────────────────────────────────────────────────────────────────
  # 7. Expired magic link → friendly error
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link
  Scenario: Investor visits an expired magic link and sees a friendly error
    Given there is a KYC for the investor with submission_status "link_sent"
    When I visit the KYC edit page with an expired signed link
    Then I should see "link has expired"

  # ─────────────────────────────────────────────────────────────────────────────
  # 8. Tampered magic link → friendly error
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_magic_link
  Scenario: Investor visits a tampered magic link and sees a friendly error
    Given there is a KYC for the investor with submission_status "link_sent"
    When I visit the KYC edit page with a tampered signed link
    Then I should see "link has expired"

  # ─────────────────────────────────────────────────────────────────────────────
  # 9. Request Updates — resets to link_sent, emails investor with custom message
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_request_updates @notification
  Scenario: Fund admin requests updates — KYC reverts to link_sent and investor is emailed
    Given there is a KYC for the investor with submission_status "completed"
    And the email queue is cleared
    When the fund admin requests updates with message "Please re-upload your PAN card"
    Then the investor kyc submission_status should be "link_sent"
    And the investor kyc submitted_at is cleared
    And the link_sent_at timestamp is set on the investor kyc
    And the investor user receives an update request email containing "Please re-upload your PAN card"

  # ─────────────────────────────────────────────────────────────────────────────
  # 10. Request Updates without message — uses default message
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_request_updates @notification
  Scenario: Fund admin requests updates without a custom message — default text is sent
    Given there is a KYC for the investor with submission_status "completed"
    And the email queue is cleared
    When the fund admin requests updates with message ""
    Then the investor user receives an update request email containing "Please update your KYC details"

  # ─────────────────────────────────────────────────────────────────────────────
  # 11. KycReminderJob skips completed and verified KYCs
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_reminder @notification
  Scenario: KycReminderJob does not email investors whose KYC is already completed or verified
    Given there is a KYC for the investor with submission_status "completed"
    And the email queue is cleared
    When the KYC reminder job runs for the entity
    Then the investor user receives no email

  @kyc_workflow @kyc_reminder @notification
  Scenario: KycReminderJob does not email investors whose KYC is verified
    Given there is a KYC for the investor with submission_status "verified"
    And the email queue is cleared
    When the KYC reminder job runs for the entity
    Then the investor user receives no email

  @kyc_workflow @kyc_reminder @notification
  Scenario: KycReminderJob does email investors whose KYC is still pending
    Given there is a KYC for the investor with submission_status "link_sent"
    And the email queue is cleared
    When the KYC reminder job runs for the entity
    Then the investor user receives a KYC email

  # ─────────────────────────────────────────────────────────────────────────────
  # 12. Investor pending dashboard
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_dashboard
  Scenario: Investor pending dashboard shows KYCs with link_sent or draft_saved status
    Given there is a KYC for the investor with submission_status "link_sent"
    And I am logged in as the investor user
    When I visit the investor pending KYC dashboard
    Then I should see "KycTestFund" within the pending kyc table
    And I should see "KycInvestor1" within the pending kyc table

  @kyc_workflow @kyc_dashboard
  Scenario: Investor pending dashboard excludes completed KYCs
    Given there is a KYC for the investor with submission_status "completed"
    And I am logged in as the investor user
    When I visit the investor pending KYC dashboard
    Then I should not see "KycInvestor1" within the pending kyc table

  # ─────────────────────────────────────────────────────────────────────────────
  # 13. Ransack filter by submission_status on index
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_filter
  Scenario: Fund admin can filter KYC index by submission_status
    Given there is a KYC for the investor with submission_status "link_sent"
    And I am logged in as the fund admin
    When I visit the investor kycs index filtered by submission_status "link_sent"
    Then I should see "KycInvestor1"
