@rack_test
Feature: Investor KYC visibility rule
  One rule decides who can see a KYC - the KYC list, the KYC page and the three KYC
  notification emails (submitted, updated, updates requested) all follow it:

    enable_kycs AND ( company admin OR Investor Kyc Read OR Investor Kyc Update
                      OR access to a fund the KYC is committed to )

  A KYC with no commitment yet has no fund to check, so only a company admin or an employee
  with Investor Kyc Read / Update sees it (and is emailed about it).

  An investor advisor is judged by their grant on the KYC's entity, whichever entity they are
  currently switched into. Each scenario is one row of the worked examples (V1-V11) in
  openspec/changes/kyc-advisor-notification-delivery-fix/design.md#worked-examples

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=KycRuleFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=KycRuleInvestor" with "1" users
    And there is a fund "name=KycRuleFundA" for the entity "name=KycRuleFund"
    And there is a KYC for the investor with submission_status "link_sent"
    And the investor kyc has a capital commitment on the fund
    And there is a fund "name=KycRuleFundB" for the entity "name=KycRuleFund"
    And the email queue is cleared

  # ─────────────────────────────────────────────────────────────────────────────
  # Employees (V1-V6)
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @kyc_visibility
  Scenario: V1 - Investor Kyc Read alone sees a KYC on a fund they have no access to
    Given there is a user "email=rule_kyc_read@example.com" for the entity "name=KycRuleFund"
    And the user "rule_kyc_read@example.com" has role "employee"
    And the user "rule_kyc_read@example.com" has extended permission "investor_kyc_read"
    Then the user "rule_kyc_read@example.com" should have show access to the investor kyc
    And the investor kyc should be in the KYC list of "rule_kyc_read@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_kyc_read@example.com" receives a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V2 - Investor Kyc Update alone sees a KYC on a fund they have no access to
    Given there is a user "email=rule_kyc_update@example.com" for the entity "name=KycRuleFund"
    And the user "rule_kyc_update@example.com" has role "employee"
    And the user "rule_kyc_update@example.com" has extended permission "investor_kyc_update"
    Then the user "rule_kyc_update@example.com" should have show access to the investor kyc
    And the investor kyc should be in the KYC list of "rule_kyc_update@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_kyc_update@example.com" receives a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V3 - Fund access alone, without Investor Kyc Read, sees the fund's KYC
    Given there is a user "email=rule_fund_a@example.com" for the entity "name=KycRuleFund"
    And the user "rule_fund_a@example.com" has role "employee"
    And I grant "read" access to "KycRuleFundA" for user "rule_fund_a@example.com"
    Then the user "rule_fund_a@example.com" should have show access to the investor kyc
    And the investor kyc should be in the KYC list of "rule_fund_a@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_fund_a@example.com" receives a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V4 - Access to a different fund does not see the KYC
    Given there is a user "email=rule_fund_b@example.com" for the entity "name=KycRuleFund"
    And the user "rule_fund_b@example.com" has role "employee"
    And I grant "read" access to "KycRuleFundB" for user "rule_fund_b@example.com"
    Then the user "rule_fund_b@example.com" should not have show access to the investor kyc
    And the investor kyc should not be in the KYC list of "rule_fund_b@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_fund_b@example.com" does not receive a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V5 - A KYC with no commitment yet is hidden from an employee with no KYC toggles
    # V5 — Edge case: no commitment means no fund to check; fund access alone never reveals it
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a user "email=rule_plain@example.com" for the entity "name=KycRuleFund"
    And the user "rule_plain@example.com" has role "employee"
    And I grant "read" access to "KycRuleFundA" for user "rule_plain@example.com"
    Then the user "rule_plain@example.com" should not have show access to the investor kyc
    And the investor kyc should not be in the KYC list of "rule_plain@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_plain@example.com" does not receive a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V5a - A KYC with no commitment yet is seen by an employee with Investor Kyc Read
    # V5a — Edge case: the KYC toggles reveal every KYC in the entity, committed or not
    Given there is a KYC for the investor with submission_status "link_sent"
    And there is a user "email=rule_nocommit_read@example.com" for the entity "name=KycRuleFund"
    And the user "rule_nocommit_read@example.com" has role "employee"
    And the user "rule_nocommit_read@example.com" has extended permission "investor_kyc_read"
    Then the user "rule_nocommit_read@example.com" should have show access to the investor kyc
    And the investor kyc should be in the KYC list of "rule_nocommit_read@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_nocommit_read@example.com" receives a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V6 - With enable_kycs off nothing else counts
    Given there is a user "email=rule_kycs_off@example.com" for the entity "name=KycRuleFund"
    And the user "rule_kycs_off@example.com" has role "employee"
    And the user "rule_kycs_off@example.com" has extended permission "investor_kyc_read"
    And I grant "read" access to "KycRuleFundA" for user "rule_kycs_off@example.com"
    And the user "rule_kycs_off@example.com" has permission "enable_kycs" disabled
    Then the user "rule_kycs_off@example.com" should not have show access to the investor kyc
    And the investor kyc should not be in the KYC list of "rule_kycs_off@example.com"
    When the investor submits an update to the KYC
    Then the user "rule_kycs_off@example.com" does not receive a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # Investor advisors switched out of the fund's entity (V7-V9)
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @kyc_visibility
  Scenario: V7 - A switched-out advisor whose grant has Investor Kyc Read gets all three KYC emails, even while in an entity with KYCs off
    Given there is an entity "name=KycRuleAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=rule_adv_read@example.com" for the entity "name=KycRuleAdvisorFirm"
    And the user "rule_adv_read@example.com" has role "investor_advisor"
    And the advisor "rule_adv_read@example.com" is switched into entity "name=KycRuleFund"
    And the investor advisor grant for "rule_adv_read@example.com" on entity "name=KycRuleFund" has extended permission "investor_kyc_read"
    # Switch them into an unrelated entity that does not use KYCs at all - the grant on
    # KycRuleFund is what counts, not the entity they happen to be in.
    And there is an entity "name=KycRuleNoKycEntity;entity_type=Investment Fund"
    And the entity "name=KycRuleNoKycEntity" has KYCs disabled
    And the advisor "rule_adv_read@example.com" is switched into entity "name=KycRuleNoKycEntity"
    Then the user "rule_adv_read@example.com" should have show access to the investor kyc
    When the investor submits an update to the KYC
    Then the user "rule_adv_read@example.com" receives a KYC updated notification email
    When the investor clicks Updates Required on the KYC
    Then the user "rule_adv_read@example.com" receives a KYC updates requested notification email
    When the investor submits the KYC as final
    Then the user "rule_adv_read@example.com" receives exactly one KYC submission notification email

  @kyc_notification @kyc_visibility
  Scenario: V8 - A switched-out advisor with a company_admin grant sees the KYC without any fund access
    Given there is an entity "name=KycRuleAdminAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=rule_adv_admin@example.com" for the entity "name=KycRuleAdminAdvisorFirm"
    And the user "rule_adv_admin@example.com" has role "investor_advisor"
    And the advisor "rule_adv_admin@example.com" is switched into entity "name=KycRuleFund" with allowed_roles "company_admin,investor_advisor"
    And there is an entity "name=KycRuleOtherEntity;entity_type=Investment Fund"
    And the advisor "rule_adv_admin@example.com" is switched into entity "name=KycRuleOtherEntity"
    Then the user "rule_adv_admin@example.com" should have show access to the investor kyc
    When the investor submits an update to the KYC
    Then the user "rule_adv_admin@example.com" receives a KYC updated notification email

  @kyc_notification @kyc_visibility
  Scenario: V9 - A switched-out advisor whose grant has enable_kycs off gets nothing, despite Kyc Read and fund access
    Given there is an entity "name=KycRuleOffAdvisorFirm;entity_type=Investor Advisor"
    And there is a user "email=rule_adv_off@example.com" for the entity "name=KycRuleOffAdvisorFirm"
    And the user "rule_adv_off@example.com" has role "investor_advisor"
    And the advisor "rule_adv_off@example.com" is switched into entity "name=KycRuleFund"
    And I grant "read" access to "KycRuleFundA" for user "rule_adv_off@example.com"
    And the investor advisor grant for "rule_adv_off@example.com" on entity "name=KycRuleFund" has extended permission "investor_kyc_read"
    And the investor advisor grant for "rule_adv_off@example.com" on entity "name=KycRuleFund" has permission "enable_kycs" disabled
    And there is an entity "name=KycRuleOtherEntity2;entity_type=Investment Fund"
    And the advisor "rule_adv_off@example.com" is switched into entity "name=KycRuleOtherEntity2"
    Then the user "rule_adv_off@example.com" should not have show access to the investor kyc
    When the investor submits an update to the KYC
    Then the user "rule_adv_off@example.com" does not receive a KYC updated notification email

  # ─────────────────────────────────────────────────────────────────────────────
  # V10 (fund-of-funds LP opening its own KYC) is scenario 16 and V11 (switched-in
  # advisor gets exactly one email) is scenarios 21 and 23 of investor_kyc_send_workflow.feature.
  # ─────────────────────────────────────────────────────────────────────────────

  # ─────────────────────────────────────────────────────────────────────────────
  # The emails go out from a background job, not inside the investor's web request
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_notification @kyc_visibility
  Scenario: An investor's KYC update queues NotifyKycJob instead of emailing inline
    Given there is a user "email=rule_job@example.com" for the entity "name=KycRuleFund"
    And the user "rule_job@example.com" has role "employee"
    And the user "rule_job@example.com" has extended permission "investor_kyc_read"
    When the investor submits an update to the KYC with background jobs held
    Then a NotifyKycJob is queued for the investor kyc with email_method "notify_kyc_updated"
    And the user "rule_job@example.com" does not receive a KYC updated notification email
