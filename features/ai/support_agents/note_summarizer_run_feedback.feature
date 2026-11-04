# Worked examples (H10-H12, E8-E10, E14-E16, X2): openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples
Feature: Summarise Notes says which notes it covers and where the summary goes
  The Note Summariser summarises the last completed quarter (or month). The run window names those dates, a manual
  run says where the summary will appear, and a period with no notes says why its summary is empty.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=Flipkart Unlisted;category=Portfolio Company"
    Given the note summariser is enabled for the entity with summary period ""
    Given the company "Flipkart Unlisted" has notes dated "27/10/2026, 29/10/2026, 30/10/2026, 04/11/2026"

  # H10 — Happy path: on 03 Nov 2026 a quarterly summariser covers Jul 01 – Sep 30, 2026
  @rack_test
  Scenario: Run window names the quarter
    Given today is "2026-11-03"
    When I open the notes of "Flipkart Unlisted"
    Then the run window should say "Summarises notes dated Jul 01, 2026 – Sep 30, 2026 (the last completed quarter)."

  # H11 — Happy path: after Run, the page says which notes are summarised and where the summary will appear
  @javascript
  Scenario: Message after Run
    Given today is "2026-11-03"
    When I open the notes of "Flipkart Unlisted"
    And I run the note summariser from the notes list
    Then I should see the page message "Summarising notes dated Jul 01, 2026 – Sep 30, 2026. The summary will appear in this Notes list as a note tagged 'summary' dated 30/09/2026, and in the Note Summaries widget."

  # H12 — Happy path: a period with notes gets a summary note, dated the period's last day, in the Notes list
  @rack_test
  Scenario: Summary note appears in the Notes list
    Given today is "2026-11-03"
    And the company "Flipkart Unlisted" has notes dated "10/08/2026, 20/09/2026"
    And the summariser's LLM replies "Two updates."
    When the note summariser runs for "Flipkart Unlisted"
    And I open the notes of "Flipkart Unlisted"
    Then the notes should include a "summary" note dated "30/09/2026" reading "Two updates."

  # E8 — Edge case: a monthly summariser on 03 Nov 2026 covers October
  @rack_test
  Scenario: Monthly summariser
    Given today is "2026-11-03"
    And the note summariser's summary period is "Month"
    When I open the notes of "Flipkart Unlisted"
    Then the run window should say "Summarises notes dated Oct 01, 2026 – Oct 31, 2026 (the last completed month)."

  # E9 — Edge case: the Note Summaries entry shows the same dates as the window, with the year on both
  @rack_test
  Scenario: Window and report agree
    Given today is "2026-11-03"
    When the note summariser runs for "Flipkart Unlisted"
    And I open the Note Summaries of "Flipkart Unlisted"
    Then the Note Summaries entry should show "Quarter (Jul 01, 2026 – Sep 30, 2026)"

  # E10 — Edge case: every note is dated after the period, so 0 notes are processed and the entry says why
  @rack_test
  Scenario: Notes only after the period
    Given today is "2026-11-03"
    When the note summariser runs for "Flipkart Unlisted"
    And I open the Note Summaries of "Flipkart Unlisted"
    Then the Note Summaries entry should show "Notes processed:"
    And the Note Summaries entry should show notes processed "0"
    And the Note Summaries entry should show "No notes dated Jul 01, 2026 – Sep 30, 2026. Notes dated after Sep 30, 2026 will be in the next quarter's summary."
    And the Note Summaries entry should not show a summary box

  # E14 — Edge case: on 01 Jan 2027 the last completed quarter is Oct – Dec 2026
  @rack_test
  Scenario: Year boundary
    Given today is "2027-01-01"
    And I am signed in as the current user
    When I open the notes of "Flipkart Unlisted"
    Then the run window should say "Summarises notes dated Oct 01, 2026 – Dec 31, 2026 (the last completed quarter)."

  # E15 — Edge case: on the last day of a quarter, that quarter is not yet complete
  @rack_test
  Scenario: Last day of a quarter
    Given today is "2026-09-30"
    When I open the notes of "Flipkart Unlisted"
    Then the run window should say "Summarises notes dated Apr 01, 2026 – Jun 30, 2026 (the last completed quarter)."

  # E16 — Edge case: with the summariser disabled for the entity the button stays greyed out and no window is drawn
  @rack_test
  Scenario: Summariser disabled
    Given the note summariser is disabled for the entity
    When I open the notes of "Flipkart Unlisted"
    Then I should not see "Summarises notes dated"
    And the Summarise Notes button should be locked

  # X2 — Error case: notes existed but the LLM failed, so the entry keeps today's empty Summary box for editors, not the
  #      empty-period message
  @rack_test
  Scenario: LLM fails with notes in the period
    Given today is "2026-11-03"
    And the company "Flipkart Unlisted" has notes dated "10/08/2026"
    And the summariser's LLM fails
    When the note summariser runs for "Flipkart Unlisted"
    And I open the Note Summaries of "Flipkart Unlisted"
    Then the Note Summaries entry should show notes processed "1"
    And the Note Summaries entry should not show "No notes dated"
    And the Note Summaries entry should show a summary box
