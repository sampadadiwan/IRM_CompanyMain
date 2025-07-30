Feature: Kpis
  Can create and view Investor Kpi Mappings

@import
Scenario Outline: Import Investor Kpi Mappings - as company
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And KPI is enabled for the user
  Given there is an existing investor "name=Demo Fund Company" with "1" users 
  And I upload an investor kpis mappings file for the company
  Then I should see the "Import in progress"
  Then There should be "2" Investor Kpi Mappings created
  And the Investor Kpi Mappings must have the data in the sheet