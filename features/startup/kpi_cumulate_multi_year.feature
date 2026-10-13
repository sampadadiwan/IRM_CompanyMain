@rack_test
Feature: KPI Cumulate Multi-Year Functionality

  Scenario: Correctly cumulates monthly KPIs into Quarterly, YTD, and Year reports across multiple years
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MultiYearStartup;category=Portfolio Company"
    # Assuming fiscal year starts in April (default)
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name          | value | tag_list |
      # FY 2022 (April 2022 - March 2023)
      | 2022-04-30 | Revenue       | 100   | Actual   |
      | 2022-05-31 | Revenue       | 110   | Actual   |
      | 2022-06-30 | Revenue       | 120   | Actual   |
      | 2022-07-31 | Revenue       | 130   | Actual   |
      | 2022-08-31 | Revenue       | 140   | Actual   |
      | 2022-09-30 | Revenue       | 150   | Actual   |
      | 2022-10-31 | Revenue       | 160   | Actual   |
      | 2022-11-30 | Revenue       | 170   | Actual   |
      | 2022-12-31 | Revenue       | 180   | Actual   |
      | 2023-01-31 | Revenue       | 190   | Actual   |
      | 2023-02-28 | Revenue       | 200   | Actual   |
      | 2023-03-31 | Revenue       | 210   | Actual   |
      # FY 2023 (April 2023 - March 2024)
      | 2023-04-30 | Revenue       | 300   | Actual   |
      | 2023-05-31 | Revenue       | 310   | Actual   |
      | 2023-06-30 | Revenue       | 320   | Actual   |
      | 2023-07-31 | Revenue       | 330   | Actual   |
      | 2023-08-31 | Revenue       | 340   | Actual   |
      | 2023-09-30 | Revenue       | 350   | Actual   |
      | 2023-10-31 | Revenue       | 360   | Actual   |
      | 2023-11-30 | Revenue       | 370   | Actual   |
      | 2023-12-31 | Revenue       | 380   | Actual   |
      | 2024-01-31 | Revenue       | 390   | Actual   |
      | 2024-02-29 | Revenue       | 400   | Actual   |
      | 2024-03-31 | Revenue       | 410   | Actual   |

    When I run the KPI cumulate method for "Revenue"
    Then Quarterly KPI should be cumulated correctly for "Revenue"
    And YTD KPI should be cumulated correctly for "Revenue"
    # FY 2022: 100+110+120+130+140+150+160+170+180+190+200+210 = 1860
    Then I should see a "Year" KPI "Revenue" for "2023-03-31" with value "1860.0"
    # FY 2023: 300+310+320+330+340+350+360+370+380+390+400+410 = 4260
    And I should see a "Year" KPI "Revenue" for "2024-03-31" with value "4260.0"
