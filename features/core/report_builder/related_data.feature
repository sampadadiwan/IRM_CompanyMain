@rack_test @report_builder
Feature: Report Builder related data — parents, one-to-one, two-step and polymorphic

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  Related data that has at most one row per report row is read directly;
  data two steps away is anchored on the report's rows; polymorphic data only
  counts the report's own records; pivot headers name their related data.

  Background:
    Given the Acme report builder data

  # H1 — Happy path: the fund's name on a commitment report (a parent, one per row)
  Scenario: A parent's value is shown on each row
    Given a "CapitalCommitment" report with columns "folio_id,fund.name"
    And the report has related data "fund"
    When I run the report
    Then the row where "folio_id" is "F-1" shows "Growth Fund II" in "fund.name"
    And the row where "folio_id" is "F-4" shows "Global Fund" in "fund.name"

  # H2 — Happy path: the call's name on a payment report, reached through its remittance (has_one through)
  Scenario: A one-to-one record through another record is shown
    Given a "CapitalRemittancePayment" report with columns "reference_no,capital_call.name"
    And the report has related data "capital_call"
    When I run the report
    Then the row where "reference_no" is "UTR001" shows "Call 1 — GF2" in "capital_call.name"
    And the row where "reference_no" is "UTR002" shows "Call 2 — GF2" in "capital_call.name"

  # H3 — Happy path: an investor's funds through their commitments (two steps away), listed
  Scenario: Two-step related data is listed per row
    Given an "Investor" report with columns "investor_name,capital_commitments.fund.name"
    And the report has related data "capital_commitments.fund"
    When I run the report
    Then the row where "investor_name" is "Aditi Rao" lists "Global Fund, Growth Fund II" in "capital_commitments.fund.name"
    And the row where "investor_name" is "Kiran Mehta" lists "Growth Fund II" in "capital_commitments.fund.name"

  # H4 — Happy path: first-level and two-step related data from the same chain, side by side
  Scenario: First-level and two-step related data together
    Given an "Investor" report with columns "investor_name,capital_commitments.committed_amount,capital_commitments.fund.name"
    And the report has related data "capital_commitments"
    And the report has related data "capital_commitments.fund"
    When I run the report
    Then the row where "investor_name" is "Kiran Mehta" shows "25000000" in "capital_commitments.committed_amount"
    And the row where "investor_name" is "Kiran Mehta" lists "Growth Fund II" in "capital_commitments.fund.name"

  # H5 — Happy path: a commitment's document count excludes another owner type's document with the same id
  Scenario: Polymorphic related data counts only the report's own records
    Given the Acme documents exist
    And a "CapitalCommitment" report with columns "folio_id,documents.id"
    And the report has related data "documents"
    When I run the report
    Then the row where "folio_id" is "F-1" shows "1" in "documents.id"

  # H12 — Happy path: two pivots with the same category values get headers naming their related data
  Scenario: Pivot headers name their related data
    Given the Acme fund units exist
    And an "Investor" report with columns "investor_name"
    And the report has related data "capital_commitments"
    And the report has related data "fund_units"
    And the report pivots "capital_commitments" by "unit_type" on "committed_amount" with "sum"
    And the report pivots "fund_units" by "unit_type" on "quantity" with "sum"
    When I run the report
    Then the report headers include "Capital commitments · A (sum)"
    And the report headers include "Fund units · A (sum)"

  # E1 — Edge case: a row whose parent doesn't exist shows a blank, not an error
  Scenario: A missing parent reads as blank
    Given the Acme documents exist
    And a "Document" report with columns "name,capital_commitment.folio_id"
    And the report has related data "capital_commitment"
    When I run the report
    Then the row where "name" is "D1" shows "F-1" in "capital_commitment.folio_id"
    And the row where "name" is "D2" is blank in "capital_commitment.folio_id"
    And the row where "name" is "D3" is blank in "capital_commitment.folio_id"

  # X1 — Error case: a saved related-data path that no longer resolves leaves its column blank; the rest renders
  Scenario: A broken related-data path doesn't break the report
    Given an "Investor" report with columns "investor_name,capital_commitments.no_such.name"
    And the report has broken related data "capital_commitments.no_such"
    When I run the report
    Then the row where "investor_name" is "Aditi Rao" is blank in "capital_commitments.no_such.name"
