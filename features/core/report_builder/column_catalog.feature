@rack_test @report_builder
Feature: Report Builder column catalog — every offered column shows a value

  Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
  Columns that only exist on a grid decorator are read as plain text; searchable
  fields with no readable value are offered as filters only; related data only
  offers stored fields.

  Background:
    Given the Acme report builder data

  # H6 — Happy path: "Investing Entity" on a remittance report shows the KYC's name instead of a blank column
  Scenario: A decorator-only column shows its value
    Given a "CapitalRemittance" report with columns "investor_name,investing_entity_name"
    When I run the report
    Then the row where "investor_name" is "Aditi Rao" shows "Aditi Rao Family Trust" in "investing_entity_name"

  # E12 — Edge case: a filter-only field ("Carry") is offered as a filter but not as a column
  Scenario: Filter-only fields are filters, not columns
    Then the "CapitalDistribution" column list does not include "carry"
    And the "CapitalDistribution" filter list includes "carry"
    And the "CapitalDistribution" column list includes "distribution_amount"

  # E13 — Edge case: related data offers only stored fields, so a decorator-only field isn't offered there
  Scenario: Related column lists offer only stored fields
    Then the related column list for "CapitalCommitment" does not include "investor_kyc_full_name"
    And the related column list for "CapitalCommitment" includes "committed_amount"

  # E14 — Edge case: drift guard over every reportable table — no offered column without a reader, no reader without a real preload
  Scenario: Every offered column of every reportable table is readable
    Then every offered root column of every reportable table is readable
