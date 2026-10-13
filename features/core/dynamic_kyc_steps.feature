Feature: Dynamic KYC wizard steps
  As a fund admin I want to place custom fields in any number of wizard steps (1 to max)
  So that the KYC form adapts to n steps based on the form type configuration

  Background:
    Given Im logged in as a user "first_name=DynAdmin" for an entity "name=DynStepFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=DynStepInvestor" with "1" users
    And there is a KYC form type with one text field on each step from one to nine

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. Wizard nav reflects the configured step count
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_dynamic_steps @form_custom_fields @rack_test
  Scenario: Step wizard renders 9 navigation circles when all 9 steps are configured
    Given there is a KYC for the investor using the dynamic form type
    When I visit the investor kyc edit form
    Then the step wizard shows 9 navigation circles

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. Values from every step are persisted and visible on the show page
  # ─────────────────────────────────────────────────────────────────────────────
  @kyc_dynamic_steps @form_custom_fields
  Scenario: Values entered on every step are saved in the DB and shown on the show page
    Given there is a KYC for the investor using the dynamic form type
    When I visit the investor kyc edit form
    And I fill in "val_step_1" for the custom field on display step 1 and advance
    And I fill in "val_step_2" for the custom field on display step 2 and advance
    And I fill in "val_step_3" for the custom field on display step 3 and advance
    And I fill in "val_step_4" for the custom field on display step 4 and advance
    And I fill in "val_step_5" for the custom field on display step 5 and advance
    And I fill in "val_step_6" for the custom field on display step 6 and advance
    And I fill in "val_step_7" for the custom field on display step 7 and advance
    And I fill in "val_step_8" for the custom field on display step 8 and advance
    And I fill in "val_step_9" for the custom field on display step 9 and save
    Then all dynamic custom field values are saved in the investor kyc properties
    When I visit the investor kyc show page
    Then I should see all dynamic custom field values on the page
