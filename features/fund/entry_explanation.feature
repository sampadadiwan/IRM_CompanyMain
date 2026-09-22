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

  Scenario: A named step opens into its own expression
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "22000" for folio "101" computed by "months = 12 - 1; @base * months / 50" recording:
      | expression | value |
      | months     | 11    |
    When I open the explanation of "Fee" for folio "101"
    Then term "Months" should show "11"
    And term "Months" should open into "12,1"

  Scenario: A rule that returns from inside an if is broken down from the branch it took
    Given the run produced "Base" of "100000" for folio "101"
    And the run produced "Fee" of "2000" for folio "101" computed by "if @base > 0; @base * 2 / 100; else; 0; end" recording:
      | expression        | value |
      | @base * 2 / 100   | 2000  |
    When I open the explanation of "Fee" for folio "101"
    Then the explanation should list "Base,2,100"

  # ── Reading other entries ─────────────────────────────────────────────────────

  Scenario: A same-period read by name is another entry
    Given the run produced "Opening Fee" of "5000" for folio "101"
    And the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.get_account_entry_or_zero('Opening Fee', @end_date).amount_cents"
    When I open the explanation of "Fee" for folio "101"
    Then term "Opening Fee" should be another entry

  Scenario: A read from an earlier period is named as such and not opened
    Given the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.get_account_entry_or_zero('Closing Fee', @start_date).amount_cents"
    When I open the explanation of "Fee" for folio "101"
    Then term "Closing Fee" should be from an earlier period
    And term "Closing Fee" should say "at the start of this period"

  Scenario: Summing this folio's entries of a name is a total that can be opened
    Given the run produced "Fee" of "5000" for folio "101" computed by "capital_commitment.account_entries.where(name: 'Audit Fees', reporting_date: ..@end_date).sum(:amount_cents)"
    When I open the explanation of "Fee" for folio "101"
    Then term "Audit Fees — up to this date" should be a total over time

  Scenario: A fallback to zero is the term, noted
    Given the run produced "Fee" of "5000" for folio "101" computed by "@base + (capital_commitment.get_account_entry_or_zero('Carry', @end_date).amount_cents || 0)"
    And the run produced "Base" of "5000" for folio "101"
    When I open the explanation of "Fee" for folio "101"
    Then term "Carry" should say "zero when there is none"

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

  Scenario: An allocated entry shows the fund-level entry it is a share of
    Given the run produced a fund-level "Operating Cost" entry of "40000"
    And the run produced "Operating Cost" of "10000" for folio "101" allocated from the fund level computed by "fund_account_entry.amount_cents * 0.25"
    When I open the explanation of "Operating Cost" for folio "101"
    Then term "Operating Cost" should be a share of a fund total

  # The leak the first review caught: the fund-level entry a share came from has references of
  # its own, and the folio's references must resolve against the folio, not the fund.
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
