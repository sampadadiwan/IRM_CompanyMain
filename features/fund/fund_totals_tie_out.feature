@import @tie_out
Feature: Tie a run's fund totals out to the fund's own figures
  Funds keep their books in a spreadsheet outside CapHive and review an allocation run in two
  steps: first the fund totals against that sheet, then a few folios. The Account Entries
  Period Report, opened from a run, carries a tab for step one — one row per entry name, our
  total beside theirs, and the difference.

  The figures belong to the fund and the period, not to our attempt at it: re-running a period
  creates a new AllocationRun and hard-deletes the previous attempt's entries, so figures tied
  to a run would have to be retyped after every re-run.

  See docs/modules/allocation/allocation_run_review_proposals.md (proposal 3).

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Master Fund;currency=INR;unit_types=A1" for the entity
    And the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"

  # ── The sheet itself ──────────────────────────────────────────────────────────

  @rack_test
  Scenario: The sheet totals each entry name across the run's folios
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I open the tie-out sheet for that run
    Then the tie-out row "Setup Fee" should show our total as "400.00"
    And the tie-out row "Setup Fee" should be "not entered"

  # A result the engine writes only at fund level (the fund's portfolio numbers, say) is a
  # non-cumulative fund-level entry. A cumulative fund entry is a roll-up of folio entries and
  # cannot exist without them, so it is not the case to test here.
  @rack_test
  Scenario: An entry produced only at fund level still gets a row
    Given the run produced a fund-level "Audit Fee" entry of "50000"
    When I open the tie-out sheet for that run
    Then the tie-out sheet should have a row for "Audit Fee"

  @rack_test
  Scenario: Rows follow the fund's own formula order, not the alphabet
    Given there is an enabled fund formula "Zeta Fee" at sequence "1"
    And there is an enabled fund formula "Alpha Fee" at sequence "2"
    And the run produced "Zeta Fee" of "100" for folio "101"
    And the run produced "Alpha Fee" of "100" for folio "101"
    When I open the tie-out sheet for that run
    Then the tie-out rows should be in the order "Zeta Fee,Alpha Fee"

  @rack_test
  Scenario: An entry name whose formula is gone sorts last
    Given there is an enabled fund formula "Known Fee" at sequence "3"
    And the run produced "Known Fee" of "100" for folio "101"
    And the run produced "Orphan Fee" of "100" for folio "101"
    When I open the tie-out sheet for that run
    Then the tie-out rows should be in the order "Known Fee,Orphan Fee"

  # ── Comparing with the fund's figures ─────────────────────────────────────────

  @rack_test
  Scenario: A figure equal to our total marks the row as matching
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I enter "400" as the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should be "match"
    And the tie-out row "Setup Fee" should show a difference of "0.00"

  @rack_test
  Scenario: A different figure shows the signed difference
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I enter "450" as the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should be "differs"
    And the tie-out row "Setup Fee" should show a difference of "50.00"

  @rack_test
  Scenario: A figure below ours shows a negative difference
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I enter "350" as the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should show a difference of "-50.00"

  @rack_test
  Scenario: Figures that differ only beyond two decimal places count as matching
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I enter "400.001" as the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should be "match"

  @rack_test
  Scenario: A figure of zero is a real figure, not an empty box
    Given the run produced "Setup Fee" of "0" for folio "101"
    When I enter "0" as the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should be "match"

  @rack_test
  Scenario Outline: Amounts are read the way a spreadsheet writes them
    When the fund's figure "<typed>" is read
    Then it should be understood as "<cents>"

    Examples:
      | typed      | cents      |
      | 8,10,000   | 81000000   |
      | 810000.50  | 81000050   |
      | (3,500)    | -350000    |
      | ₹ 1,200    | 120000     |
      |            |            |
      | abc        |            |

  Scenario: Clearing the box removes the figure
    Given the run produced "Setup Fee" of "10000" for folio "101"
    And I enter "400" as the fund's figure for "Setup Fee" on that run
    When I clear the fund's figure for "Setup Fee" on that run
    Then the tie-out row "Setup Fee" should be "not entered"
    And there should be no stored figure for "Setup Fee"

  @rack_test
  Scenario: The sheet counts how many rows are entered, match and differ
    Given the run produced "Setup Fee" of "40000" for folio "101"
    And the run produced "Audit Fee" of "10000" for folio "101"
    And the run produced "Legal Fee" of "20000" for folio "101"
    When I enter "400" as the fund's figure for "Setup Fee" on that run
    And I enter "999" as the fund's figure for "Audit Fee" on that run
    Then the tie-out sheet should count 2 entered, 1 matching and 1 differing

  # ── Surviving a re-run ────────────────────────────────────────────────────────

  @rack_test
  Scenario: Figures entered against one run are still there after the period is re-run
    Given the run produced "Setup Fee" of "40000" for folio "101"
    And I enter "400" as the fund's figure for "Setup Fee" on that run
    When the same period is run again
    And the run produced "Setup Fee" of "40000" for folio "101"
    And I open the tie-out sheet for that run
    Then the tie-out row "Setup Fee" should be "match"

  # ── Folios behind a row ───────────────────────────────────────────────────────

  @rack_test
  Scenario: Opening a row lists its folios, largest first
    Given the run produced "Setup Fee" of "10000" for folio "101" and "30000" for folio "102"
    When I open the folios behind "Setup Fee" for that run
    Then the folio list should name "102" before "101"
    And the folio list should report 2 folios in total

  # ── What each total is built from ─────────────────────────────────────────────
  # The Dependencies tab: every dependency is another row of the same sheet, resolved from the
  # fund's own formulas, so a difference at one total can be traced to the total carrying it.

  @rack_test
  Scenario: A row lists the other totals its formula is built from
    Given there is a fund formula "NAV" at sequence "3" computing "@capital_collected - @fees_charged"
    And the run produced "Capital Collected" of "100000" for folio "101"
    And the run produced "Fees Charged" of "20000" for folio "101"
    And the run produced "NAV" of "80000" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "NAV" should be built from "Capital Collected,Fees Charged"

  @rack_test
  Scenario: A dependency named as a string in a helper call is followed too
    Given there is a fund formula "Since Inception Fees" at sequence "3" computing "capital_commitment.since_inception('Fees Charged', nil, @start_date, @end_date)"
    And the run produced "Fees Charged" of "20000" for folio "101"
    And the run produced "Since Inception Fees" of "20000" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "Since Inception Fees" should be built from "Fees Charged"

  @rack_test
  Scenario: A formula naming something this run did not produce lists no dependency
    Given there is a fund formula "NAV" at sequence "3" computing "@capital_collected - @missing_thing"
    And the run produced "Capital Collected" of "100000" for folio "101"
    And the run produced "NAV" of "80000" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "NAV" should be built from "Capital Collected"

  @rack_test
  Scenario: A total read only by next period's formula is still top-level in this run
    Given there is a fund formula "Ending Balance" at sequence "1" computing "@opening_cash + @inflow"
    And there is a fund formula "Beginning Balance" at sequence "2" computing "capital_commitment.get_account_entry_or_zero('Ending Balance', @start_date).amount_cents"
    And the run produced "Opening Cash" of "1000" for folio "101"
    And the run produced "Inflow" of "500" for folio "101"
    And the run produced "Ending Balance" of "1500" for folio "101"
    And the run produced "Beginning Balance" of "900" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "Ending Balance" should be top-level

  Scenario: A row with no formula behind it has no dependencies
    Given the run produced "Orphan Fee" of "100" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "Orphan Fee" should have no dependencies

  Scenario: A formula that refers to itself does not list itself
    Given there is a fund formula "Rolling Fee" at sequence "3" computing "@rolling_fee + 1"
    And the run produced "Rolling Fee" of "100" for folio "101"
    When I open the tie-out sheet for that run
    Then the row "Rolling Fee" should have no dependencies

  # ── Permissions ───────────────────────────────────────────────────────────────

  @rack_test
  Scenario: An investor may not record the fund's figures
    Given there is an investor user on the entity
    When that investor tries to record a figure
    Then recording the figure should be refused

  @rack_test
  Scenario: A company admin may record the fund's figures
    When the company admin tries to record a figure
    Then recording the figure should be allowed
