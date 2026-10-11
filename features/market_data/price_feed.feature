Feature: Price feed and corporate actions
  The daily price feed stores closing prices of Market instruments as this entity's Market
  valuations, recomputes each holding once, and suggests corporate actions for confirmation.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H8, H10, E42–E47, X15)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the user is tagged "FundAccounting"
    And the price feed is on with providers "nse,amfi"
    And there is a Market instrument "ACMEIND" on "NSE" with ticker "ACMEIND"

  # H8 — Happy path: NSE reports ACMEIND at ₹1,250 for 30 Oct; a Market valuation ₹1,250, provider NSE, Close is stored
  @sync-http
  Scenario: Feed loads prices
    Given NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports no corporate actions
    When the price feed runs for "30 Oct 2026"
    Then the market price of "ACMEIND" on "30 Oct 2026" should be "1250" from "NSE"

  # H10 — Happy path: NSE reports a 10→5 face-value split for ACMEIND; it is suggested, emailed once, and confirming creates a 2× stock adjustment
  @sync-http
  Scenario: Split confirmed
    Given NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports these corporate actions:
      | ticker  | subject                                                                       | ex_date     |
      | ACMEIND | Face Value Split (Sub-Division) - From Rs 10/- Per Share To Rs 5/- Per Share | 06 Nov 2026 |
    When the price feed runs for "30 Oct 2026"
    Then there should be 1 pending corporate action suggestion for "ACMEIND"
    And 1 email should mention "Suggested corporate action: ACMEIND"
    When the suggestion for "ACMEIND" is confirmed by the user
    Then a stock adjustment of "2.0" should exist for "ACMEIND"
    And there should be 1 confirmed corporate action suggestion for "ACMEIND"

  # E42 — Edge case: a Market mutual fund with only an ISIN is priced from the AMFI NAV file
  @sync-http
  Scenario: Mutual fund matched by ISIN
    Given there is a Market mutual fund "Sample Liquid Fund" with ISIN "INF846K01EW2"
    And NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports no corporate actions
    And AMFI reports a NAV of "2789.1234" for ISIN "INF846K01EW2" on "30 Oct 2026"
    When the price feed runs for "30 Oct 2026"
    Then the market price of "Sample Liquid Fund" on "30 Oct 2026" should be "2789.1234" from "AMFI"

  # E43 — Edge case: prices for several instruments of one company recompute each holding once
  @sync-http
  Scenario: One recompute per holding per run
    Given there is another Market instrument "ACME Pref" of the same company on NSE with ticker "ACMEPREF"
    And these funds exist with rate sources:
      | fund        | currency | sources | prices        |
      | Listed Fund | INR      | manual  | manual,market |
    And "Listed Fund" holds 10 "ACMEIND" (INR) bought at "1000" each on "01 Apr 2026"
    And "Listed Fund" holds 10 "ACME Pref" (INR) bought at "500" each on "01 Apr 2026"
    And NSE reports these closes for "30 Oct 2026":
      | ticker   | close   |
      | ACMEIND  | 1250.00 |
      | ACMEPREF | 600.00  |
    And NSE reports no corporate actions
    When the price feed runs for "30 Oct 2026" while counting recomputes
    Then each holding should have been recomputed once

  # E44 — Edge case: running the price feed twice for 30 Oct keeps one Market valuation
  @sync-http
  Scenario: Re-run is idempotent
    Given NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports no corporate actions
    When the price feed runs for "30 Oct 2026"
    And the price feed runs for "30 Oct 2026"
    Then "ACMEIND" should have 1 market valuation on "30 Oct 2026"

  # E45 — Edge case: Test feed finds ACMEIND and Rangoli Textiles ("2 of 2 found") and stores nothing
  @sync-http
  Scenario: Test feed
    Given there is a Market instrument "Rangoli Textiles" on "NSE" with ticker "RANGOLI"
    And NSE reports these closes for the test-feed date:
      | ticker  | close   |
      | ACMEIND | 1250.00 |
      | RANGOLI | 88.50   |
    And I am at the login page
    When I fill and submit the login page
    And I click Test feed on the Market Data settings
    Then I should see "2 of 2 found"
    And "ACMEIND" should have no market valuations

  # E46 — Edge case: a dismissed dividend is not suggested again when a later run reports it
  @sync-http
  Scenario: Suggestion dismissed
    Given NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports these corporate actions:
      | ticker  | subject                      | ex_date     |
      | ACMEIND | Dividend - Rs 1.50 Per Share | 05 Nov 2026 |
    When the price feed runs for "30 Oct 2026"
    And the suggestion for "ACMEIND" is dismissed by the user
    And the price feed runs for "30 Oct 2026"
    Then there should be 1 dismissed corporate action suggestion for "ACMEIND"
    And there should be 0 pending corporate action suggestions for "ACMEIND"
    And no stock adjustment should exist for "ACMEIND"

  # E47 — Edge case: a pending split reported again creates no new suggestion and no new email
  @sync-http
  Scenario: Reported again
    Given NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports these corporate actions:
      | ticker  | subject   | ex_date     |
      | ACMEIND | Bonus 1:1 | 06 Nov 2026 |
    When the price feed runs for "30 Oct 2026"
    And the price feed runs for "30 Oct 2026"
    Then there should be 1 pending corporate action suggestion for "ACMEIND"
    And 1 email should mention "Suggested corporate action: ACMEIND"

  # X15 — Error case: NSE has no RANGOLI; ACMEIND is stored and the email names "Rangoli Textiles — ticker not found at NSE"
  @sync-http
  Scenario: Ticker not found
    Given there is a Market instrument "Rangoli Textiles" on "NSE" with ticker "RANGOLI"
    And NSE reports these closes for "30 Oct 2026":
      | ticker  | close   |
      | ACMEIND | 1250.00 |
    And NSE reports no corporate actions
    When the price feed runs for "30 Oct 2026"
    Then the market price of "ACMEIND" on "30 Oct 2026" should be "1250" from "NSE"
    And the "nse" price run for "30 Oct 2026" should list "Rangoli Textiles — ticker not found at NSE"
    And 1 email should mention "Rangoli Textiles — ticker not found at NSE"
