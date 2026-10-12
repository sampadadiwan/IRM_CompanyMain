Feature: Kpis
  Can create and view Kpis

# Portfolio Company entity will upload Kpis via kpi report magic link - so below spec is no longer relevant.
# @import
# Scenario Outline: Import Kpis - as company
#   Given Im logged in as a user "first_name=Test" for an entity "name=MyFavStartup;entity_type=Company"
#   Given the user has role "company_admin"
#   And Given I upload a kpi mappings file for the company
#   And Given I upload a kpis file for the company
#   Then I should see the "Import in progress"
#   Then There should be "2" Kpi Report with "8" Kpis created
#   And the KPIs must have the data in the sheet
#   And when I view the KPI report in grid view
#   Then I should see the KPI Report with all Kpis
#   Given I log out
#   Given there is an existing investor "name=Demo Fund Company" with "1" users
#   Given I login as the investor user
#   When I go to the KPIs of the company "MyFavStartup"
#   Then I should not see the KPI Reports
#   When Im given access to the KPI Reports
#   When I go to the KPIs of the company "MyFavStartup"
#   Then I should see the KPI Report


@import
Scenario Outline: Import Kpis - as fund
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  And Given I upload a kpi mappings file for the company
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


  # Regression test for the "Out of sort memory" bug (see
  # db/migrate/20260924160000_add_sort_memory_fix_indexes.rb and
  # kpi_cumulative.rb/kpi_workbook_reader.rb comments): a real customer workbook large enough to
  # trigger MySQL's filesort limit in production. The Cucumber suite runs against sqlite (see
  # config/environments/test.rb), which has no sort_buffer_size to exhaust, so this can't reproduce
  # the MySQL error itself - what it guards against is a regression in the *fix*, e.g. a future change
  # to fetch_related_*_kpis/find_or_create_kpi_report that drops back to eager_load or loses one of
  # the composite indexes' WHERE-clause shape, silently reintroducing the slow query path even though
  # sqlite would never surface it as a memory error.
  @import
  Scenario: Uploading a large real-world KPI workbook and approving all staged KPIs raises no error
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=RGB;category=Portfolio Company"
    And Given I upload a kpi mappings file "kpi_sort_error/investor_kpi_mappings.xlsx" for the portfolio company
    And I import the KPI workbook "kpi_sort_error/KPI Data.xlsx" for the portfolio company
    Then there should be "600" Kpis for the portfolio company
    When I go to the Kpis tab on the investor show page for the portfolio company
    And I click Actions then "View Including Staged" on the Kpis page
    And I approve all staged KPIs
    Then all pending KPIs for the portfolio company should be approved without error

  @rag_status @rack_test
  Scenario: Calculate KPI RAG Status based on ratio and InvestorKpiMapping rules
    Given Im logged in as a user "first_name=Test;email=test@example.com" for an entity "name=Test Company;entity_type=Company"
    And the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And an Investor KPI Mapping for "Revenue" exists with RAG comparator "benchmark", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And a KpiReport "as_of=2024-01-01;period=YTD;tag_list=benchmark" exists for the entity
    And a KPI "name=Revenue;value=800" exists for the kpi report
    And a KpiReport "as_of=2024-01-01;period=YTD" exists for the entity
    And a KPI "name=Revenue;value=1000" exists for the kpi report
    Then the KPI "Revenue" should have RAG status "green"
