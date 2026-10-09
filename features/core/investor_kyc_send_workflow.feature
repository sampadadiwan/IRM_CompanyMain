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
    Given I fill the kyc form
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
    Given I fill the kyc form
    And I click "Submit KYC" and confirm the dialog
    Then the investor kyc submission_status should be "completed"
    And the submitted_at timestamp is set on the investor kyc
    And the fund admin receives a KYC submission notification email
    And the fund admin's KYC submission email body reads the default submitted text
    And the fund admin has a KYC submitted notification with a non-blank message
    And the fund admin does not receive a KYC updated notification email
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

  # ─────────────────────────────────────────────────────────────────────────────
  # 14. KYC updated notification reaches both entity employees and investor-advisor
  #     employees, including an advisor currently switched into a different entity
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Investor editing the KYC notifies entity employees and investor-advisor employees, even one switched elsewhere
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is a user "email=employee@example.com" for the entity "name=KycTestFund"
    And the user "employee@example.com" has role "employee"
    And I grant "read" access to the fund for user "employee@example.com"
    And there is an entity "name=Advisor Firm;entity_type=Investor Advisor"
    And there is a user "email=advisor1@example.com" for the entity "name=Advisor Firm"
    And the user "advisor1@example.com" has role "investor_advisor"
    And the advisor "advisor1@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "advisor1@example.com"
    And there is a user "email=advisor2@example.com" for the entity "name=Advisor Firm"
    And the user "advisor2@example.com" has role "investor_advisor"
    And the advisor "advisor2@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "advisor2@example.com"
    # advisor2 then switches away to an unrelated entity before the investor edits the KYC -
    # their InvestorAdvisor grant on KycTestFund (and its AccessRight) still stand regardless.
    And there is an entity "name=Other Portco;entity_type=Investment Fund"
    And the advisor "advisor2@example.com" is switched into entity "name=Other Portco"
    And the email queue is cleared
    When the investor submits an update to the KYC
    Then the user "employee@example.com" receives a KYC updated notification email
    And the user "advisor1@example.com" receives a KYC updated notification email
    And the user "advisor2@example.com" receives a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # 15. Employees/investor-advisors without show? access to the KYC are not notified
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Employees and investor advisors without show access to the KYC are not notified
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycFund2" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    # Proper employees: one with fund access, one with investor_kyc_read but no fund access
    # (Investor Kyc Read alone shows every KYC in the entity - V1 in the change's design.md),
    # one with neither.
    And there is a user "email=emp_with_show@example.com" for the entity "name=KycTestFund"
    And the user "emp_with_show@example.com" has role "employee"
    And I grant "read" access to the fund for user "emp_with_show@example.com"
    And there is a user "email=emp_kyc_read_only@example.com" for the entity "name=KycTestFund"
    And the user "emp_kyc_read_only@example.com" has role "employee"
    And the user "emp_kyc_read_only@example.com" has extended permission "investor_kyc_read"
    And there is a user "email=emp_no_access@example.com" for the entity "name=KycTestFund"
    And the user "emp_no_access@example.com" has role "employee"
    # Investor-advisor employees: one with fund access, one switched in but with no fund access,
    # one switched OUT to a different entity but who still has the grant + fund access on
    # KycTestFund (must still be notified - notify_kyc/show? do not depend on current switch state),
    # and one who is only an advisor of a DIFFERENT entity (with show access there - irrelevant here).
    And there is an entity "name=Advisor Firm 2;entity_type=Investor Advisor"
    And there is a user "email=adv_with_show@example.com" for the entity "name=Advisor Firm 2"
    And the user "adv_with_show@example.com" has role "investor_advisor"
    And the advisor "adv_with_show@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "adv_with_show@example.com"
    And there is a user "email=adv_no_access@example.com" for the entity "name=Advisor Firm 2"
    And the user "adv_no_access@example.com" has role "investor_advisor"
    And the advisor "adv_no_access@example.com" is switched into entity "name=KycTestFund"
    And there is a user "email=adv_switched_away_with_show@example.com" for the entity "name=Advisor Firm 2"
    And the user "adv_switched_away_with_show@example.com" has role "investor_advisor"
    And the advisor "adv_switched_away_with_show@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "adv_switched_away_with_show@example.com"
    And there is a user "email=adv_other_entity@example.com" for the entity "name=Advisor Firm 2"
    And the user "adv_other_entity@example.com" has role "investor_advisor"
    And there is an entity "name=Other Portco 2;entity_type=Investment Fund"
    And there is a fund "name=OtherFund2" for the entity "name=Other Portco 2"
    And the advisor "adv_other_entity@example.com" is switched into entity "name=Other Portco 2"
    And I grant "read" access to "OtherFund2" for user "adv_other_entity@example.com"
    # Now move adv_switched_away_with_show out of KycTestFund - their grant and AccessRight there stand regardless.
    And the advisor "adv_switched_away_with_show@example.com" is switched into entity "name=Other Portco 2"
    And the email queue is cleared
    When the investor submits an update to the KYC
    Then the user "emp_with_show@example.com" receives a KYC updated notification email
    And the user "emp_kyc_read_only@example.com" receives a KYC updated notification email
    And the user "emp_no_access@example.com" does not receive a KYC updated notification email
    And the user "adv_with_show@example.com" receives a KYC updated notification email
    And the user "adv_no_access@example.com" does not receive a KYC updated notification email
    And the user "adv_switched_away_with_show@example.com" receives a KYC updated notification email
    And the user "adv_other_entity@example.com" does not receive a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # 16. A corporate/fund-of-funds LP user can still view their own KYC, even though
  #     User#setup_defaults also gives them the :employee role
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification
  Scenario: Corporate LP investor can still view their own KYC despite also carrying the employee role
    Given there is an existing investor "investor_name=KycCorpInvestor" of entity_type "Company" with "1" users
    And there is a KYC for the investor with submission_status "link_sent"
    Then the investor user should have show access to the investor kyc

  # ─────────────────────────────────────────────────────────────────────────────
  # 17. An InvestorAdvisor grant without employee/company_admin privilege must not
  #     exclusively deny show? - it should fall through to the investor-advisor role
  #     check (InvestorKyc.for_investor_advisor) instead
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification
  Scenario: A non-employee advisor grant falls through to the investor-advisor role check instead of being denied outright
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is an entity "name=KycGrantAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_grant_advisor@example.com" for the entity "name=KycGrantAdvisorFirm"
    And the user "kyc_grant_advisor@example.com" has role "investor_advisor"
    And there is an investor advisor grant for "kyc_grant_advisor@example.com" on entity "name=KycTestFund" with allowed_roles "investor"
    And InvestorKyc.for_investor_advisor is stubbed to return the investor kyc for "kyc_grant_advisor@example.com"
    Then the user "kyc_grant_advisor@example.com" should have show access to the investor kyc

  # ─────────────────────────────────────────────────────────────────────────────
  # 18. A grant privileged as company_admin (no "employee" role) is at least as
  #     capable as an employee grant, including while switched away
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification
  Scenario: A switched-away advisor granted only company_admin still has show access
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycCompanyAdminFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is an entity "name=KycCompanyAdminAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_company_admin_advisor@example.com" for the entity "name=KycCompanyAdminAdvisorFirm"
    And the user "kyc_company_admin_advisor@example.com" has role "investor_advisor"
    And there is an investor advisor grant for "kyc_company_admin_advisor@example.com" on entity "name=KycTestFund" with allowed_roles "company_admin"
    And I grant "read" access to the fund for user "kyc_company_admin_advisor@example.com"
    Then the user "kyc_company_admin_advisor@example.com" should have show access to the investor kyc

  # ─────────────────────────────────────────────────────────────────────────────
  # 19. A legacy symbol-serialized allowed_roles grant (still functional per
  #     InvestorAdvisor#setup_issues) still satisfies the employee-grant check
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification
  Scenario: A legacy symbol-serialized allowed_roles grant still satisfies the advisor-grant check
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycSymbolRolesFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is an entity "name=KycSymbolRolesAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_symbol_roles_advisor@example.com" for the entity "name=KycSymbolRolesAdvisorFirm"
    And the user "kyc_symbol_roles_advisor@example.com" has role "investor_advisor"
    And there is an investor advisor grant for "kyc_symbol_roles_advisor@example.com" on entity "name=KycTestFund" with legacy symbol allowed_roles
    And I grant "read" access to the fund for user "kyc_symbol_roles_advisor@example.com"
    Then the user "kyc_symbol_roles_advisor@example.com" should have show access to the investor kyc

  # ─────────────────────────────────────────────────────────────────────────────
  # 20. A KYC with no commitment yet is visible only to company admins and employees with
  #     Investor Kyc Read / Update (V5), so only they get its onboarding-window notifications
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: KYC with no capital commitments notifies only employees with the KYC toggles
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a user "email=zero_commitment_employee@example.com" for the entity "name=KycTestFund"
    And the user "zero_commitment_employee@example.com" has role "employee"
    And there is a user "email=zero_commitment_kyc_read@example.com" for the entity "name=KycTestFund"
    And the user "zero_commitment_kyc_read@example.com" has role "employee"
    And the user "zero_commitment_kyc_read@example.com" has extended permission "investor_kyc_read"
    And the email queue is cleared
    When the investor submits an update to the KYC
    Then the user "zero_commitment_employee@example.com" does not receive a KYC updated notification email
    And the user "zero_commitment_kyc_read@example.com" receives a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # 21. notify_kyc's two loops are deduplicated by user id
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Advisor with a legacy nil advisor_entity_id receives exactly one notification, not two
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycDedupFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is an entity "name=KycDedupAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_dedup_advisor@example.com" for the entity "name=KycDedupAdvisorFirm"
    And the user "kyc_dedup_advisor@example.com" has role "investor_advisor"
    And the advisor "kyc_dedup_advisor@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "kyc_dedup_advisor@example.com"
    And the user "kyc_dedup_advisor@example.com" has a nil advisor_entity_id
    And the email queue is cleared
    When the investor submits an update to the KYC
    Then the user "kyc_dedup_advisor@example.com" receives exactly one KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # 22. notify_kyc's second loop now gates on enable_kycs consistently with the first
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Switched-in company_admin advisor with enable_kycs disabled on their grant is not notified
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycCompanyAdminDisabledFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is an entity "name=KycCompanyAdminDisabledAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_company_admin_disabled@example.com" for the entity "name=KycCompanyAdminDisabledAdvisorFirm"
    And the user "kyc_company_admin_disabled@example.com" has role "investor_advisor"
    And the advisor "kyc_company_admin_disabled@example.com" is switched into entity "name=KycTestFund" with allowed_roles "employee,company_admin,investor_advisor" and enable_kycs disabled
    And the email queue is cleared
    When the investor submits an update to the KYC
    Then the user "kyc_company_admin_disabled@example.com" does not receive a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # 23. The final submit routes through notify_kyc, so an investor advisor with
  #     access now receives the submitted notification too - the controller's own
  #     sender only ever addressed entity employees
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_workflow @kyc_notification @notification
  Scenario: Final submit notifies an investor advisor with access, and only once
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a fund "name=KycSubmitFund" for the entity "name=KycTestFund"
    And the investor kyc has a capital commitment on the fund
    And there is an entity "name=KycSubmitAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=kyc_submit_advisor@example.com" for the entity "name=KycSubmitAdvisorFirm"
    And the user "kyc_submit_advisor@example.com" has role "investor_advisor"
    And the advisor "kyc_submit_advisor@example.com" is switched into entity "name=KycTestFund"
    And I grant "read" access to the fund for user "kyc_submit_advisor@example.com"
    And the email queue is cleared
    When the investor submits the KYC as final
    Then the user "kyc_submit_advisor@example.com" receives exactly one KYC submission notification email
    And the user "kyc_submit_advisor@example.com" does not receive a KYC updated notification email
