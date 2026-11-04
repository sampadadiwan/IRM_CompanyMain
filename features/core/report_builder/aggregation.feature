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

  # ── DEFAULT AND ALLOWED TOTALS (report-builder-trust) ───────────────────
  # Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

  # H7 — Happy path: adding Committed from capital commitments saves Sum, and the column shows each investor's total
  @rack_test @report_builder
  Scenario: A related amount gets Sum saved when it is added
    Given the Acme report builder data
    And the Acme report "LPs"
    And I am signed in as Meera
    When I add the column "capital_commitments.committed_amount" to the report over HTTP
    Then the stored total for "capital_commitments.committed_amount" is "sum"
    When I run the report
    Then the row where "investor_name" is "Aditi Rao" shows "50000000" in "capital_commitments.committed_amount"
    And the row where "investor_name" is "Kiran Mehta" shows "25000000" in "capital_commitments.committed_amount"

  # E2 — Edge case: defaults by type — a date gets Latest date (max), yes/no gets Any yes (max), text gets Latest
  @rack_test @report_builder
  Scenario: Dates, yes/no and text get their own default totals
    Given the Acme report builder data
    And the Acme report "LPs"
    And I am signed in as Meera
    When I add the column "capital_commitments.commitment_date" to the report over HTTP
    And I add the column "capital_commitments.onboarding_completed" to the report over HTTP
    And I add the column "capital_commitments.unit_type" to the report over HTTP
    Then the stored total for "capital_commitments.commitment_date" is "max"
    And the stored total for "capital_commitments.onboarding_completed" is "max"
    And the stored total for "capital_commitments.unit_type" is "latest"

  # E28 — Edge case: text two steps away (an investor's funds via commitments) defaults to List, not Latest
  @rack_test @report_builder
  Scenario: Two-step text defaults to a list
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report has related data "capital_commitments.fund"
    And I am signed in as Meera
    When I add the column "capital_commitments.fund.name" to the report over HTTP
    Then the stored total for "capital_commitments.fund.name" is "list"

  # E3 — Edge case: a report saved before defaults existed (no total stored) still shows the summed values
  @rack_test @report_builder
  Scenario: A legacy related column without a stored total uses its type default
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    Then no total is stored for "capital_commitments.committed_amount"
    When I run the report
    Then the row where "investor_name" is "Aditi Rao" shows "50000000" in "capital_commitments.committed_amount"

  # X2 — Error case: a total outside the allowed list is refused (422) and the stored total is unchanged
  @rack_test @report_builder
  Scenario: An unknown total is refused
    Given the Acme report builder data
    And the Acme report "LPs"
    And the report also shows "capital_commitments.committed_amount"
    And the report stores the total "sum" for "capital_commitments.committed_amount"
    And I am signed in as Meera
    When I set the total for "capital_commitments.committed_amount" to "median" over HTTP
    Then the request is refused with status 422
    And the stored total for "capital_commitments.committed_amount" is "sum"

  # E4 — Edge case: "All yes" (minimum) of a yes/no reads No when any commitment isn't onboarded
  @rack_test @report_builder
  Scenario: The minimum of a yes/no column reads Yes or No
    Given the Acme report builder data
    And an "Investor" report with columns "investor_name,capital_commitments.onboarding_completed"
    And the report has related data "capital_commitments"
    And the report stores the total "min" for "capital_commitments.onboarding_completed"
    And I am signed in as Meera
    When I open the Report Builder page
    Then the table shows "No" under "Onboarding completed" in the row with "Aditi Rao"
    And the table shows "Yes" under "Onboarding completed" in the row with "Zeta Holdings"

  # E5 — Edge case: a Count of a yes/no column is a number, not Yes/No
  @rack_test @report_builder
  Scenario: A count of a yes/no column is a number
    Given the Acme report builder data
    And an "Investor" report with columns "investor_name,capital_commitments.onboarding_completed"
    And the report has related data "capital_commitments"
    And the report stores the total "count" for "capital_commitments.onboarding_completed"
    And I am signed in as Meera
    When I open the Report Builder page
    Then the table shows "2" under "Onboarding completed" in the row with "Aditi Rao"
