Feature: Bulk Portfolio Report
  Can create and view a portfolio reports and extracts

Background:
  Given Im logged in as a user "first_name=TestAdmin" for an entity "name=TestEnt;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  And Given I upload a kpi mappings file for the company
  And Given I upload a kpis file for the portfolio company
  Then I should see the "Import in progress"
  Then There should be "2" Kpi Report with "8" Kpis created
  And the KPIs must have the data in the sheet
  And when I setup the KPI mappings for the portfolio company
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  Given there are "2" portfolio investments for the portfolio company in the fund
  Given I setup a portfolio report "name:Analyst Report;include_kpi:true;include_portfolio_investments:true"
  Given There is a kpi report form type setup


Scenario: Generate portfolio report for single portfolio company from show page
  Given I go to the portfolio company show page
  Given I click on "Misc"
  Given I click on "Portfolio Report (Legacy)"
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025;generate_missing_extracts:true"
  Given I trigger report generation
  # With no documents yet, the report is still generated against an empty extract.
  Then The portfolio report should be generated
  Then The portfolio extract should be generated with data "absent"
  Given I add relevant documents to the kpi report
  Given I go to the portfolio company show page
  Given I click on "Misc"
  Given I click on "Portfolio Report (Legacy)"
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025;generate_missing_extracts:true"
  Given I trigger report generation
  Then I should see the "Queued report generation for"
  Then The portfolio report should be generated
  Then The portfolio extract should be generated with data "present"

Scenario: Generate extracts only for multiple portfolio companies from the bulk page
  Given there is another portfolio company "name=Beta Corp;category=Portfolio Company" with a documented kpi report
  Given I add relevant documents to the kpi report
  Given I go to the bulk portfolio report page
  Given I select the portfolio companies for bulk generation
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025"
  Given I trigger extract generation
  Then I should see the "Queued extract generation for"
  Then an extract should be generated for each selected company with data "present"

Scenario: Only-missing option skips companies that already have an extract
  Given there is another portfolio company "name=Gamma Corp;category=Portfolio Company" with a documented kpi report
  Given I add relevant documents to the kpi report
  # First pass: everyone gets an extract.
  Given I go to the bulk portfolio report page
  Given I select the portfolio companies for bulk generation
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025"
  Given I trigger extract generation
  Then an extract should be generated for each selected company with data "present"
  # Second pass with only-missing checked: everyone already has one, so nothing new is generated.
  Given I go to the bulk portfolio report page
  Given I select the portfolio companies for bulk generation
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025;only_missing_extracts:true"
  Given I trigger extract generation
  Then I should see the "Skipped extract generation"
  Then a new extract should only be generated for companies without one

Scenario: Generate a merged report for multiple portfolio companies
  Given there is another portfolio company "name=Delta Corp;category=Portfolio Company" with a documented kpi report
  Given I add relevant documents to the kpi report
  Given I go to the bulk portfolio report page
  Given I select the portfolio companies for bulk generation
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025;generate_missing_extracts:true"
  Given I trigger report generation
  Then I should see the "Queued report generation for"
  Then each selected company should also have its own report document
  Then a single merged report document should be generated

Scenario: Full report generates missing extracts for companies without one
  Given there is another portfolio company "name=Epsilon Corp;category=Portfolio Company" with a documented kpi report
  Given I add relevant documents to the kpi report
  Given I go to the bulk portfolio report page
  Given I select the portfolio companies for bulk generation
  Given I fill in the form with "start_date:01/01/2024;end_date:31/12/2025;generate_missing_extracts:true"
  Given I trigger report generation
  Then an extract should be generated for each selected company with data "present"
