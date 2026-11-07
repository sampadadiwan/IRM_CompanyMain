# Worked examples X5, X6: openspec/changes/dashboard-insight-widgets/business-rules.md#2 and #3
@rack_test
Feature: Company insight widgets show only what the viewer may see
  Another firm's agent reports and the holdings of funds an employee cannot access never appear.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And my firm reports in "INR" for the insight widgets
    And today is "2026-09-30"
    And the insight portfolio companies "Zeta Foods" exist

  # X5 — Error case: another firm's agent report on a same-named company is never shown
  Scenario: Monitoring Status ignores another firm's agent
    Given my firm has a portfolio company agent
    And another firm has its own agent report for a company named "Zeta Foods"
    And the company dashboard has the widget "Monitoring Status" with metadata ""
    When I open the company dashboard of "Zeta Foods"
    Then the "Monitoring Status" insight widget should show "Not checked yet."
    And the "Monitoring Status" insight widget should not show "Other firm's KPI issue"

  # X6 — Error case: an employee's Investment Timeline totals only the funds they can access
  Scenario: Investment Timeline leaves out a fund the employee cannot access
    Given "Growth Fund I" "bought" 1000 shares of "Zeta Foods" for 10000000 on "2025-02-15"
    And "Second Fund" "bought" 1000 shares of "Zeta Foods" for 20000000 on "2025-02-20"
    And the company dashboard has the widget "Investment Timeline" with metadata ""
    And the employee "Ravi" can see "Zeta Foods" and the fund "Growth Fund I" only
    And I sign in as that employee
    When I open the company dashboard of "Zeta Foods"
    Then the "Investment Timeline" insight widget row "Q1 2025" should show "1,00,00,000"
    And the "Investment Timeline" insight widget should not show "3,00,00,000"
