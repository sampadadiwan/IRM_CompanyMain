# Worked examples H3, H4, H5, H6, E3, E7, E8 — openspec/changes/dashboard-widget-inline-settings/design.md#worked-examples
# (the panel itself: features/core/dashboard_widget_inline_settings.feature)
Feature: Widget settings in place — reloading only that widget
  After Save only the changed widget reloads, through the page's own address so its context (the fund, the
  company, the filters) stays right; the first save on a dashboard showing its defaults refreshes the page once.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund "Growth Fund I" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Zeta Foods    | Equity        | 1         | 4.00    | 6.00   |
      | Orbit Pay     | Series A CCPS | 1         | 2.00    | 3.00   |
      | Kite Robotics | Seed CCPS     | 1         | 1.00    | 1.00   |
    And the "Sector Exposure" widget on the "Portfolio Dashboard" has settings ""
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 90, due_days: 180, limit: 15}"

  # H3 — Happy path: Rows to show 2 → the widget alone reloads with 2 of 3 rows; Sector Exposure is untouched
  Scenario: Saving reloads only that widget
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I mark the "Sector Exposure" widget
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "2" in the settings popup
    And I click "Save" in the settings popup
    Then a saved message should say "Valuation Freshness updated"
    And Valuation Freshness should say "Showing 2 of 3"
    And the "Sector Exposure" widget should not have been reloaded
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 2}"

  # H4 — Happy path: Size Medium takes effect in the same refresh (half the row)
  Scenario: A new size takes effect in the same refresh
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Size" to "Medium" in the settings popup
    And I click "Save" in the settings popup
    Then a saved message should say "Valuation Freshness updated"
    And the "Valuation Freshness" widget should take the "col-md-6" column
    And the saved size of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "Medium"

  # H5 — Happy path: the first save on the Ops Dashboard (showing its defaults) saves them all, then refreshes the page
  Scenario: First save on a dashboard showing its defaults
    When I open the Ops Dashboard for the ops insight widgets
    And I open the settings of the "My Tasks" widget
    And I set "Size" to "Large" in the settings popup
    And I click "Save" in the settings popup
    Then the "Ops Dashboard" should have its default widgets saved once, in order
    And the saved size of the "My Tasks" widget on the "Ops Dashboard" should be "Large"
    And every widget on the page should have a settings icon

  # H6 — Happy path: on the Aggregated dashboard filtered to Zeta Foods, the reloaded widget keeps the filter
  Scenario: The Aggregated dashboard keeps its filters
    Given the "Valuation Freshness" widget on the "Aggregated Portfolio Dashboard" has settings "{limit: 15}"
    When I open the stakeholders portfolio dashboard filtered to "Zeta Foods"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "3" in the settings popup
    And I click "Save" in the settings popup
    Then a saved message should say "Valuation Freshness updated"
    And Valuation Freshness should list only "Zeta Foods"

  # E3 — Edge case: clearing Rows to show leaves the setting out, so the widget falls back to its default (15)
  Scenario: A cleared setting falls back to the widget's default
    Given the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 90, due_days: 180, limit: 2}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "" in the settings popup
    And I click "Save" in the settings popup
    Then a saved message should say "Valuation Freshness updated"
    And Valuation Freshness should list 3 companies
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180}"

  # E7 — Edge case: with reduced motion the widget refreshes the same way, without the highlight
  Scenario: Reduced motion
    Given my browser asks for reduced motion
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "2" in the settings popup
    And I click "Save" in the settings popup
    Then a saved message should say "Valuation Freshness updated"
    And Valuation Freshness should say "Showing 2 of 3"
    And the "Valuation Freshness" widget should not be highlighted

  # E8 — Edge case: a widget key that is not on the page draws no widget and no error
  @rack_test
  Scenario: Unknown widget key
    When I open the "Portfolio Dashboard" of fund "Growth Fund I" for the widget "nope"
    Then the page should show no dashboard widgets
