Feature: FX rate sources per fund
  Each fund converts with the rate sources it accepts (manual always; market and derived when chosen;
  its own rates when it uses fund-specific rates). Gains split into price and currency effect.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H5, H9, H21, E16–E33, E68–E72, X8–X10, X33, X34)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given these funds exist with rate sources:
      | fund                   | currency | sources                |
      | Growth AIF II          | INR      | manual                 |
      | Bridge Hybrid Fund     | INR      | manual,derived         |
      | Horizon Evergreen Fund | INR      | manual,market,derived  |
    Given these exchange rates exist:
      | from | to  | rate   | as_of       | source | provider |
      | USD  | INR | 83.00  | 01 Apr 2026 | manual | User     |
      | USD  | INR | 85.00  | 30 Oct 2026 | market | ECB via EUR     |
      | EUR  | USD | 1.07   | 30 Sep 2026 | manual | User     |
      | EUR  | USD | 1.08   | 30 Oct 2026 | market | ECB      |
      | INR  | GBP | 0.0095 | 30 Oct 2026 | manual | User     |

  # H5 — Happy path: Growth AIF II (manual only) values Nimbus at 83.00, Horizon (accepts market) at 85.00 on the same day
  Scenario: Two funds value the same holding with different rates
    Given "Growth AIF II" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Horizon Evergreen Fund" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Nimbus Inc" has a valuation of "120" per share on "30 Oct 2026"
    Then the fair value of "Nimbus Inc" in "Growth AIF II" on "30 Oct 2026" should be "9960000"
    And the fair value of "Nimbus Inc" in "Horizon Evergreen Fund" on "30 Oct 2026" should be "10200000"

  # H9 — Happy path: Horizon's Nimbus gain ₹19,00,000 splits into price effect ₹17,00,000 and currency effect ₹2,00,000
  # (dated 10 Oct 2026 so today's figures use them — holdings are computed as of today)
  Scenario: Unrealised gain split
    Given these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider |
      | USD  | INR | 85.00 | 10 Oct 2026 | market | ECB via EUR     |
    And "Horizon Evergreen Fund" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Nimbus Inc" has a valuation of "120" per share on "10 Oct 2026"
    When the holdings of "Horizon Evergreen Fund" are recomputed
    Then the "Nimbus Inc" holding in "Horizon Evergreen Fund" should show gain "1900000" = price effect "1700000" + currency effect "200000"

  # H21 — Happy path: Horizon's own USD→INR 84.50 is used by Horizon only; Bridge and Growth AIF II keep 83.00
  Scenario: Fund-specific rate used only by its fund
    Given these funds exist with rate sources:
      | fund        | currency | sources    |
      | Own Rate LP | INR      | manual,own |
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider | fund        |
      | USD  | INR | 84.50 | 30 Oct 2026 | manual | User     | Own Rate LP |
    When "Own Rate LP" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "84.5" "Manual · User"
    When "Growth AIF II" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "83.0" "Manual · User"
    When "Bridge Hybrid Fund" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "83.0" "Manual · User"
    And an entity-level "USD→INR" conversion on "30 Oct 2026" should use "83.0"

  # E16 — Edge case: rates entered without a source are Manual; fair values are as before
  Scenario: Existing rates become Manual
    Given these exchange rates exist:
      | from | to  | rate  | as_of       |
      | JPY  | INR | 0.56  | 01 Jan 2026 |
    Then the exchange rates dated before "01 Apr 2026" should all be Manual

  # E17 — Edge case: a Manual and a Market USD→INR rate for the same date are both stored
  Scenario: Manual and Market rate on the same date
    When a manual "USD→INR" rate of "84.80" is added for "30 Oct 2026"
    Then the entity should list 2 "Manual and Market" rates for "USD→INR" on "30 Oct 2026"

  # E18 — Edge case: on the same date Manual 84.80 beats Market 85.00 for a fund accepting market rates
  Scenario: Manual wins on the same date
    When a manual "USD→INR" rate of "84.80" is added for "30 Oct 2026"
    And "Horizon Evergreen Fund" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "84.8" "Manual · User"

  # E19 — Edge case: a Market rate dated 30 Oct beats a Manual rate dated 26 Oct for a fund accepting market rates
  Scenario: Newer market rate beats older manual rate
    When a manual "USD→INR" rate of "84.10" is added for "26 Oct 2026"
    And "Horizon Evergreen Fund" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "85.0" "Market · ECB via EUR"

  # E20 — Edge case: the manual-only fund ignores the newer Market rate and uses the 1 Apr Manual 83.00
  Scenario: Manual-only fund ignores newer market rate
    When "Growth AIF II" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "83.0" "Manual · User"
    And the rate used should be dated "01 Apr 2026"

  # E21 — Edge case: Bridge builds EUR→INR = 1.07 × 83.00 = 88.81 from its two manual legs, dated by the older leg
  Scenario: Cross rate from manual legs
    When "Bridge Hybrid Fund" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "88.81" "Derived · via USD"
    And the rate used should be dated "01 Apr 2026"
    And a derived rate "EUR→INR" should be stored as "via USD"

  # E22 — Edge case: GBP→INR is the reverse of the manual INR→GBP 0.0095
  Scenario: Reverse rate
    When "Bridge Hybrid Fund" resolves "GBP→INR" on "30 Oct 2026"
    Then the rate used should be "105.26315789" "Derived · reverse"

  # E23 — Edge case: Horizon's cross 1.08 × 85.00 = 91.80 (30 Oct) beats a direct manual EUR→INR 90.00 dated 1 Jan
  Scenario: Newer derived beats older direct
    Given these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider |
      | EUR  | INR | 90.00 | 01 Jan 2026 | manual | User     |
    When "Horizon Evergreen Fund" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "91.8" "Derived · via USD"

  # E24 — Edge case: after a manual USD→INR 84.80 replaces the 30 Oct leg, the stored cross is rebuilt as 1.08 × 84.80 = 91.584
  Scenario: Leg corrected
    When "Horizon Evergreen Fund" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "91.8" "Derived · via USD"
    When a manual "USD→INR" rate of "84.80" is added for "30 Oct 2026"
    And "Horizon Evergreen Fund" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "91.584" "Derived · via USD"

  # E25 — Edge case: storing a derived rate starts no portfolio recompute and no commitment adjustment
  Scenario: Derived rate starts no jobs
    Then storing a derived rate should start no jobs

  # E26 — Edge case: same currency uses rate 1 and makes no lookup
  Scenario: Same currency
    Then a same-currency conversion should use rate 1 without a lookup

  # E27 — Edge case: an entity-level conversion (e.g. a portfolio-company KPI) uses the entity defaults — Manual only here
  Scenario: Entity-level conversion uses entity defaults
    Then an entity-level "USD→INR" conversion on "30 Oct 2026" should use "83.0"

  # E28 — Edge case: the allocation engine's SQLite copy of a fund resolves with the same policy as the live fund
  Scenario: Allocation run resolves the same rate
    Then the allocation copy should resolve "USD→INR" for "Horizon Evergreen Fund" on "30 Oct 2026" like the live screens
    And the allocation copy should resolve "EUR→INR" for "Horizon Evergreen Fund" on "30 Oct 2026" like the live screens

  # E29 — Edge case: a Market rate recomputes Horizon's holdings but not Growth AIF II's
  Scenario: Market rate recomputes only accepting funds
    Given "Growth AIF II" holds 10 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Horizon Evergreen Fund" holds 10 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    When a market "USD→INR" rate of "85.20" arrives for "31 Oct 2026" while tracking recomputes
    Then holdings of "Horizon Evergreen Fund" should be recomputed and holdings of "Growth AIF II" should not

  # E30 — Edge case: with the commitment adjustment option on, a fed Market rate starts no commitment adjustment
  Scenario: Fed rate creates no commitment adjustment
    Given the entity uses the exchange-rate commitment adjustment option
    Then a market "USD→INR" rate arriving for "02 Nov 2026" should not start a commitment adjustment

  # E31 — Edge case: turning on Accept market FX rates recomputes Growth AIF II's fair value at 85.00; booked cost stays at 83.00
  Scenario: Changing accepted sources
    Given "Growth AIF II" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Nimbus Inc" has a valuation of "120" per share on "30 Oct 2026"
    When fund staff turn on "accept_market_rates" for "Growth AIF II"
    Then the booked cost of every holding in "Growth AIF II" should be unchanged
    And the fair value of "Nimbus Inc" in "Growth AIF II" on "30 Oct 2026" should be "10200000"

  # E32 — Edge case: 7 shares bought at $13.37 (83.1234), valued at $14.11 (84.0567) — price and currency effect add up exactly after rounding
  Scenario: Split adds up after rounding
    Given these exchange rates exist:
      | from | to  | rate    | as_of       | source | provider |
      | USD  | INR | 83.1234 | 02 Apr 2026 | manual | User     |
      | USD  | INR | 84.0567 | 10 Oct 2026 | market | ECB via EUR     |
    And "Horizon Evergreen Fund" holds 7 "Odd Lot Inc" (USD) bought at "13.37" each on "02 Apr 2026"
    And "Odd Lot Inc" has a valuation of "14.11" per share on "10 Oct 2026"
    When the holdings of "Horizon Evergreen Fund" are recomputed
    Then the "Odd Lot Inc" holding in "Horizon Evergreen Fund" gain split should add up exactly

  # E33 — Edge case: Horizon sells 400 Nimbus at $125 at 85.50; realised ₹9,55,000 = price ₹8,55,000 + currency ₹1,00,000
  Scenario: Realised split on a sale
    Given these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider |
      | USD  | INR | 85.50 | 05 Nov 2026 | market | ECB via EUR     |
    And "Horizon Evergreen Fund" holds 1000 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    When "Horizon Evergreen Fund" sells 400 "Nimbus Inc" at "125" each on "05 Nov 2026"
    Then the sale should show realised gain "955000" = price effect "855000" + currency effect "100000"

  # E68 — Edge case: Horizon-style own rate 84.50 beats an entity Manual 84.80 on the same date
  Scenario: Fund rate beats entity rate on the same date
    Given these funds exist with rate sources:
      | fund        | currency | sources           |
      | Own Rate LP | INR      | manual,market,own |
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider | fund        |
      | USD  | INR | 84.50 | 30 Oct 2026 | manual | User     | Own Rate LP |
      | USD  | INR | 84.80 | 30 Oct 2026 | manual | User     |             |
    When "Own Rate LP" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "84.5" "Manual · User"

  # E69 — Edge case: an own rate dated 26 Oct loses to the entity Market 85.00 dated 30 Oct
  Scenario: Newer entity rate beats older fund rate
    Given these funds exist with rate sources:
      | fund        | currency | sources           |
      | Own Rate LP | INR      | manual,market,own |
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider | fund        |
      | USD  | INR | 84.50 | 26 Oct 2026 | manual | User     | Own Rate LP |
    When "Own Rate LP" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "85.0" "Market · ECB via EUR"

  # E70 — Edge case: with "Use fund-specific FX rates" off, the fund's own 84.50 is kept but not used
  Scenario: Own rates ignored when the feature is off
    Given these funds exist with rate sources:
      | fund        | currency | sources           |
      | Own Rate LP | INR      | manual,market,own |
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider | fund        |
      | USD  | INR | 84.50 | 30 Oct 2026 | manual | User     | Own Rate LP |
    When fund staff turn off "use_own_fx_rates" for "Own Rate LP"
    And "Own Rate LP" resolves "USD→INR" on "30 Oct 2026"
    Then the rate used should be "85.0" "Market · ECB via EUR"
    And the entity should list 2 "own and entity" rates for "USD→INR" on "30 Oct 2026"

  # E71 — Edge case: EUR→INR for Horizon-style fund = 1.08 (Market) × its own 84.50 = 91.26, stored as Derived via USD owned by the fund
  Scenario: Derived rate from a fund's own leg
    Given these funds exist with rate sources:
      | fund        | currency | sources                   |
      | Own Rate LP | INR      | manual,market,derived,own |
    And these exchange rates exist:
      | from | to  | rate  | as_of       | source | provider | fund        |
      | USD  | INR | 84.50 | 30 Oct 2026 | manual | User     | Own Rate LP |
    When "Own Rate LP" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "91.26" "Derived · via USD"
    And the derived rate should belong to "Own Rate LP"
    When "Horizon Evergreen Fund" resolves "EUR→INR" on "30 Oct 2026"
    Then the rate used should be "91.8" "Derived · via USD"

  # E72 — Edge case: a fund's own Manual rate recomputes and adjusts only that fund
  Scenario: Own rate affects only its fund
    Given these funds exist with rate sources:
      | fund        | currency | sources    |
      | Own Rate LP | INR      | manual,own |
    And the entity uses the exchange-rate commitment adjustment option
    And "Own Rate LP" holds 10 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    And "Growth AIF II" holds 10 "Nimbus Inc" (USD) bought at "100" each on "01 Apr 2026"
    When a manual "USD→INR" rate of "84.40" for "Own Rate LP" arrives for "31 Oct 2026" while tracking recomputes
    Then holdings of "Own Rate LP" should be recomputed and holdings of "Growth AIF II" should not
    And a manual "USD→INR" rate for "Own Rate LP" arriving on "01 Nov 2026" should start a commitment adjustment

  # X8 — Error case: a second Manual USD→INR rate for 1 Apr is refused as a duplicate
  Scenario: Duplicate manual rate
    When a second manual "USD→INR" rate is added for "01 Apr 2026"
    Then it should be refused as a duplicate

  # X9 — Error case: Growth AIF II (manual only) books a EUR holding with no manual EUR→INR rate — refused, naming its sources
  Scenario: No accepted rate
    Given "Growth AIF II" holds 100 "Rhein AG" (EUR) bought at "50" each on "30 Oct 2026"
    Then saving the holding should be refused with the missing-rate message for "EUR→INR" on "30 Oct 2026" and sources "Manual"

  # X10 — Error case: Bridge (manual + derived) can't build EUR→INR when EUR→USD exists only as Market
  Scenario: Legs limited to accepted sources
    Given these funds exist with rate sources:
      | fund           | currency | sources        |
      | Bridge Only LP | INR      | manual,derived |
    And the manual "EUR→USD" rates are removed
    Given "Bridge Only LP" holds 100 "Rhein AG" (EUR) bought at "50" each on "30 Oct 2026"
    Then saving the holding should be refused with the missing-rate message for "EUR→INR" on "30 Oct 2026" and sources "Manual, Derived"

  # X33 — Error case: an upload row naming a fund without "Use fund-specific FX rates" is refused
  Scenario: Own rate for a fund without the feature
    When an exchange-rate upload row names the fund "Bridge Hybrid Fund"
    Then the upload row should be refused with "Fund Bridge Hybrid Fund does not use fund-specific FX rates"

  # X34 — Error case: an upload row naming another entity's fund is refused as not found
  Scenario: Own rate for another entity's fund
    Given another entity has a fund "Omar Growth Fund"
    When an exchange-rate upload row names the fund "Omar Growth Fund"
    Then the upload row should be refused with "Fund Omar Growth Fund not found"
