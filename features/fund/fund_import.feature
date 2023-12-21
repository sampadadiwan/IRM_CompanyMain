Feature: Import Fund
  Can import fund details


Scenario Outline: Import capital commitments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "8" capital commitments created
  And the capital commitments must have the data in the sheet
  And the capital commitments must have the percentages updated
  And the fund must have the counter caches updated
  And the investors must have access rights to the fund
  And Given I upload "account_entries.xlsx" file for Account Entries
  Then There should be "19" account_entries created
  And the account_entries must have the data in the sheet
  And the account_entries must visible for each commitment


Scenario Outline: Import capital calls
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls.xlsx" file for "Calls" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "3" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers
  And when the exchange rate changes
  Then the commitment amounts change correctly
  # Given the last investor has a user "phone=7721046692"
  # And the capital remittance whatsapp notification is sent to the first investor
  # Then the whatsapp message should be send successfully to "917721046692"

Scenario Outline: Import capital remittance payments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls_no_remittances.xlsx" file for "Calls" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "3" capital calls created
  And Given I upload "capital_remittance_payments_multi_currency.xlsx" file for the remittances of the capital call
  Then There should be "6" remittance payments created
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


Scenario Outline: Import capital remittance
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is a fund "<fund>" for the entity
  And Given I upload an investors file for the fund  
  Given the fund has capital call template
  Given the investors are added to the fund  
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  When I create a new capital call "<call>"
  Then I should see the capital call details
  Then when the capital call is approved
  Then the no remittances should be created
  And Given I upload "capital_remittances.xlsx" file for Call remittances of the fund
  Then the corresponding remittances should be created
  Then I should see the remittances
  And if the first remittance is deleted
  Then the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers


  Examples:
  	|entity                                         |fund                |msg	| call | collected_amount |
  	|entity_type=Investment Fund;enable_funds=true  |name=SAAS Fund;currency=INR      |Fund was successfully created| name=Call 1;call_basis=Upload | 2120000 |



Scenario Outline: Import capital distributions
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_distributions.xlsx" file for "Distributions" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "2" capital distributions created
  And the capital distributions must have the data in the sheet
  And the payments are generated for the capital distrbutions



Scenario Outline: Import Investor Advisors
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And given there are investor advisors "terrie@hansen-inc.com,jeanice@hansen-inc.com,tameika@hansen-inc.com,daisey@hansen-inc.com"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given I upload "investor_advisors.xlsx" file for Investoment Advisors
  Then the investor advisors should be added to each investor



