@portfolio_cashflow_xlsx_export
Feature: Portfolio Cashflow xlsx export is scoped to a single Aggregate Portfolio Investment
  Downloading cashflows from an Aggregate Portfolio Investment's "Income" tab must only export
  the cashflows belonging to that investment, not every cashflow the user can see across every
  fund/investment.

  Scenario: Downloading cashflows from an API's Income tab only exports that API's cashflows
    Given Im logged in as a user "" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    And there is a fund "name=Fund One" for the entity
    And there are "1" portfolio investments "quantity=100;category=Unlisted"
    And the last aggregate portfolio investment has cashflows "1000|2000"
    And there is a fund "name=Fund Two" for the entity
    And there are "1" portfolio investments "quantity=200;category=Unlisted"
    And the last aggregate portfolio investment has cashflows "5000|6000|7000"
    When I download the cashflows xlsx from the first aggregate portfolio investment's Income tab
    Then the exported xlsx should contain only the cashflow amounts "1000|2000"
