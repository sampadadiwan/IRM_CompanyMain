# Worked examples H3–H8, E3–E19, X4: openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#2 and #3
@rack_test
Feature: Company insight widgets on the Portfolio Company Dashboard
  KPI Movers, KPI Threshold Watch, Monitoring Status, Investment Timeline and Ownership Trend answer
  "what changed, what is outside its limits, is it up to date, when did we invest, how has our stake moved".

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And the fund entity has KPIs enabled
    And my firm reports in "INR" for the insight widgets
    And today is "2026-09-30"
    And the insight portfolio companies "Zeta Foods, Orbit Pay, Kite Robotics" exist

  # H3 — Happy path: KPI Movers ranks the latest report's KPIs by size of change, a fall counting as much as a rise
  Scenario: KPI Movers ranks by size of change
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name      | value | change |
      | Revenue   | 120   | 12.50  |
      | EBITDA    | 30    | -30.00 |
      | Headcount | 51    | 2.00   |
      | Churn     | 5     | 8.00   |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "EBITDA, Revenue, Churn, Headcount"
    And the "KPI Movers" insight widget row "EBITDA" should show "-30.0 %"
    And the "KPI Movers" insight widget row "Revenue" should show "12.5 %"

  # H4 — Happy path: top_n limits the rows
  Scenario: KPI Movers honours top_n
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name      | value | change |
      | Revenue   | 120   | 12.50  |
      | EBITDA    | 30    | -30.00 |
      | Headcount | 51    | 2.00   |
      | Churn     | 5     | 8.00   |
    And the company dashboard has the widget "KPI Movers" with metadata "{top_n: 2}"
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "EBITDA, Revenue"

  # E3 — Edge case: only the latest report with the tag and period is used
  Scenario: KPI Movers reads only the latest report
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-03-31" with:
      | name    | value | change |
      | Revenue | 107   | 50.00  |
    And "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "Revenue"
    And the "KPI Movers" insight widget row "Revenue" should show "12.5 %"
    And the "KPI Movers" insight widget report date should be "30/06/2026"

  # E4 — Edge case: a KPI with no stored change is left out
  Scenario: KPI Movers leaves out KPIs with no change
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
      | NewKPI  | 7     |        |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "Revenue"

  # E5 — Edge case: equal-sized changes sort by KPI name
  Scenario: KPI Movers breaks ties by name
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 10.00  |
      | Margin  | 18    | -10.00 |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "Margin, Revenue"

  # E6 — Edge case: the tag setting picks which report is read
  Scenario: KPI Movers reads the Budget report when told to
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And "Zeta Foods" has an "Budget" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 110   | 3.00   |
    And the company dashboard has the widget "KPI Movers" with metadata "{tag_list: 'Budget'}"
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget row "Revenue" should show "3.0 %"
    And the "KPI Movers" insight widget should show "Budget Quarter report"

  # E7 — Edge case: no report with the tag and period gives the empty-state sentence
  Scenario: KPI Movers with only monthly reports
    Given "Zeta Foods" has an "Actual" "Month" KPI report dated "2026-08-31" with:
      | name    | value | change |
      | Revenue | 40    | 5.00   |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should show "No Actual Quarter KPI report for this company yet."

  # E8 — Edge case: without the KPI module the KPI widgets are not rendered
  Scenario: KPI widgets need the KPI module
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And the company dashboard has the widget "KPI Movers" with metadata ""
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    And the KPI module is switched off for me
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should not be on the page
    And the "KPI Threshold Watch" insight widget should not be on the page

  # H6 — Happy path: KPI Threshold Watch lists red, amber, below and above, in that order
  Scenario: KPI Threshold Watch flags breaches
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name      | value | change | rag | lower | upper |
      | Revenue   | 120   | 5.00   |     | 10    | 25    |
      | EBITDA    | 30    | 2.00   | red |       |       |
      | Churn     | 5     | 30.00  |     |       | 25    |
      | Headcount | 51    | 12.00  |     | 10    | 25    |
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Threshold Watch" insight widget should list the rows "EBITDA, Revenue, Churn"
    And the "KPI Threshold Watch" insight widget flags for "EBITDA" should be "Red"
    And the "KPI Threshold Watch" insight widget flags for "Revenue" should be "Below 10 % threshold"
    And the "KPI Threshold Watch" insight widget flags for "Churn" should be "Above 25 % threshold"

  # E9 — Edge case: a change exactly equal to the threshold is not a breach
  Scenario: KPI Threshold Watch at exactly the threshold
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change | lower |
      | Revenue | 120   | 10.00  | 10    |
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Threshold Watch" insight widget should show "No KPI is outside its limits on the 30/06/2026 report."

  # E10 — Edge case: a zero threshold is ignored
  Scenario: KPI Threshold Watch ignores a zero threshold
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change | lower |
      | Revenue | 120   | -40.00 | 0     |
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Threshold Watch" insight widget should show "No KPI is outside its limits on the 30/06/2026 report."

  # E11 — Edge case: nothing outside its limits gives the empty-state sentence
  Scenario: KPI Threshold Watch with everything within limits
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change | lower | upper |
      | Revenue | 120   | 15.00  | 10    | 25    |
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Threshold Watch" insight widget should show "No KPI is outside its limits on the 30/06/2026 report."

  # E12 — Edge case: green RAG is not a flag, amber is
  Scenario: KPI Threshold Watch ignores green
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change | rag   |
      | Revenue | 120   | 12.50  | green |
      | Churn   | 5     | 1.00   | amber |
    And the company dashboard has the widget "KPI Threshold Watch" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Threshold Watch" insight widget should list the rows "Churn"
    And the "KPI Threshold Watch" insight widget flags for "Churn" should be "Amber"

  # H5 — Happy path: Monitoring Status shows the agent's latest result for the company
  Scenario: Monitoring Status shows the latest agent check
    Given my firm has a portfolio company agent
    And the portfolio company agent has an "latest" report for "Zeta Foods" dated "2026-09-15":
      | area      | severity | message                    |
      | kpi       | blocking | Q2 2026 KPIs not submitted |
      | valuation | success  | Q2 2026 valuation current  |
    And the company dashboard has the widget "Monitoring Status" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Monitoring Status" insight widget should show "Checked on 15/09/2026"
    And the "Monitoring Status" insight widget should show "Blocked"
    And the "Monitoring Status" insight widget should show "1 issue"
    And the "Monitoring Status" insight widget should show "All clear"
    And the "Monitoring Status" insight widget should show "No data"
    And the "Monitoring Status" insight widget should show "Q2 2026 KPIs not submitted"

  # E13 — Edge case: a company the agent has not checked yet
  Scenario: Monitoring Status before the first check
    Given my firm has a portfolio company agent
    And the company dashboard has the widget "Monitoring Status" with metadata ""
    When I open the company dashboard of "Orbit Pay"
    Then the "Monitoring Status" insight widget should show "Not checked yet. The portfolio company agent checks each company once a period."

  # E14 — Edge case: only the latest report counts
  Scenario: Monitoring Status ignores an older report
    Given my firm has a portfolio company agent
    And the portfolio company agent has an "older" report for "Zeta Foods" dated "2026-06-15":
      | area | severity | message                    |
      | kpi  | blocking | Q1 2026 KPIs not submitted |
    And the portfolio company agent has an "latest" report for "Zeta Foods" dated "2026-09-15":
      | area      | severity | message                   |
      | valuation | success  | Q2 2026 valuation current |
    And the company dashboard has the widget "Monitoring Status" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Monitoring Status" insight widget should show "Checked on 15/09/2026"
    And the "Monitoring Status" insight widget should not show "Q1 2026 KPIs not submitted"

  # X4 — Error case: with no portfolio company agent the widget is not rendered and the page still loads
  Scenario: Monitoring Status without an agent
    Given the company dashboard has the widget "Monitoring Status" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Monitoring Status" insight widget should not be on the page
    And I should see "Zeta Foods"

  # H7 — Happy path: Investment Timeline shows buys and sells per quarter, sells negative
  Scenario: Investment Timeline by quarter
    Given "Growth Fund I" "bought" 1000 shares of "Zeta Foods" for 10000000 on "2025-02-15"
    And "Growth Fund I" "bought" 500 shares of "Zeta Foods" for 5000000 on "2025-08-10"
    And "Growth Fund I" "sold" 300 shares of "Zeta Foods" for 3000000 on "2026-09-05"
    And the company dashboard has the widget "Investment Timeline" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Investment Timeline" insight widget should list the rows "Q1 2025, Q3 2025, Q3 2026"
    And the "Investment Timeline" insight widget row "Q1 2025" should show "1,00,00,000"
    And the "Investment Timeline" insight widget row "Q3 2025" should show "50,00,000"
    And the "Investment Timeline" insight widget row "Q3 2026" should show "-"
    And the "Investment Timeline" insight widget row "Q3 2026" should show "30,00,000"

  # E15 — Edge case: funds in two currencies are totalled in the firm's currency; an unconverted one is left out and said so
  Scenario: Investment Timeline across currencies
    Given the fund "Global Fund" is in "USD"
    And the firm has exchange rates between "USD" and "INR"
    And "Growth Fund I" "bought" 1000 shares of "Zeta Foods" for 10000000 on "2025-02-15"
    And "Global Fund" "bought" 100 shares of "Zeta Foods" for 10000 on "2025-03-20"
    And that transaction has a firm-currency amount of 800000
    And "Global Fund" "bought" 50 shares of "Zeta Foods" for 5000 on "2025-03-25"
    And the company dashboard has the widget "Investment Timeline" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Investment Timeline" insight widget row "Q1 2025" should show "1,08,00,000"
    And the "Investment Timeline" insight widget should show "1 transaction in another currency without a INR amount yet"

  # E16 — Edge case: the year setting groups by year
  Scenario: Investment Timeline by year
    Given "Growth Fund I" "bought" 1000 shares of "Zeta Foods" for 10000000 on "2025-02-15"
    And "Growth Fund I" "bought" 500 shares of "Zeta Foods" for 5000000 on "2025-08-10"
    And "Growth Fund I" "sold" 300 shares of "Zeta Foods" for 3000000 on "2026-09-05"
    And the company dashboard has the widget "Investment Timeline" with metadata "{period: 'year'}"
    When I open the company dashboard of "Zeta Foods"
    Then the "Investment Timeline" insight widget should list the rows "2025, 2026"
    And the "Investment Timeline" insight widget row "2025" should show "1,50,00,000"

  # E17 — Edge case: no transactions gives the empty-state sentence
  Scenario: Investment Timeline with no investments
    Given the company dashboard has the widget "Investment Timeline" with metadata ""
    When I open the company dashboard of "Kite Robotics"
    Then the "Investment Timeline" insight widget should show "No investments recorded for this company yet."

  # H8 — Happy path: Ownership Trend plots fully diluted % per holder group on each date
  Scenario: Ownership Trend by holder group
    Given the cap table module is on for me
    And "Zeta Foods" has the cap-table positions:
      | date       | group   | pct   |
      | 2025-03-31 | Self    | 12.00 |
      | 2025-03-31 | Founder | 60.00 |
      | 2025-09-30 | Self    | 10.50 |
      | 2025-09-30 | Founder | 55.00 |
    And the company dashboard has the widget "Ownership Trend" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Ownership Trend" insight widget should list the rows "2025-03-31 Founder, 2025-03-31 Self, 2025-09-30 Founder, 2025-09-30 Self"
    And the "Ownership Trend" insight widget row "2025-09-30 Self" should show "10.50 %"
    And the "Ownership Trend" insight widget row "2025-03-31 Founder" should show "31/03/2025"

  # E18 — Edge case: positions without a date or a % are skipped
  Scenario: Ownership Trend skips undated and blank positions
    Given the cap table module is on for me
    And "Zeta Foods" has the cap-table positions:
      | date       | group   | pct   | round   |
      | 2025-03-31 | Self    | 12.00 |         |
      |            | Founder | 60.00 | Seed    |
      | 2025-03-31 | Other   |       |         |
    And the company dashboard has the widget "Ownership Trend" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Ownership Trend" insight widget should list the rows "2025-03-31 Self"

  # E19 — Edge case: nothing usable gives the empty-state sentence
  Scenario: Ownership Trend with no dated positions
    Given the cap table module is on for me
    And "Zeta Foods" has the cap-table positions:
      | date | group   | pct   | round |
      |      | Founder | 60.00 | Seed  |
    And the company dashboard has the widget "Ownership Trend" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Ownership Trend" insight widget should show "No dated cap-table positions with a fully diluted % yet."
