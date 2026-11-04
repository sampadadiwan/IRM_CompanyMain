# Worked examples (H4-H7, H13, E1-E7, E19-E21, X1, X3): openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples
Feature: Stats widgets honour their settings
  The company Portfolio Stats widget and the fund-level stats widgets (Portfolio Dashboard "Portfolio Stats",
  Fund Dashboard "Fund Portfolio Stats") pick, order and label their cards from the same settings. The company
  widget opens in its Default currency; fund-level widgets stay in the fund's currency.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company         | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics   | Series B CCPS | 2         | 25.00   | 40.00  |
      | Bluefin Health  | Series A CCPS | 1         | 20.00   | 22.00  |
      | Cedar Logistics | Series A CCPS | 1         | 15.00   | 18.00  |
      | Delta AI        | Seed CCPS     | 1         | 3.00    | 3.00   |
      | Fenix Mobility  | Seed CCPS     | 1         | 5.00    | 5.00   |
      | Fenix Mobility  | Series A CCPS | 1         | 8.00    | 8.00   |

  # H4 — Happy path: a renamed card label shows on the next load, with view caching on
  Scenario: Renamed label shows at once
    Given view caching is on
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', field_names: 'Buy'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "Buy"
    When the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', field_names: 'Invested'}"
    And I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "Invested"

  # H5 — Happy path: the fund widget shows the picked cards in order with their names; Sold + FMV = 0.00 + 96.00
  Scenario: Fund widget picks and names cards
    Given the "Portfolio Stats" widget on the "Portfolio Dashboard" has settings "{fields: 'FMV, Sold + FMV', field_names: 'Value, Total value'}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the stats cards should be labelled "Value, Total value"
    And the stats card "Value" should show "96.00"
    And the stats card "Total value" should show "96.00"

  # H6 — Happy path: Units and Decimals on the Fund Dashboard widget (FMV ₹96 Cr = ₹9,600 L)
  Scenario: Fund widget units and decimals
    Given the "Fund Portfolio Stats" widget on the "Fund Dashboard" has settings "{fields: 'FMV', force_units: 'Lakhs', decimals: 0}"
    When I open the "Fund Dashboard" of fund "Growth Fund I"
    Then the stats card "FMV" should show "9,600"
    And the stats card "FMV" should show 0 decimals

  # H7 — Happy path: two cards per row; the fifth card fills its row
  Scenario: Fund widget cards per row
    Given the "Portfolio Stats" widget on the "Portfolio Dashboard" has settings "{per_row: 2}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the stats card widths should be "50.0%, 50.0%, 50.0%, 50.0%, 100.0%"

  # H13 — Happy path: the company widget opens in its Default currency, and the drop-down starts on it
  Scenario: Default currency used
    Given the firm has exchange rates between "USD" and "INR"
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', currency: 'USD', show_currency_filter: true}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show "$"
    And the stats currency drop-down should have "USD" selected

  # E1 — Edge case: saved fields match their cards ignoring case
  Scenario: Lower-case fields match
    Given the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'fmv, sold amount'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "FMV, Sold Amount"

  # E2 — Edge case: cards without a name keep their own
  Scenario: Fewer names than cards
    Given the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount, Sold Amount, FMV', field_names: 'Buy'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "Buy, Sold Amount, FMV"

  # E3 — Edge case: a repeated field shows once; extra names are ignored
  Scenario: More names than cards and a duplicate field
    Given the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'FMV, fmv', field_names: 'Value, Extra'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "Value"

  # E4 — Edge case: a decimals change shows on the next load, with view caching on
  Scenario: Decimals change shows at once
    Given view caching is on
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', decimals: 2}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show 2 decimals
    When the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', decimals: 0}"
    And I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show 0 decimals

  # E5 — Edge case: the widget's cached cards never reach the fund's Portfolio Investments page
  Scenario: Widget and Portfolio Investments page do not share cards
    Given view caching is on
    And the "Portfolio Stats" widget on the "Portfolio Dashboard" has settings "{fields: 'FMV', field_names: 'Value'}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the stats cards should be labelled "Value"
    When I open the Portfolio Investments page of fund "Growth Fund I"
    Then the page stats cards should include "Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income"
    And the page stats cards should not include "Value"

  # E6 — Edge case: a fund widget with no settings shows the five cards it always did, in crores with 2 decimals
  Scenario: Fund widget with no settings is unchanged
    Given the "Portfolio Stats" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the stats cards should be labelled "Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income"
    And the stats card "FMV" should show "96.00 Cr"

  # E7 — Edge case: under Allocated an LP's Portfolio Dashboard still hides the stats widget, whatever its settings,
  #      and the folio totals on the Portfolio Investments page are unchanged (Acme 40 + Cedar 18 = ₹58 Cr)
  Scenario: LP folio totals are unaffected by widget settings
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company         | instrument    | amount | purchase |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 1.00   | 1        |
      | Allocated Portfolio Cost | Cedar Logistics | Series A CCPS | 1.50   | 1        |
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    And the "Portfolio Investments" widget on the "Portfolio Dashboard" has settings ""
    And the "Portfolio Stats" widget on the "Portfolio Dashboard" has settings "{fields: 'FMV', field_names: 'Value'}"
    When LP "Ravi Menon" opens the portfolio dashboard of "Growth Fund I"
    Then the LP portfolio dashboard should show only the holdings list
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP totals should show FMV "58" Cr for "Growth Fund I"

  # E19 — Edge case: a currency picked in the drop-down wins over the Default currency
  @javascript
  Scenario: Picked currency wins
    Given the firm has exchange rates between "USD" and "INR"
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', currency: 'USD', show_currency_filter: true}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show "$"
    When I pick "INR" in the stats currency drop-down
    Then the stats card "Bought Amount" should show "₹"

  # E21 — Edge case: the drop-down lists the firm's currencies, as the metadata editor does
  @javascript
  Scenario: Drop-down lists the firm's currencies
    Given the firm has exchange rates between "SGD" and "INR"
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', show_currency_filter: true}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats currency drop-down should list "INR, SGD, USD"
    When I pick "SGD" in the stats currency drop-down
    Then the stats card "Bought Amount" should show "S$"

  # E20 — Edge case: Tracking currency ON wins over the Default currency
  Scenario: Tracking currency wins over the default
    Given the firm has exchange rates between "USD" and "INR"
    And the firm's tracking currency is "USD"
    And the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', tracking_currency: true, currency: 'INR'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show "$"

  # X1 — Error case: saved fields that match no card show every default card instead of an empty widget
  Scenario: No field matches
    Given the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Total FMV'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats cards should be labelled "Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income, Sold + FMV"

  # X3 — Error case: a Default currency the firm has no rates for is ignored; the firm's currency is used, no error
  Scenario: Default currency without rates
    Given the "Portfolio Stats" widget on the "Portfolio Company Dashboard" has settings "{fields: 'Bought Amount', currency: 'SGD'}"
    When I open the company dashboard of "Acme Robotics"
    Then the stats card "Bought Amount" should show "₹"
    And I should not see "Error fetching portfolio company stats"
