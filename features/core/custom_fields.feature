@form_custom_fields
Feature: CustomFields
  Test behavior of the CustomFields


Scenario Outline: Create investor kyc - with custom fields as fund
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "<custom_fields>" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 1"
  Given I create a new InvestorKyc "PAN=ABCD9876F;properties=Carry % (4x or less)%:Test" with files "<files>" for ""
  Then I should see the "Investor kyc was successfully saved."
  And I should see the kyc documents "<files>"
  Then I should see the investor kyc details on the details page
  Examples:
    |custom_fields| files |
    |name=F1;field_type=File;required=true#name=F2;field_type=File;required=false#name=Carry % (4x or less)%;field_type=TextField;required=true         | F1,F2|
    |name=F1;field_type=File;required=true#name=F2;field_type=File;required=true#name=Carry % (4x or less)%;field_type=TextField;required=true         | F1,F2|
    |name=F1;field_type=File;required=false#name=F2;field_type=File;required=false#name=Carry % (4x or less)%;field_type=TextField;required=true         | F1|


Scenario Outline: Create investor kyc - with custom fields as investor
  Given there is a user "" for an entity "name=Fund1;entity_type=Investment Fund"
  Given the entity has custom fields "<custom_fields>" for "IndividualKyc"
  Given there is an existing investor "name=Investor 1" with "1" users
  Given I login as the investor user
  Given I create a new InvestorKyc "PAN=ABCD9876F;properties=F3:Test" with files "<files>" for "{'investor_kyc[entity_id]': @entity.id, 'investor_kyc[investor_id]': @investor.id}"
  Then I should see the "Investor kyc was successfully saved."
  And I should see the kyc documents "<files>"
  Then I should see the investor kyc details on the details page
  Examples:
    |custom_fields| files |
    |name=F1;field_type=File;required=true#name=F2;field_type=File;required=false#name=F3;field_type=TextField;required=true         | Upload PAN / Tax ID,Upload Address Proof,F1,F2|
    |name=F1;field_type=File;required=false#name=F2;field_type=File;required=false#name=F3;field_type=TextField;required=true         | Upload PAN / Tax ID,Upload Address Proof,F1|

@import
Scenario Outline: Import form custom fields
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a FormType "name=CapitalCommitment;tag=Default"
  And Given I upload "<file_name>" file for "Form Custom Fields" of the entity
  Then There should be "<count>" form custom fields created with data in the sheet

  Examples:
   |entity                                         |file_name                |count	|
   |entity_type=Investment Fund;enable_funds=true  |form_custom_fields.xlsx  |13    |


# Fund employees (company_admin) save KYCs as partial/draft records all the time — e.g.
# before the investor has handed over every supporting document — and come back to
# complete them later. No mandatory field, standard or custom, may block that kind of
# save when a fund employee is the one saving — every fill_in is skipped here, leaving
# full_name, PAN, birth_date, address, bank details, etc. blank, on top of whichever
# custom fields are configured.
#
# Regression test: InvestorKycCreate#check_required_file_custom_fields used to run this
# check unconditionally (even for non-validating/draft saves), which silently blocked
# fund employees from saving a new KYC unless every required file was already attached.
# See app/packs/core/investor_kycs/services/investor_kyc_create.rb.
Scenario Outline: Fund employee can save a new KYC with no mandatory fields filled in - standard or custom
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "<custom_fields>" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 1"
  When I try to save a new InvestorKyc as a fund employee with no mandatory fields filled in
  Then I should see the "Investor kyc was successfully saved."
  And the saved investor kyc should have no mandatory fields filled in
  And I should not see the kyc document "<missing_doc>"

  Examples:
    | custom_fields                                                                  | missing_doc |
    | name=F1;field_type=File;required=true                                         | F1          |
    | name=F1;field_type=File;required=true#name=F2;field_type=File;required=false  | F1          |
    | name=F1;field_type=File;required=true#name=F3;field_type=TextField;required=true | F1        |

# Once the fund employee has saved the partial KYC above, they should be able to come
# back, attach the previously-missing required file, and save again to complete it.
Scenario: Fund employee completes a previously partial KYC by adding the missing required file
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "name=F1;field_type=File;required=true" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 1"
  When I try to save a new InvestorKyc as a fund employee with no mandatory fields filled in
  Then I should see the "Investor kyc was successfully saved."
  And I should not see the kyc document "F1"
  When I edit the investor kyc and upload the missing custom file "F1"
  Then I should see the kyc documents "F1"

# Contrast with the scenario above: investors are still required to fill in every
# mandatory field, standard and custom, before they can submit their KYC. This was the
# correct behavior before the regression and must not change.
@kyc_magic_link
Scenario: Investor cannot submit a KYC while mandatory fields are missing - standard or custom
  Given there is a user "first_name=FundAdmin" for an entity "name=Urban3;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "name=F3;field_type=TextField;required=true" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 3" with "1" users
  Given there is a KYC for the investor with submission_status "link_sent" and no mandatory fields filled in
  When I open the KYC edit page as the investor via a valid signed link
  Given I fill the kyc form
  And I click "Submit KYC" and confirm the dialog
  Then I should see the "F3 is required"
  And the investor kyc submission_status should not be "completed"


# Edge case: non-File field types (NumberField, DateField) work correctly as KYC custom fields
Scenario Outline: KYC custom fields of non-file types can be saved and are visible on the details page
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "<custom_fields>" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 1"
  Given I create a new InvestorKyc "PAN=ABCD9876F;properties=<properties>" with files "" for ""
  Then I should see the "Investor kyc was successfully saved."
  Then I should see the investor kyc details on the details page

  Examples:
    | custom_fields                                            | properties              |
    | name=Duration;field_type=NumberField;required=true       | Duration:5              |
    | name=Review Date;field_type=DateField;required=false     | Review Date:2026-12-31  |


# Model-level validation: Select/Radio field types require meta_data options
Scenario: Select custom field without options fails model validation
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  When I try to create a custom field "name=Category;field_type=Select" for "IndividualKyc" without options
  Then the custom field should not be saved with error "must provide at least one option for Select"
