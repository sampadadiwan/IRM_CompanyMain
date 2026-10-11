Feature: Instruments and price sources
  Instruments carry identifiers and a pricing method; every price records its source, and each
  fund uses only the price sources it accepts. Purchases record a Cost price and never overwrite.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H6, H7, E34–E41, X11–X14, X35)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the price feed is on with providers "nse,bse,amfi"
    Given these funds exist with rate sources:
      | fund                   | currency | sources | prices        |
      | Growth AIF II          | INR      | manual  | manual        |
      | Bridge Hybrid Fund     | INR      | manual  | manual,market |
    And there is an INR instrument "ACMEIND"

  # H6 — Happy path: ACMEIND set to ticker ACMEIND on NSE with pricing method Market
  Scenario: Instrument set to Market
    When the instrument "ACMEIND" is set to "ticker=ACMEIND;exchange=NSE;pricing_method=market"
    Then the instrument should be saved as Market priced

  # H7 — Happy path: Bridge (accepts market prices) uses Market ₹1,250; Growth AIF II uses Manual ₹1,100
  Scenario: Two funds price the same holding differently
    Given "ACMEIND" has a manual price of "1100" on "30 Sep 2026"
    And "ACMEIND" has a market price of "1020" on "23 Oct 2026"
    And "ACMEIND" has a market price of "1250" on "30 Oct 2026"
    Then "Bridge Hybrid Fund" should use a price of "1250" per share for "ACMEIND" on "30 Oct 2026"
    And "Growth AIF II" should use a price of "1100" per share for "ACMEIND" on "30 Oct 2026"

  # E34 — Edge case: an existing instrument stays Manual and gets its ISIN copied from the SEBI field
  Scenario: Existing instruments become Manual
    Given the instrument "ACMEIND" has the SEBI ISIN "INE009A01021"
    When the ISIN backfill runs
    Then the instrument "ACMEIND" should have ISIN "INE009A01021" and pricing method "manual"

  # E35 — Edge case: switching to Market keeps the Manual valuation and adds Market ones
  Scenario: Switching to Market keeps history
    Given "ACMEIND" has a manual price of "1100" on "30 Sep 2026"
    When the instrument "ACMEIND" is set to "ticker=ACMEIND;exchange=NSE;pricing_method=market"
    And "ACMEIND" has a market price of "1250" on "30 Oct 2026"
    Then "ACMEIND" should have 2 valuations
    And "ACMEIND" should have a manual price of "1100" on "30 Sep 2026"

  # E36 — Edge case: a valuation created without a source is Manual
  Scenario: Existing valuations become Manual
    Then a valuation created without a source for "ACMEIND" should be Manual

  # E37 — Edge case: a valuation upload with Price Type "Mid" stores price type mid, source Manual
  Scenario: Valuation upload with Price Type
    When a valuation upload row for "ACMEIND" has Price Type "Mid"
    Then the uploaded valuation for "ACMEIND" should be Manual with price type "mid"

  # E38 — Edge case: Manual ₹1,240 beats Market ₹1,250 on the same date
  Scenario: Manual beats Market on the same date
    Given "ACMEIND" has a manual price of "1240" on "30 Oct 2026"
    And "ACMEIND" has a market price of "1250" on "30 Oct 2026"
    Then "Bridge Hybrid Fund" should use a price of "1240" per share for "ACMEIND" on "30 Oct 2026"
    And the price used should come from "manual"

  # E39 — Edge case: Bridge buys ACMEIND on 30 Oct at ₹1,230; the Market close ₹1,250 is used, not the Cost price
  Scenario: Market beats Cost on the same date
    Given "ACMEIND" has a market price of "1250" on "30 Oct 2026"
    And "Bridge Hybrid Fund" holds 10 "ACMEIND" (INR) bought at "1230" each on "30 Oct 2026"
    Then "Bridge Hybrid Fund" should use a price of "1250" per share for "ACMEIND" on "30 Oct 2026"
    And the price used should come from "market"

  # E40 — Edge case: the purchase leaves the Market ₹1,250 untouched and adds a Cost ₹1,230
  Scenario: Purchase on a day with a market close
    Given "ACMEIND" has a market price of "1250" on "30 Oct 2026"
    And "Bridge Hybrid Fund" holds 10 "ACMEIND" (INR) bought at "1230" each on "30 Oct 2026"
    Then "ACMEIND" should have a market price of "1250" on "30 Oct 2026"
    And "ACMEIND" should have a cost price of "1230" on "30 Oct 2026"

  # E41 — Edge case: a manual-only fund with no Manual valuation uses the purchase's Cost price
  Scenario: Manual-only fund uses Cost
    Given "Growth AIF II" holds 10 "ACMEIND" (INR) bought at "1230" each on "30 Oct 2026"
    Then "Growth AIF II" should use a price of "1230" per share for "ACMEIND" on "30 Oct 2026"
    And the price used should come from "cost"

  # X11 — Error case: an ISIN with a wrong check digit is refused
  Scenario: Invalid ISIN
    When the instrument "ACMEIND" is set to "isin=INE009A01022"
    Then the instrument should be refused with "ISIN is not valid"

  # X12 — Error case: Market pricing with no ticker, exchange or ISIN is refused
  Scenario: Market without identifiers
    When the instrument "ACMEIND" is set to "pricing_method=market"
    Then the instrument should be refused with "Market pricing needs a ticker and exchange, or an ISIN"

  # X13 — Error case: a ticker already used on the same exchange is refused
  Scenario: Duplicate ticker
    Given the instrument "ACMEIND" is set to "ticker=ACMEIND;exchange=NSE"
    And there is an INR instrument "ACME Copy"
    When the instrument "ACME Copy" is set to "ticker=ACMEIND;exchange=NSE"
    Then the instrument should be refused with "Ticker already used by ACMEIND"

  # X14 — Error case: a second Manual valuation for the same instrument and date is refused
  Scenario: Duplicate manual valuation
    Given "ACMEIND" has a manual price of "1100" on "30 Sep 2026"
    When a second manual valuation is added for "ACMEIND" on "30 Sep 2026"
    Then the valuation should be refused as a duplicate

  # X35 — Error case: Market pricing on NASDAQ, which no selected feed covers, is refused
  Scenario: Exchange not covered by a feed
    When the instrument "ACMEIND" is set to "ticker=NMBS;exchange=NASDAQ;pricing_method=market"
    Then the instrument should be refused with "No price feed covers NASDAQ; keep this holding Manual"
