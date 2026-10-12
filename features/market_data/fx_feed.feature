Feature: FX rate feed
  The daily feed loads ECB reference rates for the currency pairs the entity uses and stores them as
  that entity's Market rates; missing data is emailed to Fund accounting once.
  Worked examples: openspec/changes/fund-market-data/business-rules.md (H4, E11–E15, E73, X6, X7)

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user is tagged "FundAccounting"
    And the FX feed is on with the ECB provider
    And the entity holds a "USD" instrument in an INR fund

  # H4 — Happy path: the feed for 30 Oct stores Market USD→INR 85.00 (ECB 93.50 ÷ 1.10), provider "ECB via EUR", Reference
  @sync-http
  Scenario: Feed loads rates
    When the FX feed runs for "30 Oct 2026"
    Then a Market "USD→INR" rate of "85.0" from "ECB via EUR" dated "30 Oct 2026" should exist
    And the "ecb" run for "30 Oct 2026" should be "ok"

  # E11 — Edge case: running the feed twice for 30 Oct keeps one Market row and one run row
  @sync-http
  Scenario: Re-run is idempotent
    When the FX feed runs for "30 Oct 2026"
    And the FX feed runs for "30 Oct 2026"
    Then there should be 1 Market "USD→INR" rate dated "30 Oct 2026"
    And the "ecb" run for "30 Oct 2026" should be "ok"

  # E12 — Edge case: adding a GBP holding makes the next run fetch GBP→INR
  @sync-http
  Scenario: New pair tracked
    Given the entity holds a "GBP" instrument in an INR fund
    Then the FX feed should track the pair "GBP→INR"
    When the FX feed runs for "30 Oct 2026"
    Then a Market "GBP→INR" rate of "110.0" from "ECB via EUR" dated "30 Oct 2026" should exist

  # E13 — Edge case: the feed due on a Saturday fetches nothing, records no run and sends no email
  @sync-http
  Scenario: Weekend skipped
    When the FX feed runs for "31 Oct 2026"
    Then no FX feed run should exist for "31 Oct 2026"
    And 0 feed emails with subject "FX feed: no rates loaded for Oct 31, 2026" should have been sent

  # E14 — Edge case: the ECB file has no AED; USD→INR is stored, the run is partial and the email lists only AED→INR
  @sync-http
  Scenario: Some pairs missing
    Given the entity holds a "AED" instrument in an INR fund
    When the FX feed runs for "30 Oct 2026"
    Then a Market "USD→INR" rate of "85.0" from "ECB via EUR" dated "30 Oct 2026" should exist
    And the "ecb" run for "30 Oct 2026" should be "partial"
    And the run for "30 Oct 2026" should list missing "AED→INR"
    And 1 feed email with subject "FX feed: no rates loaded for Oct 30, 2026" should have been sent

  # E15 — Edge case: an exchange-rate upload row without a Source column is stored as Manual, provider "Upload"
  Scenario: Upload without a Source column
    When an exchange-rate upload has a row without a Source column
    Then the uploaded rate should be Manual with provider "Upload"

  # E73 — Edge case: two entities on the ECB feed each store their own Market USD→INR; deleting one entity's row leaves the other's
  @sync-http
  Scenario: Market rates stay in their entity
    Given a second entity "Northwind Capital" also runs the ECB feed with an INR fund holding USD
    When the FX feed runs for "30 Oct 2026"
    And the market USD→INR row of the first entity is deleted
    Then the second entity should still have its own Market USD→INR rate for "30 Oct 2026"

  # X6 — Error case: the provider is down after retries; the run fails and Fund accounting is emailed once
  @sync-http
  Scenario: Provider down
    When the FX feed runs for "29 Oct 2026" while the provider is down
    And the FX feed runs for "29 Oct 2026" while the provider is down
    Then the "ecb" run for "29 Oct 2026" should be "failed"
    And 1 feed email with subject "FX feed: no rates loaded for Oct 29, 2026" should have been sent

  # X7 — Error case: a provider rate of zero (JPY) is not stored and is listed as missing
  @sync-http
  Scenario: Invalid rate from provider
    Given the entity holds a "JPY" instrument in an INR fund
    When the FX feed runs for "30 Oct 2026"
    Then there should be 0 Market "JPY→INR" rates dated "30 Oct 2026"
    And the run for "30 Oct 2026" should list missing "JPY→INR"
    And the "ecb" run for "30 Oct 2026" should be "partial"
