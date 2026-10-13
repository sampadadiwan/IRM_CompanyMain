@import @entry_explanation
Feature: How an entry's number was worked out
  The entry page explains its number by breaking the rule that produced it into the terms it
  returns — the parts of a sum, the factors of a product, the named steps it uses — each with
  the value the run recorded. A term that is another entry opens into that entry's own
  breakdown, and so on down.

  Conditions, id comparisons and record lookups are never lines: they decide which branch runs,
  they do not add up to anything. Nothing is recalculated.

  See docs/modules/allocation/allocation_run_review_proposals.md (proposal 1).

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Master Fund;currency=INR;unit_types=A1" for the entity
    And the fund has folios "101,102"
    And there is a finished allocation run "start_date=2024-01-01;end_date=2024-03-31"

  # ── Sums ──────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: A sum breaks into its terms, with deductions marked, and says it adds up
    Given the run produced "Capital Collected" of "100000" for folio "101"
    And the run produced "Fees Charged" of "20000" for folio "101"
    And the run produced "NAV" of "80000" for folio "101" computed by "@capital_collected - @fees_charged"
    When I open the explanation of "NAV" for folio "101"
    Then the explanation should list "Capital Collected,Fees Charged"
    And term "Fees Charged" should be taken away
    And term "Capital Collected" should be another entry
    And the explanation should say its lines add up

  Scenario: A sum whose terms do not come back to the entry says so
    Given the run produced "Audit Fees" of "30000" for folio "101"
    And the run produced "Legal Fees" of "50000" for folio "101"
    And the run produced "Total Expenses" of "99999" for folio "101" computed by "@audit_fees + @legal_fees"
    When I open the explanation of "Total Expenses" for folio "101"
    Then the explanation should say its lines do not add up

  # ── Products ──────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: A product breaks into factors, and claims no total
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2360" for folio "101" computed by "@base * 2 / 100 * 1.18" recording:
      | expression           | value  |
      | @base                | 100000 |
      | @base * 2 / 100 * 1.18 | 2360 |
    When I open the explanation of "Fee" for folio "101"
    Then the explanation should list "Base,2,100,1.18"
    And term "Base" should carry no operator
    And term "100" should divide
    And the explanation should not claim a total

  # ── Named steps and branches ──────────────────────────────────────────────────

  @rack_test
  Scenario: A named step opens into its own expression
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "22000" for folio "101" computed by "months = 12 - 1; @base * months / 50" recording:
      | expression | value |
      | months     | 11    |
    When I open the explanation of "Fee" for folio "101"
    Then term "Months" should show "11"
    And term "Months" should open into "12,1"

  @rack_test
  Scenario: A rule that returns from inside an if is broken down from the branch it took
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "if @base > 0; @base * 2 / 100; else; 0; end" recording:
      | expression        | value |
      | @base * 2 / 100   | 2000  |
    When I open the explanation of "Fee" for folio "101"
    Then the explanation should list "Base,2,100"

  # ── Which assignment ran ──────────────────────────────────────────────────────
  # A rule often starts a step at zero and sets it for real inside an if. The step opens into the
  # assignment that ran: later assignments replace earlier ones, and only the branch the run took
  # counts — chosen from the condition's recorded true/false. Ids ES1–ES3 are named in
  # AccountEntryExplanation#collect_locals and #chosen_branch.

  # ES1 — Edge case: a step set to zero, then reassigned inside an if, opens into the reassignment
  @rack_test
  Scenario: A step reassigned inside an if opens into the assignment that ran, not its starting zero
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "result = 0; if @base > 0; result = @base * 2 / 100; end; result" recording:
      | expression | value |
      | @base > 0  | true  |
      | result     | 2000  |
    When I open the explanation of "Fee" for folio "101"
    Then term "Result" should show "2000"
    And term "Result" should open into "Base,2,100"

  # ES2 — Edge case: nested ifs — the branch is picked by the recorded false, not by being first
  @rack_test
  Scenario: A nested if takes the branch its recorded condition chose
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "result = 0; if @base > 0; if @base > 500000; result = @base * 3 / 100; else; result = @base * 2 / 100; end; end; result" recording:
      | expression     | value |
      | @base > 0      | true  |
      | @base > 500000 | false |
      | result         | 2000  |
    When I open the explanation of "Fee" for folio "101"
    Then term "Result" should open into "Base,2,100"

  # ES3 — Edge case: a false condition with no else ran nothing, so the starting zero stands
  @rack_test
  Scenario: A step whose if did not run keeps its starting value and has nothing to open
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "0" for folio "101" computed by "result = 0; if @base > 500000; result = @base * 2 / 100; end; result" recording:
      | expression     | value |
      | @base > 500000 | false |
      | result         | 0     |
    When I open the explanation of "Fee" for folio "101"
    Then term "Result" should show "0"
    And term "Result" should have no parts

  # ── Calculation steps ─────────────────────────────────────────────────────────
  # Beneath the tree, every value the run recorded, so the lookups and settings that are not
  # terms of the result (a rate, a date, the ids a rule picked) can be read too. Ids ES4–ES6 are
  # named in AccountEntryExplanation#steps and _explanation_steps.html.erb.

  # ES4 — Happy path: named steps first, in the order the rule sets them, then the parts inside them; the run's dates are left out
  @rack_test
  Scenario: The calculation steps list the rule's named steps in order, then the parts inside them
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "22000" for folio "101" computed by "rate = 2; months = 12 - 1; @base * months * rate / 100" recording:
      | expression  | value      |
      | @end_date   | 2024-03-31 |
      | 12 - 1      | 11         |
      | months      | 11         |
      | rate        | 2          |
    When I open the explanation of "Fee" for folio "101"
    Then the calculation steps should be "rate=2,months=11,12 - 1=11"

  # ES5 — Happy path: the steps table renders each step with its value formatted for reading
  @rack_test
  Scenario: The calculation steps table shows each step and its value
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "fx_rate = 96.3234; total = @base * 2; total / 100" recording:
      | expression | value          |
      | fx_rate    | 96.3234        |
      | total      | 200000.0       |
      | first_dist | Distribution 1 |
    When I open the explanation of "Fee" for folio "101"
    And the calculation steps table is drawn
    Then the steps table should show "fx_rate" as "96.32"
    And the steps table should show "total" as "200,000"
    And the steps table should show "first_dist" as "Distribution 1"

  # ES6 — Edge case: a run made without "Explain Formulas" recorded nothing, so there is no steps table
  @rack_test
  Scenario: A run that recorded no values has no calculation steps
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "@base * 2 / 100" with no breakdown
    When I open the explanation of "Fee" for folio "101"
    Then there should be no calculation steps
    And the calculation steps table is drawn
    Then the steps table should not be drawn

  # ── Reading other entries ─────────────────────────────────────────────────────

  @rack_test
  Scenario: A same-period read by name is another entry
    Given the run produced "Opening Fee" of "5000" for folio "101"
    And the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.get_account_entry_or_zero('Opening Fee', @end_date).amount_cents"
    When I open the explanation of "Fee" for folio "101"
    Then term "Opening Fee" should be another entry

  @rack_test
  Scenario: A read from an earlier period is named as such and not opened
    Given the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.get_account_entry_or_zero('Closing Fee', @start_date).amount_cents"
    When I open the explanation of "Fee" for folio "101"
    Then term "Closing Fee" should be from an earlier period
    And term "Closing Fee" should say "at the start of this period"

  @rack_test
  Scenario: Summing this folio's entries of a name is a total that can be opened
    Given the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.account_entries.where(name: 'Audit Fees', reporting_date: ..@end_date).sum(:amount_cents)"
    When I open the explanation of "Fee" for folio "101"
    Then term "Audit Fees — up to this date" should be a total over time

  @rack_test
  Scenario: A fallback to zero is the term, noted
    Given the run produced "Fee" of "5000" for folio "101" computed by "@base + (capital_commitment.get_account_entry_or_zero('Carry', @end_date).amount_cents || 0)"
    And the run produced "Base" of "5000" for folio "101"
    When I open the explanation of "Fee" for folio "101"
    Then term "Carry" should say "zero when there is none"

  @rack_test
  Scenario: A name held by several entries on the date is not pinned to one of them
    Given the run produced "Portfolio FMV" of "30000" for folio "101"
    And the run produced "Portfolio FMV" of "70000" for folio "101"
    And the run produced "Total FMV" of "100000" for folio "101" computed by "@portfolio_fmv" recording:
      | expression     | value  |
      | @portfolio_fmv | 100000 |
    When I open the explanation of "Total FMV" for folio "101"
    Then term "Portfolio FMV (2 on this date)" should be a total over time
    And term "Portfolio FMV (2 on this date)" should not link to a single entry

  Scenario: Opening a total of the rule's own history does not list the entry itself
    Given the run produced "Fees" of "5000" for folio "101"
    And an earlier "Fees" entry of "3000" for folio "101" dated "2023-12-31"
    When I open the explanation of "Fees" for folio "101"
    And I open the total "Fees" since inception from it
    Then the total should not list the entry being explained

  Scenario: A total whose entries are chosen while the rule runs is not opened
    Given the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.since_inception(chosen_name, nil, @start_date, @end_date)"
    When I open the explanation of "Fee" for folio "101"
    Then term "A total chosen while the rule runs" should not open

  # ── Allocated shares ──────────────────────────────────────────────────────────

  @rack_test
  Scenario: An allocated entry shows the fund-level entry it is a share of
    Given the run produced a fund-level "Operating Cost" entry of "40000"
    And the run produced "Operating Cost" of "10000" for folio "101" allocated from the fund level computed by "fund_account_entry.amount_cents * 0.25"
    When I open the explanation of "Operating Cost" for folio "101"
    Then term "Operating Cost" should be a share of a fund total

  # The leak the first review caught: the fund-level entry a share came from has references of
  # its own, and the folio's references must resolve against the folio, not the fund.
  @rack_test
  Scenario: An allocated entry reads its references from its own folio, not from the fund
    Given the run produced a fund-level "Base" entry of "500000"
    And the run produced a fund-level "Operating Cost" entry of "40000" computed by "@base"
    And the run produced "Base" of "10000" for folio "101"
    And the run produced "Operating Cost" of "10000" for folio "101" allocated from the fund level computed by "@base"
    When I open the explanation of "Operating Cost" for folio "101"
    Then term "Base" should be worth "100.00"

  # ── Leaves ────────────────────────────────────────────────────────────────────

  Scenario: An uploaded entry has nothing to break down
    Given an uploaded "Bank Charges" entry of "5000" for folio "101"
    When I open the explanation of "Bank Charges" for folio "101"
    Then the explanation should say "not computed"

  Scenario: A rule that names its own entry does not open into itself
    Given the run produced "Circular" of "10000" for folio "101" computed by "@circular"
    When I open the explanation of "Circular" for folio "101"
    Then no term should be another entry

  # ── Permissions ───────────────────────────────────────────────────────────────
  # Opening a line walks into the fund's own formulas and fund-level entries.

  Scenario: An investor may not open the lines of the explanation
    Given the run produced "NAV" of "80000" for folio "101"
    And there is an investor user on the entity
    Then that investor should not be able to open the explanation's lines

  @rack_test
  Scenario: The fund's staff may open the lines of the explanation
    Given the run produced "NAV" of "80000" for folio "101"
    Then the company admin should be able to open the explanation's lines

  # ── Being honest ──────────────────────────────────────────────────────────────

  Scenario: A year is not money
    Given the run produced "Fee" of "5000" for folio "101" computed by "@end_date.year * 12" recording:
      | expression     | value |
      | @end_date.year | 2024  |
    When I open the explanation of "Fee" for folio "101"
    Then term "Year (end date)" should not be money

  Scenario: A rule that cannot be read says so rather than guessing
    Given the run produced "Fee" of "5000" for folio "101" computed by "this is ((( not ruby" with no breakdown
    When I open the explanation of "Fee" for folio "101"
    Then the explanation should say "could not be read"
