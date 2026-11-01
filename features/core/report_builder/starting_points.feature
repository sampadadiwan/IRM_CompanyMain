@rack_test @report_builder
Feature: Report Builder starting points — one New report, one set of names

  Worked examples: openspec/changes/report-builder-starting-points/business-rules.md
  The Reports page has one New report menu (From a template, Guided setup).
  The step-by-step flow is "Guided setup" everywhere, and templates never
  change an existing report.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera
    And the Acme report "LPs"

  # H1 — Happy path: one New report menu; the old builder buttons are gone
  Scenario: One New report menu
    When I open the Reports page
    Then the New report menu offers "From a template, Guided setup, Describe it"
    And the page has no "New Custom Report"
    And the page has no "Builder Report"

  # H11 — Happy path: the card menu, guided setup and builder use "Guided setup" and "Duplicate", never the retired names
  Scenario: One name everywhere
    When I open the Reports page
    Then the card menu of "LPs" offers "Guided setup, Duplicate"
    And the page has no "Guided Wizard"
    When I open "guided setup" of the report
    Then the report builder page reads "Guided setup"
    And the page has no "Guided Wizard"
    When I open "the builder" of the report
    Then the page has no "Advanced builder"
    And the page has no "Custom report"
    And the page has no "Guided Wizard"

  # E7 — Edge case: the builder has no Templates button and the old apply-template address is gone; the report is untouched
  Scenario: Templates never change an existing report
    When I open "the builder" of the report
    Then the builder has no Templates button
    When I request the old apply-template address
    Then the answer is Not found
    And the report is unchanged
