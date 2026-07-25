Feature: KPI Cumulate Functionality

  Scenario: Correctly cumulates monthly KPIs into Quarterly, YTD, and Year reports across multiple years
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MultiYearStartup;category=Portfolio Company"
    # Assuming fiscal year starts in April (default)
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      # FY 2022 (April 2022 - March 2023)
      | 2022-04-30 | Revenue | 100   | Actual   |
      | 2022-05-31 | Revenue | 110   | Actual   |
      | 2022-06-30 | Revenue | 120   | Actual   |
      | 2022-07-31 | Revenue | 130   | Actual   |
      | 2022-08-31 | Revenue | 140   | Actual   |
      | 2022-09-30 | Revenue | 150   | Actual   |
      | 2022-10-31 | Revenue | 160   | Actual   |
      | 2022-11-30 | Revenue | 170   | Actual   |
      | 2022-12-31 | Revenue | 180   | Actual   |
      | 2023-01-31 | Revenue | 190   | Actual   |
      | 2023-02-28 | Revenue | 200   | Actual   |
      | 2023-03-31 | Revenue | 210   | Actual   |
      # FY 2023 (April 2023 - March 2024)
      | 2023-04-30 | Revenue | 300   | Actual   |
      | 2023-05-31 | Revenue | 310   | Actual   |
      | 2023-06-30 | Revenue | 320   | Actual   |
      | 2023-07-31 | Revenue | 330   | Actual   |
      | 2023-08-31 | Revenue | 340   | Actual   |
      | 2023-09-30 | Revenue | 350   | Actual   |
      | 2023-10-31 | Revenue | 360   | Actual   |
      | 2023-11-30 | Revenue | 370   | Actual   |
      | 2023-12-31 | Revenue | 380   | Actual   |
      | 2024-01-31 | Revenue | 390   | Actual   |
      | 2024-02-29 | Revenue | 400   | Actual   |
      | 2024-03-31 | Revenue | 410   | Actual   |

    When I run the KPI cumulate method for "Revenue"
    Then Quarterly KPI should be cumulated correctly for "Revenue"
    And YTD KPI should be cumulated correctly for "Revenue"
    # FY 2022: 100+110+120+130+140+150+160+170+180+190+200+210 = 1860
    Then I should see a "Year" KPI "Revenue" for "2023-03-31" with value "1860.0"
    # FY 2023: 300+310+320+330+340+350+360+370+380+390+400+410 = 4260
    And I should see a "Year" KPI "Revenue" for "2024-03-31" with value "4260.0"
    Then Quarterly KPI should be cumulated correctly for "Revenue"
    And YTD KPI should be cumulated correctly for "Revenue"

  Scenario: Only approved KPIs are cumulated
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | status     |
      | 2023-01-31 | Revenue | 100   | approved   |
      | 2023-02-28 | Revenue | 150   | unapproved |
      | 2023-03-31 | Revenue | 200   | approved   |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2023-03-31" with value "300.0"

  Scenario: Existing cumulative KPI is replaced if value is different
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2023-01-31 | Revenue | 100   |
      | 2023-02-28 | Revenue | 150   |
      | 2023-03-31 | Revenue | 200   |
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  |
      | 2023-03-31 | Revenue | 999   | Quarter |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2023-03-31" with value "450.0"
    And the "Quarter" KPI "Revenue" for "2023-03-31" should have 1 record

  Scenario: Year period KPI is only created when 12 months are present
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    # Case 1: 11 months within FY 2023 (April to February)
    # FY 2023 starts on 2023-04-01 (default)
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2023-04-30 | Revenue | 100   |
      | 2023-05-31 | Revenue | 100   |
      | 2023-06-30 | Revenue | 100   |
      | 2023-07-31 | Revenue | 100   |
      | 2023-08-31 | Revenue | 100   |
      | 2023-09-30 | Revenue | 100   |
      | 2023-10-31 | Revenue | 100   |
      | 2023-11-30 | Revenue | 100   |
      | 2023-12-31 | Revenue | 100   |
      | 2024-01-31 | Revenue | 100   |
      | 2024-02-29 | Revenue | 100   |
    When I run the KPI cumulate method for "Revenue"
    Then I should NOT see a "Year" KPI "Revenue" for "2024-02-29"

    # Case 2: 12 months within FY 2023 (April to March)
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2024-03-31 | Revenue | 100   |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Year" KPI "Revenue" for "2024-03-31" with value "1200.0"

  Scenario: Existing cumulative KPI is NOT replaced if value is the same
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2023-01-31 | Revenue | 100   |
      | 2023-02-28 | Revenue | 150   |
      | 2023-03-31 | Revenue | 200   |
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  |
      | 2023-03-31 | Revenue | 450   | Quarter |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2023-03-31" with value "450.0"
    And the "Quarter" KPI "Revenue" for "2023-03-31" should have 1 record

  # Regression: KpiCumulateJob must trigger the percentage-change job itself (after cumulation)
  # so the freshly cumulated Quarter/YTD/Year KPIs get MoM/YoY changes too. Cumulatives also
  # inherit the source KPI's mapping — otherwise the mapping-id validation would reject them.
  Scenario: Percentage changes are computed over the cumulated KPIs in the same run
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2023-01-31 | Revenue | 100   |
      | 2023-02-28 | Revenue | 150   |
      | 2023-03-31 | Revenue | 200   |
      | 2023-04-30 | Revenue | 300   |
      | 2023-05-31 | Revenue | 310   |
      | 2023-06-30 | Revenue | 320   |
    When I run the KpiCumulateJob with percentage change computation
    Then I should see a "Quarter" KPI "Revenue" for "2023-03-31" with value "450.0"
    And I should see a "Quarter" KPI "Revenue" for "2023-06-30" with value "930.0"
    And the "Quarter" KPI "Revenue" for "2023-06-30" should have a percentage change
    And the "Quarter" KPI "Revenue" for "2023-06-30" should be linked to the "Revenue" mapping

  # Regression: a cumulative KPI that fails to save (e.g. a validation error) must surface in the
  # job's error email — previously the non-bang save swallowed the failure and the company's
  # cumulative totals silently stopped updating.
  Scenario: Failed cumulative KPI saves are reported by email instead of being silently dropped
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2023-01-31 | Revenue | 100   |
      | 2023-02-28 | Revenue | 150   |
      | 2023-03-31 | Revenue | 200   |
    And cumulative KPI saves will fail
    When I run the KpiCumulateJob for the portfolio company
    Then a KPI cumulation error email should be sent