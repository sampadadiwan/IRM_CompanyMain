Feature: Import Fund
  Can import fund details


Scenario Outline: Import capital commitments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "5" capital commitments created
  And the capital commitments must have the data in the sheet
  And the capital commitments must have the percentages updated
  And the fund must have the counter caches updated
  And Given I upload "account_entries.xlsx" file for Account Entries
  Then There should be "5" account_entries created
  And the account_entries must have the data in the sheet
  And the account_entries must visible for each commitment
  

Scenario Outline: Import capital calls
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_calls.xlsx" file for "Capital Calls" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "3" capital calls created
  And the capital calls must have the data in the sheet
  And the remittances are generated for the capital calls
  And the capital commitments are updated with remittance numbers
  And the funds are updated with remittance numbers
  

Scenario Outline: Import capital distributions
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments.xlsx" file for "Commitments" of the fund
  And Given I upload "capital_distributions.xlsx" file for "Capital Distributions" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "3" capital distributions created
  And the capital distributions must have the data in the sheet
  And the payments are generated for the capital distrbutions
  
