Feature: KYC level Call and Dist Payment notice generation and notification


Scenario Outline: Call Notice generation and notification for all
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B, Series C, Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  Given the fund has capital call template
  Given the remittances have proper notification users
  Then call notice is generated for the remittances
  And remittance notice must be generated for each remittance
  Given I approve the capital call
  # Normal scenario - call notice is generated for each remittance for its own data
  Then the notification must be sent to the investors where the call notice was generated

Scenario Outline: Call Notice generation and notification for all at kyc level
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B, Series C, Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  Given the fund has capital call template
  Given the remittances have proper notification users
  Given I update the fund custom fields "call_notice_on:kyc"
  Then call notice is generated for the remittances

  # Now notice is generated at the kyc level but we havent set skip call notice in the commitment so it will be generated for all remittances but where the kyc has multiple remittances it will have cumulated data
  And remittance notice must be generated for each remittance
  Given I approve the capital call
  Then the notification must be sent to the investors where the call notice was generated

Scenario Outline: Call Notice generation and notification for only the latest ones at kyc level
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B, Series C, Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import in progress"
  Then There should be "4" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  Given the fund has capital call template
  Given the remittances have proper notification users
  Given I update the fund custom fields "call_notice_on:kyc"
  Given I update the remittances commitments custom fields with the same kyc and earlier remittance date "skip_call_notice:Yes"
  Then call notice is generated for the remittances

  # Now notice is generated at the kyc level but we have set skip call notice in the commitment that are from the same kyc and earlier i.e. only the latest remittance for the kyc should have notice generated
  And remittance notice must be generated for the latest remittance for each kyc
  Given I approve the capital call
  Then the notification must be sent to the investors where the call notice was generated

Scenario Outline: DIST Notice generation and notification for all
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_distributions_no_payments_1.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "3" capital distributions created
  And Given I upload "capital_distribution_payments.xlsx" file for the Distribution Payments of the fund
  Then There should be "6" distribution payments created
  And the capital distribution payments must have the data in the sheet "capital_distribution_payments.xlsx"
  Given The capital distribution payments are approved
  Given the fund has a Distribution Template
  Given the distribution is approved
  Given the distribution is not manually generated
  Given the distribution payments are completed
  Given the dist payments have proper notification users
  Given dist notice is generated for the dist payments
  Then dist notice must be generated for each dist payment
  Given I trigger notification for the distribution
  Then the notification must be sent to the investors where the distribution notice was generated


Scenario Outline: DIST Notice generation and notification for all
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_distributions_no_payments_1.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "3" capital distributions created
  And Given I upload "capital_distribution_payments.xlsx" file for the Distribution Payments of the fund
  Then There should be "6" distribution payments created
  And the capital distribution payments must have the data in the sheet "capital_distribution_payments.xlsx"
  Given The capital distribution payments are approved
  Given the fund has a Distribution Template
  Given the distribution is approved
  Given the distribution is not manually generated
  Given the distribution payments are completed
  Given I update the fund custom fields "call_notice_on:kyc"
  Given the dist payments have proper notification users

  # Now notice is generated at the kyc level but we havent set skip dist notice in the commitment so it will be generated for all dist payments but where the kyc has multiple dist payments it will have cumulated data
  Given dist notice is generated for the dist payments
  Then dist notice must be generated for each dist payment
  Given I trigger notification for the distribution
  Then the notification must be sent to the investors where the distribution notice was generated


Scenario Outline: DIST Notice generation and notification for only the latest ones at kyc level
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And The multiple commitments have the same investor kycs linked
  And Given I upload "capital_distributions_no_payments_1.xlsx" file for "Distributions" of the fund
  Then I should see the "Import in progress"
  Then There should be "3" capital distributions created
  And Given I upload "capital_distribution_payments_test.xlsx" file for the Distribution Payments of the fund
  Then There should be "6" distribution payments created
  And the new capital distribution payments must have the data in the sheet "capital_distribution_payments_test.xlsx"
  Given The capital distribution payments are approved
  Given the fund has a Distribution Template
  Given the distribution is approved
  Given the distribution is not manually generated
  Given the distribution payments are completed
  Given the dist payments have proper notification users

  Given I update the fund custom fields "call_notice_on:kyc"
  # Now notice is generated at the kyc level but we have set skip dist notice in the commitment that are from the same kyc and earlier i.e. only the latest dist payment for the kyc should have notice generated
  Given I update the dist payments commitments custom fields with the same kyc and earlier payment date "skip_call_notice:Yes"
  Given dist notice is generated for the dist payments

  And dist notice must be generated for the latest dist payment for each kyc

  Given I trigger notification for the distribution
  Then the notification must be sent to the investors where the distribution notice was generated
