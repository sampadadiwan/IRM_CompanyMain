# bulk-path-query-optimisation, phase 5 — formula import skips the sequence shift that would move nothing.
# Worked examples: openspec/changes/bulk-path-query-optimisation/business-rules.md (H5, E5, E6, E7)

@bulk_query @rack_test
Feature: Fund formula import skips empty sequence shifts
  Inserting a formula at sequence k makes room by moving every formula at k or above down one. When k is
  above every existing formula there is nothing to move, so that statement is skipped. The resulting
  order and sequence numbers must be exactly what they are today.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Beta Fund" for the entity
    And the fund has formulas at sequences "1, 2, 3"

  # H5 — Happy path: appending 4, 5, 6 keeps the sheet order and runs no shift
  Scenario: H5 Formulas appended after the existing ones are not shifted
    Given I count queries by call site
    When I import fund formulas at sequences "4, 5, 6"
    Then the fund formulas in order should be "Existing 1@1, Existing 2@2, Existing 3@3, New 1@4, New 2@5, New 3@6"
    And at most 0 statements containing "\"sequence\" + 1" came from "ImportFundFormula#save_row"

  # E5 — Edge case: a formula inserted at 2 still moves 2 and 3 down, as today
  Scenario: E5 A formula inserted before existing ones still shifts them
    When I import fund formulas at sequences "2"
    Then the fund formulas in order should be "Existing 1@1, New 1@2, Existing 2@3, Existing 3@4"

  # E6 — Edge case: three rows at the same sequence: the first lands at 4, the next two each push the
  # earlier ones down (4 -> 5 -> 6), exactly as acts_as_list orders them today
  Scenario: E6 Duplicate sequences in one sheet keep today's order
    When I import fund formulas at sequences "4, 4, 4"
    Then the fund formulas in order should be "Existing 1@1, Existing 2@2, Existing 3@3, New 3@4, New 2@5, New 1@6"

  # E7 — Edge case: a blank sequence is appended after the last formula, as today
  Scenario: E7 A formula with no sequence goes to the end
    When I import fund formulas at sequences ""
    Then the fund formulas in order should be "Existing 1@1, Existing 2@2, Existing 3@3, New 1@4"
