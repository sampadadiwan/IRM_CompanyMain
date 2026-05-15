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


# Error scenario: required custom file field left blank triggers validation error
Scenario Outline: Submitting KYC without a required custom file shows a validation error
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the entity has custom fields "<custom_fields>" for "IndividualKyc"
  Given there is an existing investor "investor_name=Investor 1"
  When I try to save a new InvestorKyc "PAN=ABCD9876F" without any files
  Then I should see the "<error_msg>"

  Examples:
    | custom_fields                               | error_msg          |
    | name=F1;field_type=File;required=true       | can't be blank     |
    | name=F1;field_type=File;required=true#name=F2;field_type=File;required=false | can't be blank |


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
