# Worked examples X1, X2, X3, X6, X7 — openspec/changes/dashboard-widget-inline-settings/design.md#worked-examples
@rack_test
Feature: Widget settings in place — access
  Only the firm's own users, not acting as investors, may open or save a widget's settings. Direct requests that
  bypass the page are refused the same way, and the panel can change nothing but a widget's settings and size.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{limit: 15}"

  # X1 — Error case: a firm user acting as an investor gets no icons and a direct request is refused
  Scenario: Acting as an investor
    Given I am acting as an investor
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then no widget should have a settings icon
    When I request the settings of the "Valuation Freshness" widget on the "Portfolio Dashboard"
    Then the settings request should be refused

  # X2 — Error case: another firm's widget can be neither opened nor saved
  Scenario: Another firm's widget is refused
    Given another firm has a saved "Valuation Freshness" widget on the "Portfolio Dashboard" with settings "{limit: 15}"
    When I request the settings of the other firm's widget
    Then the settings request should be refused
    When I save the settings "{limit: 1}" with size "Small" for the other firm's widget
    Then the other firm's widget should still have settings "{limit: 15}" and size "XL"

  # X3 — Error case: the LP company dashboard (an LP layout) never shows the icon
  Scenario: The LP company dashboard has no settings icon
    Given the fund has the LP allocation formulas
    And the fund "Growth Fund I" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr | tags     |
      | Acme Robotics | Series B CCPS | 1         | 25.00   | 40.00  | Robotics |
    And LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    And folio "F-012" has allocation entries:
      | formula                  | company       | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 2.50   |
    And the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    And the LP layout "LP" has widgets:
      | widget     | size   |
      | Data Card  | Medium |
      | Valuations | XL     |
    And the company "Acme Robotics" is shown to LPs
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should show the widgets "Data Card, Valuations"
    And no widget should have a settings icon

  # X6 — Error case: an unknown dashboard or widget name is refused and nothing is saved
  Scenario: Unknown dashboard name is refused
    When I request the settings of the default "Anything" widget on the "Nope"
    Then the settings request should be refused
    When I save the settings "" with size "XL" for the default "Anything" widget on the "Nope"
    Then no widget should be saved for the "Nope"

  # X7 — Error case: a save carrying another firm's id, another widget type and layout changes only settings and size
  Scenario: Fields the panel never sends are ignored
    When I save the settings "{limit: 2}" with size "Medium" for the "Valuation Freshness" widget on the "Portfolio Dashboard" with extra fields
    Then the "Valuation Freshness" widget on the "Portfolio Dashboard" should still be my firm's, unchanged but for its settings "{limit: 2}" and size "Medium"
