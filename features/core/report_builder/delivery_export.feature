@report_builder
Feature: Report Builder delivery — export progress and recent exports

  Worked examples: openspec/changes/report-builder-delivery/business-rules.md
  Export XLSX reads "Preparing…" from the click until the export job replaces
  it with Download (or puts it back on failure); the report page lists the
  report's last five exports.

  Background:
    Given the Acme report builder data
    And the Acme delivery report "LPs"

  # H1 — Happy path: Export on the report page goes Preparing… → Download, and the file joins Recent exports
  @javascript
  Scenario: Export from the report page
    Given exports take a moment
    And Meera is on the report page
    When I click Export XLSX
    Then the export button reads "Preparing…" and is disabled
    And the export button offers Download and Export again
    And the first recent export reads "LPs · Meera"

  # H2 — Happy path: the builder header's Export goes through the same states
  @javascript
  Scenario: Export from the builder
    Given exports take a moment
    And Meera is on the builder for the report
    When I click Export XLSX
    Then the export button reads "Preparing…" and is disabled
    And the export button offers Download and Export again

  # H3 — Happy path: the five newest of seven exports, newest first, with who and when
  @rack_test
  Scenario: Recent exports
    Given the report has been exported 7 times, a minute apart from "2026-11-01 10:00"
    And I am signed in as Meera
    When I open the report builder report page
    Then Recent exports lists 5 files
    And the recent exports read "LPs · Meera" at "01 Nov 2026 10:06, 01 Nov 2026 10:05, 01 Nov 2026 10:04, 01 Nov 2026 10:03, 01 Nov 2026 10:02"

  # E1 — Edge case: a report never exported says how to make one
  @rack_test
  Scenario: No exports yet
    Given I am signed in as Meera
    When I open the report builder report page
    Then the report page reads "No exports yet — Export XLSX makes one."

  # E2 — Edge case: another report's exports aren't listed
  @rack_test
  Scenario: Only this report's exports
    Given another Acme report "Funds" has been exported
    And I am signed in as Meera
    When I open the report builder report page
    Then the report page reads "No exports yet — Export XLSX makes one."

  # X1 — Error case: a failed export puts the button back and says why
  @javascript
  Scenario: Export fails
    Given exports take a moment
    And exports of the report fail with "Disk full"
    And Meera is on the report page
    When I click Export XLSX
    Then the export button reads "Preparing…" and is disabled
    And the export button reads "Export XLSX" again
    And I see the alert "Couldn't export LPs: Disk full"
