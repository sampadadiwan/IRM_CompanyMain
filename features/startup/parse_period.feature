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
    And the parsed type should be "<Type>"

    # Note: Expected Dates assume default fiscal_year_start_month = 4 (April) where applicable

    Examples: Quarter formats
      | Input Period       | Expected Date | Type     |
      | Q1FY21             | 2020-06-30    | Quarter  |
      | Q1 FY21            | 2020-06-30    | Quarter  |
      | Q1 2021            | 2021-03-31    | Quarter  |
      | Q1 CY21            | 2021-03-31    | Quarter  |
      | Q1 21              | 2021-03-31    | Quarter  |
      | Jan-Mar 2021       | 2021-03-31    | Quarter  |
      | JFM 2021           | 2021-03-31    | Quarter  |
      | Q2FY22             | 2021-09-30    | Quarter  |
      | Q2 FY22            | 2021-09-30    | Quarter  |
      | Q2 CY22            | 2022-06-30    | Quarter  |
      | Q2 2022            | 2022-06-30    | Quarter  |
      | Apr-Jun 2022       | 2022-06-30    | Quarter  |
      | AMJ 2022           | 2022-06-30    | Quarter  |
      | Q3 2021            | 2021-09-30    | Quarter  |
      | Q3 CY21            | 2021-09-30    | Quarter  |
      | Q3 FY2021          | 2020-12-31    | Quarter  |
      | Q3 FY21            | 2020-12-31    | Quarter  |
      | JAS 2023           | 2023-09-30    | Quarter  |
      | Oct-Dec 2020       | 2020-12-31    | Quarter  |
      | OND 2020           | 2020-12-31    | Quarter  |
      | Q4 2021            | 2021-12-31    | Quarter  |
      | Q4 CY21            | 2021-12-31    | Quarter  |
      | Q4 FY2021          | 2021-03-31    | Quarter  |
      | Q4 FY21            | 2021-03-31    | Quarter  |
      | JFM 2023           | 2023-03-31    | Quarter  |
      | Jan-Mar 2023       | 2023-03-31    | Quarter  |

    Examples: Month formats
      | Input Period     | Expected Date | Type   |
      | Jan 21           | 2021-01-31    | Month  |
      | January 2021     | 2021-01-31    | Month  |
      | Feb 2022         | 2022-02-28    | Month  |
      | February 22      | 2022-02-28    | Month  |
      | Sept 2020        | 2020-09-30    | Month  |
      | September 20     | 2020-09-30    | Month  |
      | Dec 1999         | 1999-12-31    | Month  |
      | December 99      | 1999-12-31    | Month  |
      | 01-11-2023       | 2023-11-30    | Month  |
      | 03-11-2022       | 2022-11-30    | Month  |

    Examples: Year formats
      | Input Period   | Expected Date | Type  |
      | 2021           | 2021-12-31    | Year  |
      | CY2021         | 2021-12-31    | Year  |
      | CY21           | 2021-12-31    | Year  |
      | FY2021         | 2021-03-31    | Year  |
      | FY2020-21      | 2021-03-31    | Year  |
      | FY21           | 2021-03-31    | Year  |
      | FY 20-21       | 2021-03-31    | Year  |
      | 2020           | 2020-12-31    | Year  |
      | CY2020         | 2020-12-31    | Year  |
      | CY20           | 2020-12-31    | Year  |
      | FY2020         | 2020-03-31    | Year  |
      | FY20           | 2020-03-31    | Year  |
      | FY99           | 1999-03-31    | Year  |
      | CY1999         | 1999-12-31    | Year  |

  Examples: YTD formats
    | Input Period        | Expected Date | Type  |
    | YTD Nov 23          | 2023-11-30    | YTD   |
    | YTD-Jan 2022        | 2022-01-31    | YTD   |
    | ytd Jan-Sept 2023   | 2023-09-30    | YTD   |

  Examples: Half Year formats
    | Input Period   | Expected Date | Type       |
    | H1 2023        | 2023-06-30    | half year  |
    | H1 FY2023      | 2022-09-30    | half year  |
    | H1 FY23        | 2022-09-30    | half year  |
