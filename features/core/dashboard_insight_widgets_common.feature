# Worked examples (H1, H2, E1, E2, X1, X2): openspec/changes/dashboard-insight-widgets/business-rules.md#1-rules-every-widget-follows--phase-1
Feature: Rules every dashboard insight widget follows
  The 17 insight widgets are offered on their dashboards only, label and explain every setting, fall back to
  defaults for bad settings, and are never shown to LPs.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"

  # H1 — Happy path: each new widget is offered on exactly its dashboards in the New Widget form
  @rack_test
  Scenario Outline: New widget offered on its dashboards
    When I go to the new dashboard widget page
    Then the new widget form should offer "<widget>" only on "<dashboards>"

    Examples:
      | widget                    | dashboards                                                   |
      | KPI Movers                | Portfolio Company Dashboard                                  |
      | KPI Threshold Watch       | Portfolio Company Dashboard                                  |
      | Monitoring Status         | Portfolio Company Dashboard                                  |
      | Investment Timeline       | Portfolio Company Dashboard                                  |
      | Ownership Trend           | Portfolio Company Dashboard                                  |
      | Valuation Freshness       | Portfolio Dashboard, Aggregated Portfolio Dashboard          |
      | Winners & Losers          | Portfolio Dashboard                                          |
      | Sector Exposure           | Portfolio Dashboard                                          |
      | Peer KPI Comparison       | Aggregated Portfolio Dashboard                               |
      | Remittance Ageing         | Fund Dashboard                                               |
      | NAV per Unit Trend        | Fund Dashboard                                               |
      | Hedge Expiries            | Fund Dashboard                                               |
      | Investor Pending Actions  | Investor Dashboard                                           |
      | Side-letter Obligations   | Investor Dashboard, Ops Dashboard                            |
      | Needs Attention           | Ops Dashboard, FM Landing Page                               |
      | Overdue Tasks by Assignee | Ops Dashboard                                                |
      | Stuck Workflows           | Ops Dashboard                                                |

  # H2 — Happy path: every setting of a new widget shows its label and its help line
  @rack_test
  Scenario Outline: Settings are labelled and explained
    Given the "<widget>" widget on the "<dashboard>" has settings ""
    When I go to the edit page for the "<widget>" widget
    Then the field "<key>" should have the label "<label>"
    And the field "<key>" should have helper text containing "<help>"

    Examples:
      | widget                    | dashboard                      | key             | label                        | help                                  |
      | KPI Movers                | Portfolio Company Dashboard    | top_n           | Rows to show                 | Default 5.                            |
      | KPI Movers                | Portfolio Company Dashboard    | tag_list        | Report tag                   | Default Actual.                       |
      | KPI Movers                | Portfolio Company Dashboard    | period          | Report period                | Default Quarter.                      |
      | KPI Threshold Watch       | Portfolio Company Dashboard    | period          | Report period                | Default Quarter.                      |
      | Investment Timeline       | Portfolio Company Dashboard    | period          | Group by                     | Default quarter.                      |
      | Valuation Freshness       | Portfolio Dashboard            | current_days    | Current up to (days)         | Default 90.                           |
      | Valuation Freshness       | Portfolio Dashboard            | due_days        | Due up to (days)             | Default 180.                          |
      | Valuation Freshness       | Portfolio Dashboard            | limit           | Rows to show                 | Default 15.                           |
      | Winners & Losers          | Portfolio Dashboard            | top_n           | Rows per list                | Default 5.                            |
      | Sector Exposure           | Portfolio Dashboard            | measure         | Measure                      | Default fmv.                          |
      | Peer KPI Comparison       | Aggregated Portfolio Dashboard | kpi_name        | KPI name                     | e.g. Revenue.                         |
      | NAV per Unit Trend        | Fund Dashboard                 | months          | Months                       | Default 12.                           |
      | Hedge Expiries            | Fund Dashboard                 | days            | Expiring within (days)       | Default 90.                           |
      | Investor Pending Actions  | Investor Dashboard             | kyc_expiry_days | KYC expiry warning (days)    | Default 60.                           |
      | Side-letter Obligations   | Ops Dashboard                  | days            | Due within (days)            | Default 30.                           |
      | Overdue Tasks by Assignee | Ops Dashboard                  | top_n           | People to show               | Default 10.                           |
      | Stuck Workflows           | Ops Dashboard                  | days            | Waiting at least (days)      | Default 7.                            |
      | Stuck Workflows           | Ops Dashboard                  | limit           | Rows to show                 | Default 10.                           |
 
  # E1 — Edge case: a zero setting falls back to its default (top_n 0 → 5 rows)
  @rack_test
  Scenario: Zero setting uses the default
    Given the fund entity has KPIs enabled
    And my firm reports in "INR" for the insight widgets
    And today is "2026-09-30"
    And the insight portfolio companies "Zeta Foods" exist
    And "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name      | value | change |
      | Revenue   | 120   | 12.50  |
      | EBITDA    | 30    | -30.00 |
      | Headcount | 51    | 2.00   |
      | Churn     | 5     | 8.00   |
      | Margin    | 25    | 6.00   |
      | Cash      | 80    | 1.00   |
    And the company dashboard has the widget "KPI Movers" with metadata "{top_n: 0}"
    When I open the company dashboard of "Zeta Foods"
    Then the "KPI Movers" insight widget should list the rows "EBITDA, Revenue, Churn, Margin, Headcount"

  # E2 — Edge case: text where a number is expected falls back to the default (current_days 'abc' → 90)
  @rack_test
  Scenario: Text setting uses the default
    Given today is "2026-09-30"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund "Growth Fund I" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Zeta Foods | Equity     | 1         | 4.00    | 6.00   |
    And the insight company "Zeta Foods" was valued on "2026-07-02"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 'abc'}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness counts should be "Current 1, Due 0, Stale 0, Never 0"

  # X1 — Error case: none of the new company widgets can be placed in an LP layout
  @rack_test
  Scenario Outline: New widget refused in an LP layout
    When a request saves a "<widget>" widget into the layout "LP"
    Then the widget save should be refused with "This widget can't be added to an LP layout: it isn't safe to show LPs."

    Examples:
      | widget              |
      | KPI Movers          |
      | KPI Threshold Watch |
      | Monitoring Status   |
      | Investment Timeline |
      | Ownership Trend     |

  # X2 — Error case: an investor-role user opening a dashboard that holds an insight widget never sees its body
  @rack_test
  Scenario: LP never sees an insight widget
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund has the LP allocation formulas
    And the fund "Growth Fund I" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics | Series B CCPS | 1         | 25.00   | 40.00  |
    And LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    And the fund "Growth Fund I" LP portfolio view is "whole_fund"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the "Valuation Freshness" insight widget should be rendered
    When LP "Ravi Menon" opens the portfolio dashboard of "Growth Fund I"
    Then the "Valuation Freshness" insight widget should not be rendered
