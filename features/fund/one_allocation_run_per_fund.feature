@rack_test
Feature: Only one allocation run per fund at a time
  Two allocation runs on the same fund delete each other's entries and both insert theirs. On
  2026-11-10 runs 3499 and 3500 of fund 316 overlapped this way and left October with duplicated
  entries (docs/modules/allocation/allocation_process.md, "One run per fund at a time"). A fund with an unfinished run therefore refuses a
  new one. An unfinished run whose process died never finishes by itself, so it can be marked as
  crashed straight away instead of blocking the fund until it goes stale (12 hours). That is offered
  only while no engine is actually running on the fund.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Test Fund" for the entity

  # ── Starting a run from the Allocate screen ─────────────────────────────────

  # H1 — Happy path: a finished run does not hold the fund
  Scenario: A run can start once the previous run has finished
    Given an allocation run on the fund started "10 minutes" ago with status "Success"
    When I start an allocation run on the Allocate screen
    Then a new allocation run is created for the fund

  # X1 — Error case: the run 3500 case, a second run while the first is still running
  Scenario: A second run is refused while a run on the fund is still running
    Given an allocation run on the fund started "2 minutes" ago with status "Pending"
    And an allocation engine is running on the fund
    When I start an allocation run on the Allocate screen
    Then I should see "has not finished yet. Wait for it to finish before starting another run on this fund." on the page
    And no new allocation run is created for the fund
    And Previous Runs shows "Running. No other run can start on this fund until it finishes." for that run
    And Previous Runs does not offer "Mark as crashed" for that run

  # E1 — Edge case: a run whose process died blocks the fund, and can be marked crashed at once
  Scenario: A crashed run is marked as crashed and the fund can run again
    Given an allocation run on the fund started "30 minutes" ago with status "Pending"
    When I start an allocation run on the Allocate screen
    Then I should see "is no longer running. Mark it as crashed under Previous Runs" on the page
    And no new allocation run is created for the fund
    And Previous Runs shows "Not running on any server, so it will not finish." for that run
    When I mark that run as crashed under Previous Runs
    Then I should see "marked as crashed. You can now start a new run on this fund" on the page
    And that run's status starts with "Crashed: marked as crashed by"
    And Previous Runs does not offer "Mark as crashed" for that run
    When I start an allocation run on the Allocate screen
    Then a new allocation run is created for the fund

  # E2 — Edge case: a run that died before writing any status blocks the fund the same way
  Scenario: A run that never wrote a status blocks the fund until marked as crashed
    Given an allocation run on the fund started "5 minutes" ago with status ""
    When I start an allocation run on the Allocate screen
    Then I should see "has not finished yet and is no longer running" on the page
    And no new allocation run is created for the fund
    And Previous Runs offers "Mark as crashed" for that run

  # E3 — Edge case: an unfinished run older than 12 hours is taken to have died and no longer blocks
  Scenario: A stale unfinished run does not block the fund
    Given an allocation run on the fund started "13 hours" ago with status "Pending"
    When I start an allocation run on the Allocate screen
    Then a new allocation run is created for the fund
    And Previous Runs does not offer "Mark as crashed" for that run

  # E4 — Edge case: a run that ended in an error has finished; it does not block
  Scenario: A failed run does not block the fund
    Given an allocation run on the fund started "10 minutes" ago with status "Error in Formula 307: Distribution towards preferred return"
    When I start an allocation run on the Allocate screen
    Then a new allocation run is created for the fund

  # E5 — Edge case: the engine picked the run up between the page loading and the click
  Scenario: Marking a run as crashed is refused once an engine is running on the fund
    Given an allocation run on the fund started "30 minutes" ago with status "Pending"
    And Previous Runs offers "Mark as crashed" for that run
    And an allocation engine is running on the fund
    When I mark that run as crashed under Previous Runs
    Then I should see "was not marked as crashed: it has finished, or it is still running." on the page
    And that run's status is "Pending"

  # ── The engine itself ─────────────────────────────────────────────────────────

  # E6 — Edge case: a run marked crashed while its job sat in the queue does not start later
  Scenario: The queued job of a run marked as crashed does not run its formulas
    Given an allocation run on the fund started "1 minutes" ago with status ""
    And that run is marked as crashed
    And the allocation formulas are stubbed to succeed
    When the allocation job of that run runs
    Then no formulas ran
    And that run's status starts with "Crashed: marked as crashed by"

  # E7 — Edge case: two engines slipped past the screen's check (a double-click); the second stops
  Scenario: A second engine on the same fund stops before running any formula
    Given an allocation run on the fund started "0 minutes" ago with status ""
    And an allocation engine is running on the fund
    And the allocation formulas are stubbed to succeed
    When the allocation job of that run runs
    Then no formulas ran
    And that run's status is "Not started: another allocation run is already running on this fund. Wait for it to finish, then run this period again."

  # E8 — Edge case: a statements-only run used to keep a blank status for ever and would block the fund
  Scenario: A run that runs no formulas ends with status Success
    Given an allocation run on the fund that runs no formulas, started "0 minutes" ago with status ""
    And the allocation formulas are stubbed to succeed
    When the allocation job of that run runs
    Then the formulas ran once
    And that run's status is "Success"

  # E9 — Edge case: an exception ends the run in-process, so it must not be left reading as running
  Scenario: A run that raises ends with a Failed status
    Given an allocation run on the fund started "0 minutes" ago with status ""
    And the allocation formulas will raise "boom"
    When the allocation job of that run runs
    Then the job failed with "boom"
    And that run's status is "Failed: RuntimeError: boom"

  # E10 — Edge case: two runs of one fund in one Sidekiq process used to share a scratch file
  Scenario: Each run gets its own scratch file
    Then two runs of the same fund get different scratch files

  # ── Re-running an existing run ─────────────────────────────────────────────────

  # X2 — Error case: rerun! is held to the same rule as a new run
  Scenario: Re-running a run is refused while another run on the fund is still running
    Given an allocation run on the fund started "2 minutes" ago with status "Pending"
    And an allocation engine is running on the fund
    When another run on the fund, which finished, is re-run
    Then the re-run is refused with "has not finished yet"

  # E11 — Edge case: re-running the crashed run itself is one way to recover it
  Scenario: A crashed run can be re-run into itself
    Given an allocation run on the fund started "30 minutes" ago with status "Pending"
    And the allocation formulas are stubbed to succeed
    When that run is re-run
    Then the re-run is accepted
    And that run's status is "Success"

  # X3 — Error case: re-running a run that is still executing would run it twice at once
  Scenario: Re-running a run that is still running is refused
    Given an allocation run on the fund started "2 minutes" ago with status "Pending"
    And an allocation engine is running on the fund
    When that run is re-run
    Then the re-run is refused with "has not finished yet"
