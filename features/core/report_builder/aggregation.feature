Feature: ReportBuilderChildAggregator — all aggregate types

  Two investors are used: one with commitments (for positive tests),
  one without (for zero-fill tests). All tests call the aggregator directly.

  Background:
    Given a report builder entity and user
    And that entity has an investor "Aggregation Investor"

  # ── COUNT ────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: count returns the number of child records
    Given that investor has 3 capital commitments of 500000 paise each
    When I aggregate "id" on capital commitments for that investor using "count"
    Then the aggregation result for the investor and column "id" should be "3"

  Scenario: count returns 0 for an investor with no children when aggregated with another
    Given another investor "Empty Investor" with no commitments
    And that investor has 2 capital commitments of 500000 paise each
    When I aggregate "id" on capital commitments for both investors using "count"
    Then the investor with no commitments should not appear in the aggregation result

  # ── SUM ─────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: sum adds up monetized commitment amounts (paise → rupees)
    Given that investor has 2 capital commitments of 1000000 paise each
    When I aggregate "folio_committed_amount" on capital commitments for that investor using "sum"
    Then the aggregation result for the investor and column "folio_committed_amount" should be "20000.0"

  @rack_test
  Scenario: sum of a single commitment equals that commitment's amount
    Given that investor has a capital commitment of 3000000 paise
    When I aggregate "folio_committed_amount" on capital commitments for that investor using "sum"
    Then the aggregation result for the investor and column "folio_committed_amount" should be "30000.0"

  # ── AVG ─────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: avg returns the arithmetic mean of monetized amounts
    Given that investor has 2 capital commitments of 1000000 paise each
    When I aggregate "folio_committed_amount" on capital commitments for that investor using "avg"
    Then the aggregation result for the investor and column "folio_committed_amount" should be "10000.0"

  # ── MIN ─────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: min returns the smallest monetized amount
    Given that investor has 1 capital commitments of 500000 paise each
    And that investor has a capital commitment of 2000000 paise
    When I aggregate "folio_committed_amount" on capital commitments for that investor using "min"
    Then the aggregation result for the investor and column "folio_committed_amount" should be "5000.0"

  # ── MAX ─────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: max returns the largest monetized amount
    Given that investor has 1 capital commitments of 500000 paise each
    And that investor has a capital commitment of 2000000 paise
    When I aggregate "folio_committed_amount" on capital commitments for that investor using "max"
    Then the aggregation result for the investor and column "folio_committed_amount" should be "20000.0"

  # ── LIST ────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: list concatenates distinct fund_close values
    Given that investor has 2 capital commitments of 500000 paise each
    When I aggregate "fund_close" on capital commitments for that investor using "list"
    Then the aggregation result for the investor and column "fund_close" should be "First Close"

  # ── LATEST ──────────────────────────────────────────────────────────────

  @rack_test
  Scenario: latest returns a value from the most recent KYC record
    Given that investor has a KYC record
    When I aggregate "residency" on investor KYCs for that investor using "latest"
    Then the aggregation result for the investor and KYC column "residency" should be "domestic"

  # ── EMPTY result ─────────────────────────────────────────────────────────

  @rack_test
  Scenario: aggregator returns empty hash when root_ids is empty
    When I aggregate "id" on capital commitments with empty root ids
    Then the aggregation result should be empty
