@rack_test
Feature: The portfolio report shows the company's stake, first investment date, and IRR and MOIC in each fund
  Across all the company's funds, latest_pi is its latest investment, buy or sale (the stake custom
  field is read off it) and earliest_pi its first buy (for the investment date). Each fund's <fund>_data also carries
  the company's irr and moic in that fund, from the stored fund ratio runs: the latest run on or before the report's
  end date, Default scenario. Investments after the end date are left out.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And there is a fund "name=Alpha Fund" for the entity
    And there is a fund "name=Beta Fund" for the entity

  # H13 — Happy path: the latest buy across both funds gives the stake, the earliest gives the date
  Scenario: H13 Stake from the latest buy and date from the earliest across funds
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And a buy in fund "Beta Fund" dated "2025-09-01" with stake "12.5"
    And a buy in fund "Alpha Fund" dated "2025-01-10" with stake "10"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the latest portfolio investment should have stake "12.5"
    And the earliest portfolio investment should be dated "2024-03-15"

  # H14 — Happy path: each fund shows its own IRR and MOIC for the company
  Scenario: H14 IRR and MOIC for each fund
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And a buy in fund "Beta Fund" dated "2025-09-01" with stake "12"
    And the company has a fund ratio "name=IRR;value=14.5;end_date=2026-03-31" in fund "Alpha Fund"
    And the company has a fund ratio "name=MOIC;value=1.8;end_date=2026-03-31" in fund "Alpha Fund"
    And the company has a fund ratio "name=IRR;value=-3.2;end_date=2026-03-31" in fund "Beta Fund"
    And the company has a fund ratio "name=MOIC;value=0.9;end_date=2026-03-31" in fund "Beta Fund"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the data for fund "Alpha Fund" should have "irr" equal to "14.5"
    And the data for fund "Alpha Fund" should have "moic" equal to "1.8"
    And the data for fund "Beta Fund" should have "irr" equal to "-3.2"
    And the data for fund "Beta Fund" should have "moic" equal to "0.9"

  # E41 — Edge case: a fund whose ratios were never run
  Scenario: E41 Ratio not run
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And a buy in fund "Beta Fund" dated "2025-09-01" with stake "12"
    And the company has a fund ratio "name=IRR;value=14.5;end_date=2026-03-31" in fund "Alpha Fund"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the data for fund "Alpha Fund" should have "moic" equal to "N/A"
    And the data for fund "Beta Fund" should have "irr" equal to "N/A"

  # E42 — Edge case: the latest run on or before the end date wins; a later run is not used
  Scenario: E42 Ratio as of the end date
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And the company has a fund ratio "name=IRR;value=10;end_date=2025-12-31" in fund "Alpha Fund"
    And the company has a fund ratio "name=IRR;value=14.5;end_date=2026-06-30" in fund "Alpha Fund"
    And the company has a fund ratio "name=IRR;value=20;end_date=2026-09-30" in fund "Alpha Fund"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the data for fund "Alpha Fund" should have "irr" equal to "14.5"

  # E43 — Edge case: only the fund's Default-scenario ratio of the company is used
  Scenario: E43 Other scenarios and other owners ignored
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And the company has a fund ratio "name=IRR;value=14.5;end_date=2026-03-31" in fund "Alpha Fund"
    And the company has a fund ratio "name=IRR;value=99;end_date=2026-06-30;scenario=Bull Case" in fund "Alpha Fund"
    And the fund "Alpha Fund" has its own IRR ratio of 77 on "2026-06-30"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the data for fund "Alpha Fund" should have "irr" equal to "14.5"

  # E44 — Edge case: a sale after the last buy is the latest investment, the first date still comes from the first buy
  Scenario: E44 A later sale is the latest investment
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And a buy in fund "Alpha Fund" dated "2025-01-10" with stake "10"
    And a sale in fund "Alpha Fund" dated "2026-02-01"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the latest portfolio investment should be dated "2026-02-01"
    And the earliest portfolio investment should be dated "2024-03-15"

  # E45 — Edge case: investments after the end date are left out
  Scenario: E45 Investments after the end date
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake "8"
    And a buy in fund "Alpha Fund" dated "2026-09-01" with stake "15"
    When the portfolio report fund data is built up to "2026-06-30"
    Then the latest portfolio investment should have stake "8"

  # E46 — Edge case: the company has no investment yet, the fields are blank and nothing fails
  Scenario: E46 No investment
    When the portfolio report fund data is built up to "2026-06-30"
    Then the latest portfolio investment should have stake ""
    And the earliest portfolio investment should be dated ""

  # E47 — Edge case: a buy with no stake recorded
  Scenario: E47 Stake not recorded
    Given a buy in fund "Alpha Fund" dated "2024-03-15" with stake ""
    When the portfolio report fund data is built up to "2026-06-30"
    Then the latest portfolio investment should have stake ""
    And the earliest portfolio investment should be dated "2024-03-15"
