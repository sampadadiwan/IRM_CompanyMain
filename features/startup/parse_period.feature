# features/kpi/parse_period.feature
Feature: KPI Period Parsing
  As a developer
  I want the KpiWorkbookReader#parse_period method to correctly interpret various period strings
  So that KPI data can be accurately associated with the correct date.

  Background:
    Given a KpiWorkbookReader is initialized

  Scenario Outline: Parsing various period strings into dates (Default Fiscal Start: April)
    When I parse the period string "<Input Period>"
    Then the resulting date should be "<Expected Date>"

    # Note: Expected Dates assume default fiscal_year_start_month = 4 (April) where applicable

    Examples: Standard Date.parse Formats
      | Input Period | Expected Date |
      | 2024-03-15   | 2024-03-15    |
      | 15 Feb 2024  | 2024-02-15    |
      | 01/10/2023   | 2023-10-01    | 

    Examples: Fiscal Quarters (Q[1-4] FYxxxx or FYxxxx Q[1-4])
      | Input Period | Expected Date | Comment           |
      | Q1 FY24      | 2023-04-01    | FY24 Q1           |
      | Q2 FY24      | 2023-07-01    | FY24 Q2           |
      | Q3 FY24      | 2023-10-01    | FY24 Q3           |
      | Q4 FY24      | 2024-01-01    | FY24 Q4           |
      | Q1-FY2024    | 2023-04-01    | FY24 Q1           |
      | Q3 FY 23     | 2022-10-01    | FY23 Q3           |
      | FY24 Q1      | 2023-04-01    | FY24 Q1           |
      | FY 24 Q 2    | 2023-07-01    | FY24 Q2           |
      | FY2023 Q4    | 2023-01-01    | FY23 Q4           |

    Examples: Fiscal Quarters (Q[1-4] YYYY) - Uses fiscal calculation
      | Input Period | Expected Date | Comment           |
      | Q1 2024      | 2023-04-01    | FY24 Q1           |
      | Q2 2024      | 2023-07-01    | FY24 Q2           |
      | Q3 2024      | 2023-10-01    | FY24 Q3           |
      | Q4 2024      | 2024-01-01    | FY24 Q4           |
      | Q1 2023      | 2022-04-01    | FY23 Q1           |
      | Q4 2023      | 2023-01-01    | FY23 Q4           |

    Examples: Fiscal Years (FYxxxx)
      | Input Period | Expected Date | Comment           |
      | FY24         | 2023-04-01    | Start of FY24     |
      | FY 2024      | 2023-04-01    | Start of FY24     |
      | FY99         | 1998-04-01    | Start of FY99     |
      | FY05         | 2004-04-01    | Start of FY05     |

    Examples: Fiscal Months (Month FYxxxx) - Parsed as Calendar Month/Year
      | Input Period | Expected Date | Comment           |
      | Jan FY24     | 2024-01-01    | Calendar Jan 2024 |
      | Apr FY24     | 2024-04-01    | Calendar Apr 2024 |
      | Dec FY 23    | 2023-12-01    | Calendar Dec 2023 |
      | February FY99| 1999-02-01    | Calendar Feb 1999 |

    Examples: Calendar Year (CY YYYY)
      | Input Period | Expected Date | Comment           |
      | CY 2024      | 2024-01-01    | Start of CY2024   |
      | CY 2023      | 2023-01-01    | Start of CY2023   |

    Examples: Strptime Formats
      | Input Period | Expected Date |
      | Jan-24       | 2024-01-01    |
      | Feb-2024     | 2024-02-01    |
      | Mar 24       | 2024-03-01    |
      | Apr 2024     | 2024-04-01    |
      | May-99       | 1999-05-01    |
      | Jun 05       | 2005-06-01    |
      | 01-24        | 2024-01-01    |
      | 02-2024      | 2024-02-01    |
      | 2024-03      | 2024-03-01    |
      | 2024/04      | 2024-04-01    |
      | 05/2024      | 2024-05-01    |
      | 06/24        | 2024-06-01    |
      | 2024/Jul     | 2024-07-01    |
      | 2023/August  | 2023-08-01    |

    Examples: Invalid or Blank Inputs
      | Input Period    | Expected Date | Comment                 |
      |                 |               | Blank input             |
      | Total           |               | Non-date string         |
      | Q5 FY24         |               | Invalid quarter         |
      | FY24 Q0         |               | Invalid quarter         |
      | Q1 FY           |               | Missing year            |
      | FY              |               | Missing year            |
      | Jan FY          |               | Missing year            |
      | CY              |               | Missing year            |
      | CY2024          |               | Needs space             |
      | 13/2024         |               | Invalid month           |
      | Not-A-Date-99   |               | Unparseable             |

  Scenario Outline: Parsing fiscal periods with different start months
    Given a KpiWorkbookReader is initialized with fiscal start month <Fiscal Start Month>
    When I parse the period string "<Input Period>"
    Then the resulting date should be "<Expected Date>"

    Examples: Fiscal Start Month = 1 (January)
      | Fiscal Start Month | Input Period | Expected Date | Comment           |
      | 1                  | Q1 FY24      | 2024-01-01    | FY24 Q1           |
      | 1                  | Q4 FY24      | 2024-10-01    | FY24 Q4           |
      | 1                  | FY24         | 2024-01-01    | Start of FY24     |
      | 1                  | Q1 2024      | 2024-01-01    | FY24 Q1           |
      | 1                  | Q4 2023      | 2023-10-01    | FY23 Q4           |

    Examples: Fiscal Start Month = 7 (July)
      | Fiscal Start Month | Input Period | Expected Date | Comment           |
      | 7                  | Q1 FY24      | 2023-07-01    | FY24 Q1           |
      | 7                  | Q2 FY24      | 2023-10-01    | FY24 Q2           |
      | 7                  | Q3 FY24      | 2024-01-01    | FY24 Q3           |
      | 7                  | Q4 FY24      | 2024-04-01    | FY24 Q4           |
      | 7                  | FY24         | 2023-07-01    | Start of FY24     |
      | 7                  | Q1 2024      | 2023-07-01    | FY24 Q1           |
      | 7                  | Q4 2023      | 2023-04-01    | FY23 Q4           |