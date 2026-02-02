Feature: KPI Cumulate Functionality

  Scenario: Correctly cumulates monthly KPIs into Quarterly and YTD reports
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name          | value | tag_list |
      | 2023-01-31 | Revenue       | 100   | Actual   |
      | 2023-02-28 | Revenue       | 150   | Actual   |
      | 2023-03-31 | Revenue       | 200   | Actual   |
      | 2023-04-30 | Revenue       | 250   | Actual   |
      | 2023-05-31 | Revenue       | 300   | Actual   |
      | 2023-06-30 | Revenue       | 350   | Actual   |
      | 2024-01-31 | Revenue       | 500   | Actual   |
      | 2024-02-29 | Revenue       | 600   | Actual   |
      | 2023-01-31 | Revenue       | 100   | Budget   |
      | 2023-02-28 | Revenue       | 150   | Budget   |
      | 2023-03-31 | Revenue       | 200   | Budget   |
      | 2023-04-30 | Revenue       | 250   | Budget   |
      | 2023-05-31 | Revenue       | 300   | Budget   |
      | 2023-06-30 | Revenue       | 350   | Budget   |
      | 2024-01-31 | Revenue       | 500   | Budget   |
      | 2024-02-29 | Revenue       | 600   | Budget   |


    When I run the KPI cumulate method for "Revenue"
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