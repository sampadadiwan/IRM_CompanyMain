# Worked examples H1, H2, H7, H8, E1, E2, E4, E5, E6, E9, X4, X5 — openspec/changes/archive/2026-11-07-dashboard-widget-inline-settings/design.md#worked-examples
# (X1–X3, X6, X7: features/security/dashboard_widget_inline_settings_isolation.feature; H3–H6, E3, E7, E8:
# features/core/dashboard_widget_inline_settings_refresh.feature)
Feature: Widget settings in place
  Every widget on a fund-manager dashboard has a settings icon that opens its settings in a panel, with the same
  fields as the widget edit page plus its size. The first save on a dashboard showing its defaults keeps them all.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 90, due_days: 180, limit: 15}"

  # H1 — Happy path: every widget on the Portfolio tab has the icon; pointing at a widget shows it
  Scenario: Every widget has a settings icon
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then every widget on the page should have a settings icon
    When I point at the "Valuation Freshness" widget
    Then the settings icon of the "Valuation Freshness" widget should be visible

  # H2 — Happy path: the panel shows the saved settings (90, 180, 15), the size and the shared-settings note
  Scenario: The panel shows the widget's current settings
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    Then the settings popup should be titled "Valuation Freshness settings"
    And the settings popup should show "Current up to (days)" as "90"
    And the settings popup should show "Due up to (days)" as "180"
    And the settings popup should show "Rows to show" as "15"
    And the settings popup should show "Size" as "XL"
    And the settings popup should say "Shared with everyone in your firm on the Default layout"

  # H7 — Happy path: Fund Stats draws its own card and still gets the icon
  Scenario: A widget that draws its own card has the icon
    Given the "Fund Stats" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    And I open the settings of the "Fund Stats" widget
    Then the settings popup should be titled "Fund Stats settings"

  # H8 — Happy path: FMV % has no settings of its own — the panel offers Size only
  Scenario: A widget without settings offers its size only
    Given the "FMV %" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "FMV %" widget
    Then the settings popup should say "This widget has no settings of its own."
    And the settings popup should show "Size" as "XL"

  # E1 — Edge case: Cancel closes the panel and saves nothing
  Scenario: Cancel changes nothing
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "5" in the settings popup
    And I click "Cancel" in the settings popup
    Then the settings popup should be closed
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 15}"

  # E2 — Edge case: the close button, and Esc, save nothing either
  Scenario: Closing the panel changes nothing
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "5" in the settings popup
    And I close the settings popup
    Then the settings popup should be closed
    When I open the settings of the "Valuation Freshness" widget
    And I press Escape
    Then the settings popup should be closed
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 15}"

  # E9 — Edge case: a saved setting the widget does not list (legacy_key) survives a save from the panel
  Scenario: A saved setting outside the widget's list is kept
    Given the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 90, due_days: 180, limit: 15, legacy_key: 'x'}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    And I open the settings of the "Valuation Freshness" widget
    And I set "Rows to show" to "5" in the settings popup
    And I click "Save" in the settings popup
    Then the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 5, legacy_key: 'x'}"

  # E4 — Edge case: the home page shows the first 4 defaults; the first save saves exactly those 4
  @rack_test
  Scenario: The home page saves only the widgets it shows
    When I save the settings "" with size "XL" for the default "Funds" widget on the "FM Landing Page"
    Then the "FM Landing Page" should have 4 saved widgets: "FM Menus, FM Stats, Funds, Investment Opportunities"
    And the saved size of the "Funds" widget on the "FM Landing Page" should be "XL"

  # E5 — Edge case: once the defaults are saved, a later save adds no rows
  @rack_test
  Scenario: A second save adds no widgets
    When I save the settings "" with size "Large" for the default "My Tasks" widget on the "Ops Dashboard"
    And I save the settings "" with size "Small" for the "My Tasks" widget on the "Ops Dashboard"
    Then the "Ops Dashboard" should have its default widgets saved once, in order
    And the saved size of the "My Tasks" widget on the "Ops Dashboard" should be "Small"

  # E6 — Edge case: two first saves (opened before either was saved) write the defaults once, and keep both changes
  @rack_test
  Scenario: Two first saves write the defaults once
    When I save the settings "" with size "Large" for the default "My Tasks" widget on the "Ops Dashboard"
    And I save the settings "" with size "Small" for the default "Notes" widget on the "Ops Dashboard"
    Then the "Ops Dashboard" should have its default widgets saved once, in order
    And the saved size of the "My Tasks" widget on the "Ops Dashboard" should be "Large"
    And the saved size of the "Notes" widget on the "Ops Dashboard" should be "Small"

  # X4 — Error case: settings that are code, not plain values, are refused and nothing changes
  @rack_test
  Scenario: Code in the settings is refused
    When I save the settings "{limit: exit}" with size "XL" for the "Valuation Freshness" widget on the "Portfolio Dashboard"
    Then the settings save should be refused with "Calculations and code are not allowed"
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 15}"

  # X5 — Error case: a size the form does not offer is refused
  @rack_test
  Scenario: An unknown size is refused
    When I save the settings "{limit: 5}" with size "Huge" for the "Valuation Freshness" widget on the "Portfolio Dashboard"
    Then the settings save should be refused with "Size is not one of XL, Large, Medium, Small, XS"
    And the saved size of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "XL"
    And the saved settings of the "Valuation Freshness" widget on the "Portfolio Dashboard" should be "{current_days: 90, due_days: 180, limit: 15}"
