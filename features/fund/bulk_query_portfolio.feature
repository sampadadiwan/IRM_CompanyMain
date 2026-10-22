# bulk-path-query-optimisation, phase 6 — portfolio re-valuation reads sold/transferred quantities per batch;
# an investment import saves each aggregate once at the end (D4).
# Phase 8 — a past-date aggregate valuation reads every buy's quantities in grouped queries.
# Worked examples: openspec/changes/bulk-path-query-optimisation/business-rules.md (H6, E9, E10, H10, E13)

@bulk_query @rack_test
Feature: Portfolio re-valuation reads quantities per batch
  Re-valuing a fund's investments used to sum each one's sold and transferred quantities separately, and an
  investment import re-saved the aggregate after every row before saving all aggregates again at the end.
  Values must not change.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Gamma Firm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Gamma Fund;currency=INR" for the entity
    And there is an existing portfolio company "investor_name=Acme"
    And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech;currency=INR"

  # H6 — Happy path: 3 buys of 200 and 2 sells of 100 (attributed to the buys); re-valuing keeps every
  # quantity and reads them in grouped queries, not a SUM per investment
  Scenario: H6 Re-valuing keeps every quantity without per-investment sums
    Given there are "3" portfolio investments "quantity=200"
    And there are "2" portfolio investments "quantity=-100"
    And I note each portfolio investment's quantities
    And I count queries by call site
    When the fund fair value recompute job runs
    Then each portfolio investment's quantities should be unchanged
    And at most 0 queries came from "PortfolioComputations#set_buy_quantities"

  # E9 — Edge case: investments with no sales or conversions get 0 from the preload, as an empty SUM gives
  Scenario: E9 An investment with no sales or conversions reads zero
    Given there are "2" portfolio investments "quantity=200"
    When the fund fair value recompute job runs
    Then every bought portfolio investment should have sold and transferred quantity 0

  # E10 — Edge case (D4): an import re-saves each aggregate once at the end instead of after every row;
  # the aggregate's totals are the same
  Scenario: E10 An investment import gives the same aggregate totals
    Given I count queries by call site
    When I import portfolio investments
      | Fund       | Portfolio Company Name | Investment Date | Amount (Excluding Expenses) | Quantity | Instrument | Currency | Investment Domicile | Notes | Excused Folio Ids | Proforma |
      | Gamma Fund | Acme                   | <1 year ago>    | 100000                      | 100      | Stock      | INR      | Domestic            |       |                   | No       |
      | Gamma Fund | Acme                   | <1 year ago>    | 200000                      | 150      | Stock      | INR      | Domestic            |       |                   | No       |
      | Gamma Fund | Acme                   | <1 year ago>    | 300000                      | 250      | Stock      | INR      | Domestic            |       |                   | No       |
    Then the import has 3 processed and 0 failed row
    And an aggregate portfolio investment should be created
    # 36 without D4. The 18 left come from each new valuation re-valuing the investments
    # (Investor#valuation_updated -> PortfolioInvestmentUpdate), which still saves the aggregate
    And at most 18 queries came from "PortfolioInvestment#compute_avg_cost"

  # H10 — Happy path (phase 8): valuing the aggregate as of a past date reads every buy's quantities in grouped
  # queries; each buy's figures equal the same buy computed on its own
  Scenario: H10 A past-date valuation reads every holding's quantities in grouped queries
    Given Gamma holds 3 buys of 200 on "2025-01-01" and sells of 100 on "2025-03-01, 2025-04-01"
    And 20 units of the first buy were converted on "2025-02-01"
    And I count queries by call site
    When the aggregate is valued as of "2025-06-30"
    Then at most 0 queries came from "PortfolioComputations#set_buy_quantities"
    And at most 0 queries came from "PortfolioComputations#net_quantity_on"
    And each buy's as-of quantities and values should match the live calculation

  # E13 — Edge case (phase 8): a proforma sale before the date and a sale after it are both left out of
  # net_quantity_on, exactly as the live sum leaves them out
  Scenario: E13 A proforma sale and a later sale are left out as the live sum leaves them out
    Given Gamma holds 1 buys of 200 on "2025-01-01" and sells of 50 on "2025-03-01, 2025-09-01"
    And the earliest sale is proforma
    When the aggregate is valued as of "2025-06-30"
    Then each buy's as-of quantities and values should match the live calculation
    And the first buy's net quantity on that date should be 200
