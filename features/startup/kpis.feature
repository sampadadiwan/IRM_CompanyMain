Feature: Kpis
  Can create and view Kpis

@import
Scenario Outline: Import Kpis - as company
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
  Given the user has role "company_admin"
  And Given I upload a kpis file for the company
  Then I should see the "Import in progress"
  Then There should be "2" Kpi Report with "8" Kpis created
  And the KPIs must have the data in the sheet
  And when I view the KPI report in grid view
  Then I should see the KPI Report with all Kpis
  Given I log out
  Given there is an existing investor "name=Demo Fund Company" with "1" users 
  Given I login as the investor user
  When I go to the KPIs of the company "Urban"
  Then I should not see the KPI Reports
  When Im given access to the KPI Reports
  When I go to the KPIs of the company "Urban"
  Then I should see the KPI Report
  

@import
Scenario Outline: Import Kpis - as fund
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  And Given I upload a kpis file for the portfolio company
  Then I should see the "Import in progress"
  Then There should be "2" Kpi Report with "8" Kpis created
  And the KPIs must have the data in the sheet
  And when I setup the KPI mappings for the portfolio company
  And when I view the KPI report for the portfolio company in grid view as owner
  Then I should see the KPI Report with all Kpis
  Given I log out
  Given I login as the portfolio company user
  When I go to the KPIs of the company "MyFavStartup"
  Then I should not see the KPI Reports
  
  
