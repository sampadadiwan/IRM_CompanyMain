@javascript
Feature: AG Grid date columns can be filtered by typing a date
  ag-Grid's stock date filter renders a bare <input type="date">. It cannot be typed
  into — it can only be driven by the browser's segmented entry or its calendar popup
  — and those segments follow the BROWSER's locale, not the app's. A user whose grid
  cells read 22/07/2020 was handed a filter expecting 07/22/2020, with no way to type
  either. That is the same silent locale disagreement the moment `en`-only build caused
  in the cells themselves (see ag_grid_date_locale.feature).

  custom/ag_locale_date_filter.js replaces it with the widget shape the Rails forms
  already use: a text input in the app's locale format plus a calendar icon for the
  native picker. base_ag_grid.js#dateFormatColumn gives it to every date column.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=XYZ;currency=INR"
    Given there is a fund "name=Test fund;currency=INR" for the entity
    Given there are "1" portfolio investments "quantity=200;investment_date=2020-07-22"
    Given there are "1" portfolio investments "quantity=300;investment_date=2021-03-05"

  Scenario: A date typed in the active locale's format filters the grid
    Given my browser sends an Accept-Language header of "en-GB"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    When I open the "investment_date" column filter
    And I type "22/07/2020" into the column filter
    Then the grid "investment_date" cell should read "22/07/2020"
    And the grid should have no "investment_date" cell reading "05/03/2021"

  Scenario: The filter reads the date in the app's locale, not ISO
    Given my browser sends an Accept-Language header of "en-US"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    When I open the "investment_date" column filter
    And I type "07/22/2020" into the column filter
    Then the grid "investment_date" cell should read "07/22/2020"
    And the grid should have no "investment_date" cell reading "03/05/2021"

  Scenario: A date typed with different separators is still understood
    Given my browser sends an Accept-Language header of "en-GB"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    When I open the "investment_date" column filter
    And I type "22-07-2020" into the column filter
    Then the grid "investment_date" cell should read "22/07/2020"
    And the grid should have no "investment_date" cell reading "05/03/2021"

  Scenario: An impossible date filters nothing rather than rolling over into the next month
    Given my browser sends an Accept-Language header of "en-GB"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    When I open the "investment_date" column filter
    And I type "31/02/2020" into the column filter
    # 31 February must not be read as 2 March and silently filter on a day nobody asked for
    Then the grid "investment_date" cell should read "22/07/2020"
    And the grid "investment_date" cell should read "05/03/2021"
    When I leave the column filter
    Then the column filter should be marked invalid
