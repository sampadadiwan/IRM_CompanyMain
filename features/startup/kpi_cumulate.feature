Feature: KPI Cumulate Functionality

  Scenario: Correctly cumulates monthly KPIs into Quarterly and YTD reports
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name          | value |
      | 2023-01-31 | Revenue       | 100   |
      | 2023-02-28 | Revenue       | 150   |
      | 2023-03-31 | Revenue       | 200   |
      | 2023-04-30 | Revenue       | 250   |
      | 2023-05-31 | Revenue       | 300   |
      | 2023-06-30 | Revenue       | 350   |
      | 2024-01-31 | Revenue       | 500   |
      | 2024-02-29 | Revenue       | 600   |

    When I run the KPI cumulate method for "Revenue"
    Then Quarterly KPI should be cumulated correctly for "Revenue"
    And YTD KPI should be cumulated correctly for "Revenue"