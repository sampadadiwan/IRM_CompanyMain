@rack_test @report_builder
Feature: Report Builder filters — the right input for each field

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  A filter offers a pick-list of existing values for text with few values, the
  entity's funds for a fund, and a plain text box where listing values would be
  slow (the largest tables) or unhelpful (more than 30 values).

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"

  # H8 — Happy path: Category offers its existing values; a commitment's Fund offers the entity's funds by name
  Scenario: Pick-list and fund picker
    When I open the filter row for "category"
    Then the filter row offers the choices "Co-Investor, LP"
    And the filter row operators are "is, is not, is any of, is empty"
    When I open the filter row for "fund_id" on "capital_commitments"
    Then the filter row offers the choices "Global Fund, Growth Fund II"

  # E7 — Edge case: a field on a very large table (capital remittances) gets a text box, with no value query
  Scenario: Large table field
    Given the report has related data "capital_remittances"
    When I open the filter row for "status" on "capital_remittances"
    Then the filter row is a text box

  # E8 — Edge case: a text field with more than 30 different values gets a text box
  Scenario: Many values
    Given 31 investors with different cities exist
    When I open the filter row for "city"
    Then the filter row is a text box
