# Worked examples (H1, H2, H17, H18, E1-E4, E6, E7): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
@rack_test
Feature: The company page and its menu follow the widgets that are switched on
  Default widgets appear only when no widget is enabled. Otherwise the page shows the enabled widgets and the menu
  lists only those with Show Menu ticked; with none ticked there is no menu row at all.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Flipkart Unlisted;category=Portfolio Company"

  # H1 — Happy path: menu lists only the Show Menu widgets, in position order
  Scenario: Menu lists only Show Menu widgets in order
    Given the company dashboard has widgets:
      | widget                | position | tags          | show_menu |
      | Kpis                  | 1        | Kpis          | yes       |
      | Portfolio Investments | 2        | Portfolio Inv | yes       |
      | Documents             | 3        | Docs          | no        |
    When I open the company page
    Then the page should show the widgets "Kpis, Portfolio Investments, Documents"
    And the menu should list "Kpis, Portfolio Inv"

  # H2 — Happy path: a menu link leads to its widget
  Scenario: Menu link reaches its widget
    Given the company dashboard has widgets:
      | widget                | position | tags          | show_menu |
      | Kpis                  | 1        | Kpis          | yes       |
      | Portfolio Investments | 2        | Portfolio Inv | yes       |
    When I open the company page
    And I click the menu link "Kpis"
    Then the menu link "Kpis" should lead to its widget

  # H17 — Happy path: nothing configured, so the default widgets show and are listed in the menu
  Scenario: No widget is configured
    When I open the company page
    Then the page should show the default widgets
    And the menu should list the default widgets

  # H18 — Happy path: widgets enabled but none has Show Menu, so the widgets show and there is no menu row
  Scenario: Enabled widgets but none has Show Menu
    Given the company dashboard has widgets:
      | widget                | position | tags          | show_menu |
      | Kpis                  | 1        | Kpis          | no        |
      | Portfolio Investments | 2        | Portfolio Inv | no        |
    When I open the company page
    Then the page should show the widgets "Kpis, Portfolio Investments"
    And no menu row should be shown

  # E1 — Edge case: every configured widget is disabled, so the defaults apply
  Scenario: Every configured widget is disabled
    Given the company dashboard has widgets:
      | widget                | position | tags          | enabled |
      | Kpis                  | 1        | Kpis          | no      |
      | Portfolio Investments | 2        | Portfolio Inv | no      |
      | Documents             | 3        | Docs          | no      |
    When I open the company page
    Then the page should show the default widgets
    And the menu should list the default widgets

  # E2 — Edge case: the original bug, one enabled widget with Show Menu off
  Scenario: A single enabled widget with Show Menu unticked
    Given the company dashboard has widgets:
      | widget | position | tags | show_menu |
      | Kpis   | 1        | Kpis | no        |
    When I open the company page
    Then the page should show the widgets "Kpis"
    And no menu row should be shown

  # E3 — Edge case: a disabled widget with Show Menu ticked appears nowhere
  Scenario: A disabled widget with Show Menu ticked
    Given the company dashboard has widgets:
      | widget                | position | tags          | enabled | show_menu |
      | Kpis                  | 1        | Kpis          | yes     | yes       |
      | Portfolio Investments | 2        | Portfolio Inv | no      | yes       |
    When I open the company page
    Then the page should show the widgets "Kpis"
    And the menu should list "Kpis"

  # E4 — Edge case: no Show Menu widget, so Reports and the layout selector go with the menu row (accepted)
  Scenario: Menu row hides Reports and layout selector too
    Given the company dashboard has widgets:
      | widget | position | tags | show_menu | layout  |
      | Kpis   | 1        | Kpis | no        | Default |
      | Kpis   | 1        | Kpis | no        | Second  |
    And the portfolio company has a report tagged for its dashboard
    And the portfolio company has a logo
    When I open the company page
    Then no menu row should be shown
    And the menu should have no Reports drop-down and no layout selector
    And the logo heading with "Flipkart Unlisted" should still show

  # E7 — Edge case: enabled widgets all hidden by tags give an empty page, not the defaults
  Scenario: Enabled widgets all hidden by tags
    Given the company "Flipkart Unlisted" is tagged "AI"
    And the company dashboard has widgets:
      | widget | position | tags | tag_list |
      | Kpis   | 1        | Kpis | Ecom     |
    When I open the company page
    Then the page should show no widgets
    And no menu row should be shown

  # E6 — Edge case: the LP company page follows the same rule
  Scenario: LP company page with no Show Menu widget
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund has the LP allocation formulas
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
    And Show Menu is off for every widget of the LP layout "LP"
    And the company "Acme Robotics" is shown to LPs
    When LP "Ravi Menon" opens the company "Acme Robotics"
    Then the LP company page should show the widgets "Data Card, Valuations"
    And the LP company page should have no menu row
