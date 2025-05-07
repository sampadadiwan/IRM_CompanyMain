Feature: KPI Period Parsing
  As a developer
  I want the parse_period method to correctly interpret various period strings
  So that KPI data can be accurately associated with the correct date.


  Scenario Outline: Check if string is date-like
    Given the string "<input>"
    When I check if it is date-like
    Then the result should be <expected>

    Examples:
      | Q1FY21           | true     |
      | Q1 FY21          | true     |
      | Q1 2021          | true     |
      | Q1 CY21          | true     |
      | Q1 21            | true     |
      | Jan-Mar 2021     | true     |
      | JFM 2021         | true     |
      | Q2FY22           | true     |
      | Q2 FY22          | true     |
      | Q2 CY22          | true     |
      | Q2 2022          | true     |
      | Apr-Jun 2022     | true     |
      | AMJ 2022         | true     |
      | Q3 2021          | true     |
      | Q3 CY21          | true     |
      | Q3 FY2021        | true     |
      | Q3 FY21          | true     |
      | JAS 2023         | true     |
      | Oct-Dec 2020     | true     |
      | OND 2020         | true     |
      | Jan 21          | true     |
      | January 2021    | true     |
      | Feb 2022        | true     |
      | February 22     | true     |
      | Sept 2020       | true     |
      | September 20    | true     |
      | Dec 1999        | true     |
      | December 99     | true     |
      | 01-11-2023      | true     |
      | 03-11-2022      | true     |
      | CY2021          | true     |
      | CY21            | true     |
      | FY2021          | true     |
      | FY2020-21       | true     |
      | FY21            | true     |
      | FY 20-21        | true     |
      | CY2020          | true     |
      | CY20            | true     |
      | FY2020          | true     |
      | FY20            | true     |
      | FY99            | true     |
      | CY1999          | true     |
      |  Q1 FY21           | true     |  # leading space
      | Q1   FY21          | true     |  # multiple internal spaces
      | Q1FY21             | true     |  # no space
      | Q1 2021            | true     |
      | Q1   2021          | true     |
      | Q1CY21             | true     |
      | Q1 CY21            | true     |
      | Jan  21            | true     |
      |  January  2021     | true     |
      | February22         | true     |
      | February   22      | true     |
      | Sept2020           | true     |
      | September  20      | true     |
      |  Dec 1999          | true     |
      | December99         | true     |
      | 01 - 11 - 2023     | true     |  # with spaces around dashes
      | 03-11-2022         | true     |
      | FY 2020 - 21       | true     |
      | FY2020-21          | true     |
      | FY  21             | true     |
      | CY  2020           | true     |
      | CY2020             | true     |

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
      | CY2021           | 2021-12-31    |
      | CY21             | 2021-12-31    |
      | FY2021           | 2021-03-31    |
      | FY21             | 2021-03-31    |
      | FY 2020-21       | 2021-03-31    |
      | FY 20-21         | 2021-03-31    |
      | CY2020           | 2020-12-31    |
      | CY20             | 2020-12-31    |
      | FY2020           | 2020-03-31    |
      | FY20             | 2020-03-31    |
      | FY99             | 1999-03-31    |
      | CY1999           | 1999-12-31    |
    Examples: Invalid inputs
      | Input Period     | Expected Date |
      |                  |               |
      | 2021             |               |      
      | Hello World      |               |
      | FY               |               |
      | 13/2021          |               |
      | Not-A-Date       |               |
      | Q5 2021          |               |
      | ABCDEF           |               |
      | 202113           |               |
      
 
