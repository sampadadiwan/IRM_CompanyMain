@javascript
Feature: AG Grid date columns follow the active locale
  Date cells in an AG Grid used to be rendered by moment's `format('L')` after
  setting moment's locale from navigator.language. The importmap pinned the bare
  moment build, which ships the `en` locale only, so `.locale('en-GB')` silently
  no-opped and every user — whatever their browser was set to — saw the `en`
  L format, MM/DD/YYYY. Rails-rendered dates on the same page meanwhile followed
  date.formats.default for the locale WithLocale resolved from Accept-Language,
  so the two disagreed.

  Grid cells now read the active locale's strftime pattern from the
  app-date-format meta tag (custom/locale_date_format.js), which keeps them in
  step with every server-rendered date.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=XYZ;currency=INR"
    Given there is a fund "name=Test fund;currency=INR" for the entity
    Given there are "1" portfolio investments "quantity=200;investment_date=2020-07-22"

  Scenario: A day-first browser sees the grid date day-first
    Given my browser sends an Accept-Language header of "en-GB"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    And the grid "investment_date" cell should read "22/07/2020"

  Scenario: A month-first browser sees the grid date month-first
    Given my browser sends an Accept-Language header of "en-US"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    And the grid "investment_date" cell should read "07/22/2020"

  Scenario: The grid date matches the date format the server published
    Given my browser sends an Accept-Language header of "en-GB"
    When I visit the Portfolio Investments AG Grid page
    Then the AG grid should boot and render rows
    And the page should publish the date format "%d/%m/%Y"
    And the grid "investment_date" cell should match the published date format
