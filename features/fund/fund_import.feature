Feature: Import Fund
  Can import fund details

@import
Scenario Outline: Import capital commitments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" capital commitments created
  And the import upload must be updated correctly for capital commitments
  And the imported data must have the form_type updated
  And the capital commitments must have the data in the sheet
  And the capital commitments must have the percentages updated
  And the fund must have the counter caches updated
  And the investors must have access rights to the fund
  And Given I upload "account_entries.xlsx" file for Account Entries
  Then There should be "19" account_entries created
  And the account_entries must have the data in the sheet
  And the account_entries must visible for each commitment


@import
Scenario Outline: Import capital commitments - Large set
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C,Series C1" for the entity
  And Given I upload an investors file large for the fund
  And Given I upload "capital_commitments_multi_currency_large.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "100" capital commitments created
  And the capital commitments must have the data in the sheet
  And the capital commitments must have the percentages updated
  And the fund must have the counter caches updated
  And the investors must have access rights to the fund
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers

@import
Scenario Outline: Import capital calls
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B, Series C, Series C1" for the entity
  And Given I upload an investors file for the fund
  # And Given I upload an investors file large for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  # And Given I upload "capital_commitments_multi_currency_large.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  And the remittance rollups should be correct
  And when the exchange rate changes
  Then the commitment amounts change correctly
  # Given the last investor has a user "phone=7721046692"
  # And the capital remittance whatsapp notification is sent to the first investor
  # Then the whatsapp message should be send successfully to "917721046692"

@import
Scenario Outline: Import capital remittance payments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls_no_remittances.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "3" capital calls created
  And Given I upload "capital_remittance_payments_multi_currency.xlsx" file for the remittances of the capital call
  Then There should be "5" remittance payments created
  And the capital remittance payments must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers
  And if the last remittance payment is deleted
  Then the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers
  And if the first remittance is deleted
  Then the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers

@import
Scenario Outline: Import capital remittance
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund
  Given the fund has capital call template
  Given the investors are added to the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Then when the capital call is approved
  Then the no remittances should be created
  And Given I upload "capital_remittances.xlsx" file for Call remittances of the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  And the remittance rollups should be correct
  And if the first remittance is deleted
  Then the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers
  Given there are payments for each remittance
  Given I filter the "capital_remittances" by "verified=true"
  And I trigger the bulk action for "Toggle Verify"
  # Then I should see the "Verify completed"
  And the remittances have verified set to "false"
  And the remittance rollups should be correct
  Given I filter the "capital_remittances" by "verified=false"
  And I trigger the bulk action for "Toggle Verify"
  # Then I should see the "Verify completed"
  And the remittances have verified set to "true"
  And the remittance rollups should be correct

  Examples:
  	|entity                                         |fund                |msg	| call | collected_amount |
  	|entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| name=Call 1;call_basis=Upload | 2120000 |


@import
Scenario Outline: Import capital distributions
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_distributions.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "2" capital distributions created
  And the capital distributions must have the data in the sheet
  And the payments are generated for the capital distrbutions

@import
Scenario Outline: Import capital distributions payments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_distributions_no_payments.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "2" capital distributions created
  And Given I upload "capital_distribution_payments.xlsx" file for the Distribution Payments of the fund
  Then There should be "6" distribution payments created
  And the capital distribution payments must have the data in the sheet "capital_distribution_payments.xlsx"

@import
Scenario Outline: Import commitment and distribution fund documents
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The commitments have investor kycs linked
  And Given I upload "capital_distributions_no_payments_1.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "3" capital distributions created
  And Given I upload "capital_distribution_payments.xlsx" file for the Distribution Payments of the fund
  Then There should be "6" distribution payments created
  And the capital distribution payments must have the data in the sheet "capital_distribution_payments.xlsx"
  Given I upload fund documents "commitment_and_distribution_fund_docs.zip"
  Then I should see the "Import in progress"
  Then The proper documents must be uploaded for the commitments and distributions
  Then I should see the commitment and distribuition docs upload errors

@import
Scenario Outline: Import capital remittance payments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency_1.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls_no_remittances_1.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And Given I upload "capital_remittance_payments_multi_currency_errors.xlsx" file for the remittances of the capital call with errors
  Then There should be "6" remittance payments created
  And I should see the remittance payments upload errors

@import
Scenario Outline: Import capital remittance fund documents
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency_1.xlsx" file for "Commitments" of the fund
  And The commitments have investor kycs linked
  And Given I upload "capital_calls_no_remittances_1.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  Given I upload fund documents "remittance_fund_docs.zip"
  Then I should see the "Import in progress"
  Then The proper documents must be uploaded for the remittances
  And I should see the remittance docs upload errors


@import
Scenario Outline: Import Fund Formulas
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload fund formulas for the fund
  Then I should see the "Import in progress"
  Then There should be "9" fund formulas created
  And the fund formulas must have the data in the sheet
