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
      | Jan 2021         | 2021-01-01    |
      | Jan 21           | 2021-01-01    |
      | January 2021     | 2021-01-01    |

    Examples: Quarter formats
      | Input Period     | Expected Date |
      | Q1FY21           | 2020-04-01    |
      | Q1 FY21          | 2020-04-01    |
      | Jan-Mar 2021     | 2021-01-01    |
      | JFM 2021         | 2021-01-01    |

    Examples: Year formats
      | Input Period     | Expected Date |
      | 2021             | 2021-01-01    |
      | CY2021           | 2021-01-01    |
      | CY21             | 2021-01-01    |
      | FY2021           | 2020-04-01    |
      | FY21             | 2020-04-01    |

    Examples: Invalid inputs
      | Input Period     | Expected Date |
      |                  |               |
      | Hello World      |               |
      | Q5FY21           |               |
      | Jan-March 2021   |               |
      | FY               |               |
      | 13/2021          |               |
      | Not-A-Date       |               |

  Scenario Outline: Parsing supported fiscal periods with custom fiscal year start
    When I parse the period string "<Input Period>" with fiscal start month <Fiscal Start Month>
    Then the resulting date should be "<Expected Date>"

    Examples: Fiscal Start Month = 1 (January)
      | Fiscal Start Month | Input Period | Expected Date |
      | 1                  | Q1FY24       | 2024-01-01    |
      | 1                  | FY24         | 2024-01-01    |

    Examples: Fiscal Start Month = 7 (July)
      | Fiscal Start Month | Input Period | Expected Date |
      | 7                  | Q1FY24       | 2023-07-01    |
      | 7                  | FY24         | 2023-07-01    |
