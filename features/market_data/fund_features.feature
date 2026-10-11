Feature: Fund features and Market Data settings
  Market-data features are switched on for the entity by CapHive support and chosen per fund in one
  Features section, which also holds the fund's existing investor-visibility and reporting switches.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H1–H3, E1–E10, X1–X5)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Horizon Evergreen Fund;currency=INR" for the entity

  # H1 — Happy path: once CapHive support switches on the three market-data features, the company admin finds Market Data in the Company menu and sees the card
  Scenario: Support switches on the entity features
    Given the entity has market data features "enable_market_rates,enable_market_prices,enable_derivatives"
    Then the entity should have the features "enable_market_rates,enable_market_prices,enable_derivatives"
    And the Market Data settings are "available" to the user
    When I open the Market Data settings
    Then I should see the Market Data card

  # H2 — Happy path: the entity admin turns on the FX feed (ECB) and the price feed (NSE, BSE, AMFI) and saves
  Scenario: Admin sets feeds and defaults
    Given the entity has market data features "enable_market_rates,enable_market_prices"
    When I turn on the FX feed with "ecb" and the price feed with "nse,bse,amfi" and save
    Then I should see "Market Data settings saved."
    And the entity Market Data settings should have "fx_feed_enabled=true;fx_providers=ecb;price_feed_enabled=true;price_providers=nse,bse,amfi;pivot_currency=USD"

  # H3 — Happy path: fund staff tick the four market-data switches on Horizon; the change is audited and Manual is always accepted
  Scenario: Fund chooses its market-data features
    Given the entity has market data features "enable_market_rates,enable_market_prices,enable_derivatives"
    When I tick the fund features "accept_market_rates,accept_derived_rates,accept_market_prices,enable_derivatives" on the fund form and save
    Then the fund features should include "accept_market_rates,accept_derived_rates,accept_market_prices,enable_derivatives"
    And the fund audit trail should record the features change
    And the fund form should show Manual as always accepted

  # E1 — Edge case: an entity with no market-data feature sees no Market Data settings and no market-data fund switches
  Scenario: Entity with no market-data feature
    Then the Market Data settings are "not available" to the user
    And the fund form should "not show" the switch "accept_market_rates"
    And the fund form should "not show" the switch "accept_market_prices"
    And the fund form should "not show" the switch "enable_derivatives"

  # E2 — Edge case: without the Market FX rates entity feature the fund form has no "Accept market FX rates" switch
  Scenario: Switch hidden when the entity feature is off
    Given the entity has market data features "enable_market_prices"
    Then the fund form should "not show" the switch "accept_market_rates"
    And the fund form should "show" the switch "accept_market_prices"

  # E3 — Edge case: a fund created after the entity default is Manual + Market FX rates starts accepting market rates
  Scenario: New fund starts with entity defaults
    Given the entity has market data features "enable_market_rates"
    And the entity Market Data settings are "fund_defaults=accept_market_rates"
    When a fund is created in the entity
    Then the fund features should include "accept_market_rates,show_fund_units,enable_ai_commentary"

  # E4 — Edge case: the backfill copies the old boolean columns into the fund features unchanged
  Scenario: Values carried over
    Given the fund has the old switches "show_portfolios=true;show_fund_units=true;show_fund_ratios=false;show_valuations=false;enable_ai_commentary=true;editable_formulas=false" stored in columns
    When the fund features backfill runs
    Then the fund features should include "show_portfolios,show_fund_units,enable_ai_commentary"
    And the fund features should not include "show_fund_ratios,show_valuations,editable_formulas"

  # E5 — Edge case: investor access is unchanged — with "Show portfolio to LPs" off the investor is refused the portfolio (the "on" path stays covered by master_fund_portfolio_access.feature)
  Scenario: Investor access unchanged
    Given there is an existing portfolio company "name=AcmeCorp;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Common Stock;category=Unlisted;sub_category=Equity;sector=Tech"
    Given there is a fund "name=Master Growth Fund;show_portfolios=false" for the entity
    And the current fund is the master fund
    And there are "2" portfolio investments "quantity=200"
    And there is a fund "name=Feeder Fund I" for the entity
    And the current fund is a feeder of the master fund
    And there is an existing investor entity "entity_type=Family Office" with employee "first_name=Investor"
    And another user is "yes" investor access to the fund
    And the user has curr role "investor"
    And I log out
    And I am at the login page
    When I fill and submit the login page
    When I view the master fund's portfolio investments
    Then I should not see "AcmeCorp"

  # E6 — Edge case: a fund upload with "Show Fund Ratios To Lps"=Yes and "Show Fund Portfolios To Lps"=No sets the matching features
  Scenario: Fund upload keeps its columns
    When a fund is imported with "Show Fund Ratios To Lps=Yes;Show Fund Portfolios To Lps=No"
    Then the fund features should include "show_fund_ratios,show_fund_units,enable_ai_commentary"
    And the fund features should not include "show_portfolios"

  # E7 — Edge case: a blank fund limit uses the entity default
  Scenario: Blank limit uses entity default
    Given the entity has market data features "enable_market_rates"
    And the entity Market Data settings are "max_rate_age_days=3;max_price_age_days=5;price_move_threshold_pct=12"
    Then the effective fund limits should be "max_rate_age_days=3;max_price_age_days=5;price_move_threshold_pct=12"

  # E8 — Edge case: a fund that is not open-ended has no Limits group on its form
  Scenario: Limits hidden on a closed-ended fund
    Given the entity has market data features "enable_market_rates"
    Then the fund form should not show the Limits group

  # E9 — Edge case: changing the entity's new-fund defaults leaves existing funds unchanged; only new funds pick them up
  Scenario: Changing defaults leaves existing funds alone
    Given the entity has market data features "enable_market_rates"
    And the entity Market Data settings are "fund_defaults=accept_market_rates"
    Then the fund features should not include "accept_market_rates"
    When a fund is created in the entity
    Then the fund features should include "accept_market_rates"

  # E10 — Edge case: when support switches the entity feature off, the fund keeps its bit but no longer uses market rates; switching it back on restores the choice
  Scenario: Entity feature switched off later
    Given the entity has market data features "enable_market_rates"
    When I tick the fund features "accept_market_rates" on the fund form and save
    Then the fund should "use" the feature "accept_market_rates"
    When support turns off the entity feature "enable_market_rates"
    Then the fund should "not use" the feature "accept_market_rates"
    And the fund features should include "accept_market_rates"
    Given the entity has market data features "enable_market_rates"
    Then the fund should "use" the feature "accept_market_rates"

  # X1 — Error case: a company admin who is not CapHive support cannot change the entity features
  Scenario: Non-support user cannot switch entity features
    When a non-support company user opens the admin entity form
    Then the entity features change is refused

  # X2 — Error case: the price feed switched on with no provider ticked is refused
  Scenario: Feed on with no provider
    Given the entity has market data features "enable_market_prices"
    When I turn on the price feed with no provider and save
    Then I should see "Choose at least one provider"

  # X3 — Error case: a direct submission of "Accept market prices" while the entity lacks Market prices is refused
  Scenario: Direct submission of an unavailable switch
    When the fund features "accept_market_prices" are submitted directly
    Then the submission should be refused and the fund features unchanged

  # X4 — Error case: a maximum rate age of 31 is refused
  Scenario: Out-of-range age
    Given the entity has market data features "enable_market_rates"
    When I set the entity limit "max_rate_age_days" to "31" and save
    Then I should see "must be between 0 and 30"

  # X5 — Error case: a price-move threshold of 0 is refused
  Scenario: Out-of-range threshold
    Given the entity has market data features "enable_market_rates"
    When I set the entity limit "price_move_threshold_pct" to "0" and save
    Then I should see "must be between 1 and 100"
