Feature: Report create and destroy
  Create and destroy report

@import
Scenario Outline: Create and destroy report
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" capital commitments created
  And the imported data must have the form_type updated
  And the capital commitments must have the data in the sheet
  Given I ransack filter the "Commitments"
  And I save the filtered data as a report "Commitments Report"
  Then I should be able to view the report details
  Given I delete the report
  Then The report should be deleted
  

