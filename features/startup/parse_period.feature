Feature: KPI Period Parsing
  As a developer
  I want the parse_period method to correctly interpret various period strings
  So that KPI data can be accurately associated with the correct date.

  Scenario Outline: Parsing supported period strings into dates (Default Fiscal Start: April)
    When I parse the period string "<Input Period>"
    Then the resulting date should be "<Expected Date>"

    # Note: Expected Dates assume default fiscal_year_start_month = 4 (April) where applicable

    Examples: Month formats
      | Input Period     | Expected Date |
      | Jan 21           | 2021-01-31    |
      | January 2021     | 2021-01-31    |
      | Feb 2022         | 2022-02-28    |
      | February 22      | 2022-02-28    |
      | Sept 2020        | 2020-09-30    |
      | September 20     | 2020-09-30    |
      | Dec 1999         | 1999-12-31    |
      | December 99      | 1999-12-31    |

    Examples: Quarter formats
      | Input Period     | Expected Date |
      | Q1FY21           | 2021-06-30    |
      | Q1FY2021         | 2021-06-30    |
      | Q1 FY21          | 2021-06-30    |
      | Q1 2021          | 2021-03-31    |
      | Q1 CY21          | 2021-03-31    |
      | Q1 CY2021        | 2021-03-31    |
      | Q1 21            | 2021-03-31    |
      | Q1 2021          | 2021-03-31    |
      | Jan-Mar 2021     | 2021-03-31    |
      | JFM 2021         | 2021-03-31    |
      | JFM 21           | 2021-03-31    |
      | Q2FY22           | 2022-09-30    |
      | Q2 FY22          | 2022-09-30    |
      | Q2 CY22          | 2022-06-30    |
      | Q2 22            | 2022-06-30    |
      | Apr-Jun 2022     | 2022-06-30    |
      | AMJ 2022         | 2022-06-30    |
      | Q3 2021          | 2021-09-30    |
      | Q3 CY21          | 2021-09-30    |
      | Q3 FY21          | 2021-12-31    |
      | Q3 FY2021        | 2021-12-31    |
      | JAS 2023         | 2023-09-30    |
      | Oct-Dec 2020     | 2020-12-31    |
      | OND 2020         | 2020-12-31    |

    Examples: Year formats
      | Input Period     | Expected Date |
      | 2021             | 2021-12-31    |
      | CY2021           | 2021-12-31    |
      | CY21             | 2021-12-31    |
      | FY2021           | 2021-03-31    |
      | FY21             | 2021-03-31    |
      | FY 2020-21       | 2021-03-31    |
      | FY 20-21         | 2021-03-31    |
      | 2020             | 2020-12-31    |
      | CY2020           | 2020-12-31    |
      | CY20             | 2020-12-31    |
      | FY2020           | 2020-03-31    |
      | FY20             | 2020-03-31    |
      | FY99             | 1999-03-31    |
      | CY1999           | 1999-12-31    |
    Examples: Invalid inputs
      | Input Period     | Expected Date |
      |                  |               |
      | Hello World      |               |
      | FY               |               |
      | 13/2021          |               |
      | Not-A-Date       |               |
      | Q5 2021          |               |
      | ABCDEF           |               |
      | 202113           |               |
      
 
