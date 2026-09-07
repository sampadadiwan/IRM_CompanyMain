@import @allocation_run_checker
Feature: Allocation Run Checker
  After an allocation run finishes, a reviewer runs the checker over it and gets a
  Pass / Warn / Fail report before deciding whether to lock the run. The checks are
  arithmetic and lookups only — the same run always produces the same result — and the
  report never locks or unlocks anything itself.

  Two questions are answered: did the run happen correctly (section 1), and do the numbers
  add up (section 2). Whether the numbers look reasonable (section 3) is out of scope.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Master Fund;currency=INR;unit_types=A1" for the entity
    And the fund has folios "101,102"

  # ── 1. Did the run happen correctly? ─────────────────────────────────────────

  Scenario: A clean run passes every check
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "400" for "Setup Fee"
    And the run produced cumulative entries matching the folio entries for "Setup Fee"
    When I check that allocation run
    Then the report status should be "Pass"
    And check "2.1" should be "pass"
    And check "2.2" should be "pass"

  Scenario: A run that did not finish fails check 1.1
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31;status=Formula 'Setup Fee' raised ZeroDivisionError"
    When I check that allocation run
    Then the report status should be "Fail"
    And check "1.1" should be "fail" mentioning "ZeroDivisionError"

  Scenario: A run that produced nothing for an enabled formula warns
    Given there is an enabled fund formula "Management Fees"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    When I check that allocation run
    Then the report status should be "Warn"
    And check "1.2" should be "warn" mentioning "Management Fees"

  Scenario: A folio committed before the period end that received nothing warns
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101"
    When I check that allocation run
    Then check "1.3" should be "warn" mentioning "102"

  Scenario: A gap after the previous locked run warns
    Given there is a locked allocation run "start_date=2023-10-01;end_date=2023-12-25"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    When I check that allocation run
    Then check "1.4" should be "warn" mentioning "gap"

  Scenario: A period that follows straight on from the previous locked run passes
    Given there is a locked allocation run "start_date=2023-10-01;end_date=2023-12-31"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    When I check that allocation run
    Then check "1.4" should be "pass"

  # ── 2. Do the numbers add up? ────────────────────────────────────────────────

  Scenario: A fund total that no longer matches its folio entries fails
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "999" for "Setup Fee"
    When I check that allocation run
    Then the report status should be "Fail"
    And check "2.1" should be "fail" mentioning "Setup Fee"

  Scenario: A folio cumulative that does not match the entries beneath it fails
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "400" for "Setup Fee"
    And the run produced a cumulative of "555" for folio "101" for "Setup Fee"
    When I check that allocation run
    Then the report status should be "Fail"
    And check "2.2" should be "fail" mentioning "101"

  Scenario: A cumulative that leaves out an entry back-dated into an earlier period fails
    Given there is a locked allocation run "start_date=2023-10-01;end_date=2023-12-31"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "400" for "Setup Fee"
    And the run produced cumulative entries matching the folio entries for "Setup Fee"
    And someone back-dates a "Setup Fee" entry of "50" for folio "101" into "2023-11-30"
    When I check that allocation run
    Then check "2.2" should be "fail" mentioning "101"

  Scenario: Percentage allocations that do not sum to 100 fail
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "400" for "Setup Fee"
    And the run produced percentages of "25" for folio "101" and "60" for folio "102"
    When I check that allocation run
    Then the report status should be "Fail"
    And check "2.3" should be "fail" mentioning "Percentage"

  Scenario: Percentages that are all zero are how the engine records a zero base, not a defect
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "400" for "Setup Fee"
    And the run produced percentages of "0" for folio "101" and "0" for folio "102"
    When I check that allocation run
    Then check "2.3" should be "pass"

  Scenario: A run that is still going is not reported as a failure
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31;status=Pending"
    And the run produced "Setup Fee" of "100" for folio "101"
    When I check that allocation run
    Then the report status should be "Warn"
    And check "1.1" should be "warn" mentioning "has not finished"
    And check "2.1" should be "skipped"
    And check "2.2" should be "skipped"

  # ── A run that only generated statements ─────────────────────────────────────

  Scenario: A run that did not run formulas has nothing to check
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31;run_allocations=false;status="
    When I check that allocation run
    Then the report status should be "Pass"
    And check "1.4" should be "skipped"
    And check "2.1" should be "skipped"
    And check "2.2" should be "skipped"
    And the summary should say nothing was checked

  # ── Checking a run long after it ran ─────────────────────────────────────────

  Scenario: A run older than run-id tagging is not reported as having produced nothing
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And there is an enabled fund formula "Management Fees"
    And that run was made on "2023-08-01"
    When I check that allocation run
    Then check "1.2" should be "skipped" mentioning "tag entries with the run that made them"
    And check "1.3" should be "skipped" mentioning "tag entries with the run that made them"
    And check "2.1" should be "skipped" mentioning "tag entries with the run that made them"

  Scenario: A run older than the status column is not reported as never having finished
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31;status="
    And that run was made on "2023-08-01"
    When I check that allocation run
    Then check "1.1" should be "skipped" mentioning "record a run's status"

  Scenario: The arithmetic checks still work on a run too old to be checked by run id
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a cumulative of "555" for folio "101" for "Setup Fee"
    And the run produced percentages of "25" for folio "101" and "60" for folio "102"
    And that run was made on "2023-08-01"
    When I check that allocation run
    Then the report status should be "Fail"
    And check "2.2" should be "fail" mentioning "101"
    And check "2.3" should be "fail" mentioning "Percentage"

  # ── The report never decides anything ────────────────────────────────────────

  Scenario: Checking a run leaves the run itself untouched
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    When I check that allocation run
    Then the allocation run should still be unlocked
    And no account entry should have been created or changed by the check

  Scenario: Re-checking a run overwrites its report rather than adding another
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "999" for "Setup Fee"
    When I check that allocation run
    Then the report status should be "Fail"
    When the fund total for "Setup Fee" is corrected to "400"
    And I check that allocation run
    Then the report status should be "Pass"
    And the allocation run should have exactly one report

  # ── The screens ──────────────────────────────────────────────────────────────

  @javascript
  Scenario: The allocation screen offers the check and shows the result once it exists
    Given I am at the login page
    When I fill and submit the login page
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    When I visit the allocation screen of the fund
    Then I should see "Not checked"
    When I press the check button for that allocation run
    Then I should be on the report page
    When I visit the allocation screen of the fund
    Then I should see the report badge "Pass" for that allocation run

  @javascript
  Scenario: The report page shows each check under the question it answers
    Given I am at the login page
    When I fill and submit the login page
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And the run produced "Setup Fee" of "100" for folio "101" and "300" for folio "102"
    And the run produced a fund total of "999" for "Setup Fee"
    And that allocation run has been checked
    When I open the report page
    And I click the report tab "Did the run happen correctly?"
    Then I should see "1.3"
    When I click the report tab "Do the numbers add up?"
    Then I should see "2.1"
    And I should see "Sum of entries"

  Scenario: An employee without rights on the fund cannot check its runs
    Given there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"
    And there is another employee without rights on the fund
    When that employee tries to check the allocation run
    Then the check should be refused
