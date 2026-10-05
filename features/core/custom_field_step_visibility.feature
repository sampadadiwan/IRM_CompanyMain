@form_custom_fields
Feature: Custom field visibility by step on single-page vs multi-step forms
  Single-page forms (e.g. CapitalCommitment) render all their custom fields on one
  page, regardless of which wizard "Step" is configured on each field in the form
  builder. Only genuine multi-step wizard forms (e.g. InvestorKyc, already covered by
  features/core/dynamic_kyc_steps.feature) split fields across pages by step.
  #
  # Regression test for: choosing anything other than the "Step 3 (Default)" option
  # for a field on a single-page form used to make that field disappear entirely,
  # because custom_form_fields defaulted to only rendering step "end" fields.
  # See app/packs/misc/form_types/helpers/form_type_helper.rb#custom_form_fields.

Scenario: CapitalCommitment shows custom fields configured on every step
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given the entity has custom fields "name=source_of_funds;field_type=TextField;step=one;label=Source of Funds#name=risk_notes;field_type=TextField;step=two;label=Risk Notes#name=internal_notes;field_type=TextField;step=end;label=Internal Notes" for "CapitalCommitment"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000" for "FilterFund" and "Investor A"
  When I visit the edit page for the capital commitment
  Then I should see a field labelled "Source of Funds"
  And I should see a field labelled "Risk Notes"
  And I should see a field labelled "Internal Notes"

Scenario: CapitalCommitment saves a value entered in a custom field configured on a non-default step
  Given Im logged in as a user "" for an entity "name=TestFund;entity_type=Investment Fund;enable_funds=true"
  Given the user has role "company_admin"
  Given the entity has custom fields "name=source_of_funds;field_type=TextField;step=one;label=Source of Funds#name=internal_notes;field_type=TextField;step=end;label=Internal Notes" for "CapitalCommitment"
  Given there is an existing fund "name=FilterFund"
  Given there is an existing investor "investor_name=Investor A"
  Given there is an existing capital commitment "committed_amount=100000" for "FilterFund" and "Investor A"
  When I visit the edit page for the capital commitment
  And I fill in the field labelled "Source of Funds" with "Salary savings" and save
  Then the capital commitment custom field "source_of_funds" should be "Salary savings"
  When I visit the edit page for the capital commitment
  Then the field labelled "Source of Funds" should contain "Salary savings"
