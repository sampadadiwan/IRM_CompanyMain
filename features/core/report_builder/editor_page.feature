@rack_test @report_builder
Feature: Report Builder page — layout, help and preview states

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  The builder is a page of settings tabs beside a preview that loads by itself.
  Icon buttons are labelled, the guide and command search are one click away,
  and the preview explains itself when it's empty or fails.

  Background:
    Given the Acme report builder data
    And I am signed in as Meera

  # H17 — Happy path: icon-only buttons have accessible labels; the guide link and command search button are present
  Scenario: Labels and help on the builder
    Given the Acme report "LPs"
    When I open the builder
    Then the builder page loads
    And every icon-only control on the builder has an accessible label
    And the builder links to the Report Builder guide
    And the builder has a command search button

  # E19 — Edge case: a preview that can't be produced shows its error inside the preview, not an error page
  Scenario: A preview error stays inside the preview
    Given the Acme report "LPs"
    And the preview engine fails
    When I open the builder preview
    Then the builder page loads
    And the preview shows the error "Simulated engine failure"

  # E20 — Edge case: a report with no columns says what to do next
  Scenario: An empty report names the next action
    Given an "Investor" report with no columns
    When I open the builder preview
    Then the preview says "Tick columns on the left, then Add selected."
