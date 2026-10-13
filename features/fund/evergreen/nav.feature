Feature: Evergreen NAV — draft, override, upload, approve, reopen, staleness
  Worked examples H3, H4, H5, H6, E7, E8, E9, E10, E11, E71, E120–E126, X5, X6, X7, X8, X9, X70–X80 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # H3 — Happy path: a single-class draft reads fair value, ledger cash and liabilities, and gives NAV ₹102,70,00,000 = ₹10,270.00 a unit.
  Scenario: Draft a NAV from CapHive data
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor   | folio | class | units  | issued     |
      | A Ltd      | F-012 | A     | 12000  | 2025-09-01 |
      | B LLP      | F-031 | A     | 7000   | 2025-09-01 |
      | C HUF      | F-044 | A     | 2000   | 2025-09-01 |
      | D Partners | F-050 | A     | 4000   | 2025-09-01 |
      | Others     | F-099 | A     | 75000  | 2025-09-01 |
    And the portfolio fair value is "95,00,00,000"
    And the fund ledger has "Cash In Hand" of "8,00,00,000" on "2026-10-31"
    And the fund ledger has "Other Liabilities" of "30,00,000" on "2026-10-31"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | status                  | draft         |
      | source                  | computed      |
      | investments_fmv_cents   | 95,00,00,000  |
      | cash_cents              | 8,00,00,000   |
      | other_liabilities_cents | 30,00,000     |
      | nav_cents               | 102,70,00,000 |
      | units_outstanding       | 100000        |
      | nav_per_unit_cents      | 10,270        |
    And the NAV per unit shown is "10,270.00"
    And the NAV line "cash" shows the note "Ledger balance \"Cash In Hand\""

  # H4 — Happy path: overriding the management fee payable with a reason recomputes NAV to ₹102,20,00,000 and shows the reason on the line.
  Scenario: Override a line with a reason
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "95,00,00,000"
    And the fund ledger has "Cash In Hand" of "8,00,00,000" on "2026-10-31"
    And the fund ledger has "Other Liabilities" of "30,00,000" on "2026-10-31"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Management fee payable" to "50,00,000" with reason "per admin stmt"
    Then I should see "Line overridden"
    And the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 50,00,000     |
      | nav_cents              | 102,20,00,000 |
      | nav_per_unit_cents     | 10,220        |
    And the NAV line "mgmt_fee_payable" shows the note "Overridden per admin stmt"
    And the NAV per unit shown is "10,220.00"

  # H5 — Happy path: an administrator's NAV row uploads as a draft with source "uploaded" and its own NAV per unit.
  @rack_test
  Scenario: Upload an administrator's NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV          | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 98,25,98,930.50 | 98,450         | 9,980.69     |
    Then the NAV upload should have "0" failed rows
    And the class "A" NAV for "2026-09-30" should be:
      | status             | draft    |
      | source             | uploaded |
      | nav_per_unit_cents | 9,980.69 |

  # X7 — Error case: an upload row whose NAV ÷ units differs from its NAV per unit by more than 0.01 is rejected.
  @rack_test
  Scenario: An inconsistent upload row is rejected
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV          | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 98,26,00,000 | 98,450            | 9,980.40     |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "NAV per unit does not equal NAV ÷ units outstanding"

  # H6 — Happy path: a colleague with the approver role approves the draft.
  Scenario: A colleague approves the NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-10-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-10-31"
    And I approve the NAV
    Then I should see "NAV approved"
    And the class "A" NAV for "2026-10-31" should be:
      | status | approved |

  # X8 — Error case: without the approver role the Approve button is hidden and a direct request is refused.
  Scenario: Without the approver role a NAV can't be approved
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    Then I should not be able to approve the NAV
    When the preparer tries to approve the NAV directly
    Then the approval is refused with "Only an approver can approve a NAV"

  # E71 — Edge case: in a small fund an approver approves the NAV they prepared; it is approved and the audit trail notes it.
  Scenario: An approver approves the NAV they prepared
    Given the user has role "approver"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    And I approve the NAV
    Then the class "A" NAV for "2026-10-31" should be:
      | status | approved |
    And the NAV audit trail for class "A" on "2026-10-31" should note "approver also prepared this NAV"

  # X5 — Error case: a holding with no valuation on or before the NAV date stops the draft and names the company.
  Scenario: A missing valuation stops the draft
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "Pharma Co" has no valuation on or before "2026-10-31"
    When I draft the NAV for "2026-10-31"
    Then I should see "No valuation for Pharma Co on or before"
    And I should see "add one or upload the NAV"

  # X6 — Error case: an override with a blank reason is not saved.
  Scenario: An override needs a reason
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Cash" to "1,00,000" with reason ""
    Then I should see "Reason can't be blank"

  # E7 — Edge case: two classes split fund-wide lines by value at the previous NAV per unit (80 % / 20 %).
  Scenario: Two classes split fund-wide lines by value at the previous price
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 80000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 20000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "20000"
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_cents   | 81,76,00,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_cents | 20,44,00,000 |

  # E8 — Edge case: a class with no units outstanding shows its initial price ₹10,000.00 as NAV per unit.
  Scenario: A class with no units uses its initial price
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "B" NAV for "2026-10-31"
    Then I should see "No units outstanding — initial price"
    And the NAV per unit shown is "10,000.00"

  # E9 — Edge case: an approved NAV no dealing date used can be reopened to draft.
  Scenario: Reopen an unused approved NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-10-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-10-31"
    And I approve the NAV
    And I reopen the NAV
    Then I should see "NAV reopened"
    And the class "A" NAV for "2026-10-31" should be:
      | status | draft |

  # X9 — Error case: a NAV priced into a confirmed dealing date cannot be reopened.
  Scenario: A NAV used by a dealing date cannot be reopened
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-10-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-10-31"
    And I approve the NAV
    And a confirmed dealing date on "2026-11-02" priced at that NAV
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "Used by dealing date 02/11/2026 — cannot reopen"

  # E10 — Edge case: a ledger entry dated before the NAV date, added after drafting, marks the draft stale.
  Scenario: A draft becomes stale when its inputs change
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And a portfolio input dated "2026-10-30" changes
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "Inputs changed since drafted"

  # E11 — Edge case: a unit added after approval flags the approved NAV but leaves its values unchanged.
  Scenario: An approved NAV keeps its values when inputs change
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-10-31"
    And the approver logs in
    And I open the class "A" NAV for "2026-10-31"
    And I approve the NAV
    And a fund unit dated "2026-10-15" is added
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "Inputs changed after approval"
    And the class "A" NAV for "2026-10-31" should be:
      | nav_cents | 102,20,00,000 |

  # ---- Edge cases (E120–E128, X70–X80) ----

  # E120 — Edge case: upload rows whose NAV ÷ units is exactly 0.01 above or below the NAV per unit are within tolerance and accepted.
  @rack_test
  Scenario: Upload rows at exactly the 0.01 tolerance are accepted
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV         | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 1,00,00,100 | 1,000             | 10,000.09    |
      | A          | 2026-10-31 | 1,00,00,100 | 1,000             | 10,000.11    |
    Then the NAV upload should have "0" failed rows
    And the class "A" NAV for "2026-09-30" should be:
      | source             | uploaded  |
      | nav_per_unit_cents | 10,000.09 |
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000.11 |

  # X70 — Error case: an upload row 0.011 off (NAV ÷ units 10,000.101 vs 10,000.09) is just past the tolerance and rejected; its valid neighbour still loads.
  @rack_test
  Scenario: An upload row just past the tolerance is rejected
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV         | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 1,00,00,100 | 1,000             | 10,000.10    |
      | A          | 2026-10-31 | 1,00,00,101 | 1,000             | 10,000.09    |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "NAV per unit does not equal NAV ÷ units outstanding (10000.09 vs 10000.101)"
    And the class "A" NAV for "2026-09-30" should be:
      | nav_per_unit_cents | 10,000.10 |
    And there should be no class "A" NAV for "2026-10-31"

  # X71 — Error case: an upload row with zero units outstanding cannot be checked (no division) and is rejected.
  @rack_test
  Scenario: An upload row with zero units is rejected
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 0   | 0                 | 10,000       |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "NAV per unit does not equal NAV ÷ units outstanding (10000.0 vs no units)"
    And there should be no class "A" NAV for "2026-09-30"

  # X72 — Error case: an upload row naming a class the fund does not have is rejected with the class named.
  @rack_test
  Scenario: An upload row for an unknown class is rejected
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV          | Units Outstanding | NAV Per Unit |
      | B          | 2026-09-30 | 10,00,00,000 | 10,000            | 10,000       |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "B is not a unit class of Alpha Long-Short Fund"
    And there should be no class "B" NAV for "2026-09-30"

  # X73 — Error case: uploading over an approved NAV is refused ("reopen it first") and the approved NAV keeps its values.
  @rack_test
  Scenario: An upload cannot replace an approved NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "100000"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV             | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 98,25,98,930.50 | 98,450            | 9,980.69     |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "An approved NAV exists for A on 2026-09-30 — reopen it first"
    And the class "A" NAV for "2026-09-30" should be:
      | status             | approved |
      | source             | uploaded |
      | nav_per_unit_cents | 10,000   |

  # E121 — Edge case: re-uploading over a computed draft (with an override) replaces it with the uploaded totals, zeroes its lines and drops the override; a second upload for the same date updates that one row.
  Scenario: Re-uploading a date replaces the draft in place
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Cash" to "1,00,000" with reason "bank stmt"
    Then I should see "Line overridden"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV           | Units Outstanding | NAV Per Unit |
      | A          | 2026-10-31 | 102,00,00,000 | 1,00,000          | 10,200       |
    Then the NAV upload should have "0" failed rows
    And the class "A" NAV for "2026-10-31" should be:
      | status                | draft         |
      | source                | uploaded      |
      | investments_fmv_cents | 0             |
      | cash_cents            | 0             |
      | nav_cents             | 102,00,00,000 |
      | nav_per_unit_cents    | 10,200        |
    And the class "A" NAV for "2026-10-31" should have no overrides
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV           | Units Outstanding | NAV Per Unit |
      | A          | 2026-10-31 | 102,10,00,000 | 1,00,000          | 10,210       |
    Then the NAV upload should have "0" failed rows
    And there should be 1 class "A" NAV for "2026-10-31"
    And the class "A" NAV for "2026-10-31" should be:
      | nav_cents          | 102,10,00,000 |
      | nav_per_unit_cents | 10,210        |

  # E122 — Edge case: an override reason of exactly 255 characters (the maximum) is saved and NAV is recomputed (₹102,20,00,000 + ₹1,00,000 cash = ₹102,21,00,000).
  Scenario: A 255-character override reason is accepted
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Cash" to "1,00,000" with a reason of 255 characters
    Then I should see "Line overridden"
    And the "cash" override of the class "A" NAV for "2026-10-31" should have a 255-character reason
    And the class "A" NAV for "2026-10-31" should be:
      | cash_cents         | 1,00,000      |
      | nav_cents          | 102,21,00,000 |
      | nav_per_unit_cents | 10,221        |

  # X74 — Error case: a direct override with a 256-character reason (one over the maximum) is refused and the line is unchanged.
  Scenario: A 256-character override reason is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And the preparer tries to override line "cash" of the class "A" NAV for "2026-10-31" to "1,00,000" with a reason of 256 characters directly
    Then the request is refused with "Reason is too long (maximum is 255 characters)"
    And the class "A" NAV for "2026-10-31" should have no overrides
    And the class "A" NAV for "2026-10-31" should be:
      | cash_cents | 0             |
      | nav_cents  | 102,20,00,000 |

  # E123 — Edge case: an overridden line survives a re-draft of the same date; the overridden cash ₹1,00,000 and its reason are kept (NAV ₹102,21,00,000).
  Scenario: An override survives a re-draft
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Cash" to "1,00,000" with reason "bank stmt"
    And I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | status             | draft         |
      | cash_cents         | 1,00,000      |
      | nav_cents          | 102,21,00,000 |
      | nav_per_unit_cents | 10,221        |
    When I open the class "A" NAV for "2026-10-31"
    Then the NAV line "cash" shows the note "Overridden bank stmt"

  # X75 — Error case: an uploaded NAV has no lines, so it offers no override form and a direct override is refused.
  @rack_test
  Scenario: An uploaded NAV refuses overrides
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV             | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 98,25,98,930.50 | 98,450            | 9,980.69     |
    And I open the class "A" NAV for "2026-09-30"
    Then I should not be able to override the NAV
    When the preparer tries to override line "cash" of the class "A" NAV for "2026-09-30" to "1,00,000" with reason "fix" directly
    Then the request is refused with "An uploaded NAV has no lines to override — upload a corrected NAV instead"
    And the class "A" NAV for "2026-09-30" should be:
      | nav_per_unit_cents | 9,980.69 |

  # X76 — Error case: an approved NAV is read-only — no override form, and a direct override is refused.
  @rack_test
  Scenario: An approved NAV refuses overrides
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2026-10-31" is drafted and approved
    And I open the class "A" NAV for "2026-10-31"
    Then I should not be able to override the NAV
    When the approver tries to override line "cash" of the class "A" NAV for "2026-10-31" to "1,00,000" with reason "late cash" directly
    Then the request is refused with "Only a draft NAV can be edited"
    And the class "A" NAV for "2026-10-31" should be:
      | status    | approved      |
      | nav_cents | 102,20,00,000 |

  # E124 — Edge case: an approver who prepared the draft and overrode a line approves it; the audit trail records the override and both notes.
  Scenario: An approver who overrode a line approves it, and the trail says so
    Given the user has role "approver"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And I override the NAV line "Cash" to "1,00,000" with reason "bank stmt"
    And I approve the NAV
    Then the class "A" NAV for "2026-10-31" should be:
      | status    | approved      |
      | nav_cents | 102,21,00,000 |
    And the NAV audit trail for class "A" on "2026-10-31" should note "Overrode cash: bank stmt"
    And the NAV audit trail for class "A" on "2026-10-31" should note "approver also prepared this NAV"
    And the NAV audit trail for class "A" on "2026-10-31" should note "approver also overrode cash"

  # X77 — Error case: approving an already approved NAV again (a second click or direct request) is refused, so it can't crystallise twice.
  @rack_test
  Scenario: An approved NAV cannot be approved again
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2026-10-31" is drafted and approved
    And the approver tries to approve the class "A" NAV for "2026-10-31" directly
    Then the request is refused with "This NAV is already approved"

  # X78 — Error case: a user without the approver role sees no Reopen button and a direct reopen is refused; the NAV stays approved.
  @rack_test
  Scenario: Without the approver role a NAV can't be reopened
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2026-10-31" is drafted and approved
    And I open the class "A" NAV for "2026-10-31"
    Then I should not be able to reopen the NAV
    When the preparer tries to reopen the class "A" NAV for "2026-10-31" directly
    Then the request is refused with "Only an approver can reopen a NAV"
    And the class "A" NAV for "2026-10-31" should be:
      | status | approved |

  # X79 — Error case: reopening a NAV that is still a draft (out-of-order transition) is refused.
  Scenario: A draft NAV cannot be reopened
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And there is an approver "Ravi" in the entity
    When I draft the NAV for "2026-10-31"
    And the approver tries to reopen the class "A" NAV for "2026-10-31" directly
    Then the request is refused with "Only an approved NAV can be reopened"
    And the class "A" NAV for "2026-10-31" should be:
      | status | draft |

  # X80 — Error case: drafting a date that already has an approved NAV is refused ("reopen it to recalculate") and the approved values stay.
  Scenario: Drafting over an approved NAV is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When the class "A" NAV for "2026-10-31" is drafted and approved
    Given the portfolio fair value is "110,00,00,000"
    When I draft the NAV for "2026-10-31"
    Then I should see "An approved NAV exists for"
    And I should see "reopen it to recalculate"
    And the class "A" NAV for "2026-10-31" should be:
      | status    | approved      |
      | nav_cents | 102,20,00,000 |

  # E125 — Edge case: two classes with equal units but different previous prices (₹12,000 and ₹8,000) split fair value 60 % / 40 % by value, not 50 / 50 by units.
  Scenario: Classes split by value at the previous price, not by unit count
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "12,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "8,000" and units "50000"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | investments_fmv_cents | 60,00,00,000 |
      | nav_cents             | 60,00,00,000 |
      | nav_per_unit_cents    | 12,000       |
    And the class "B" NAV for "2026-10-31" should be:
      | investments_fmv_cents | 40,00,00,000 |
      | nav_cents             | 40,00,00,000 |
      | nav_per_unit_cents    | 8,000        |

  # E126 — Edge case: on the first NAV of two classes (no previous NAV) the split uses each class's initial price — A 1,00,000 × ₹10,000 and B 50,000 × ₹20,000 are equal, so 50 / 50.
  Scenario: The first NAV of each class splits by initial price
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And class "B" of the fund has "initial_price=20000"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 100000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000  | 2025-09-01 |
    And the portfolio fair value is "200,00,00,000"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_cents          | 100,00,00,000 |
      | nav_per_unit_cents | 10,000        |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_cents          | 100,00,00,000 |
      | nav_per_unit_cents | 20,000        |

  # X116 — Error case: an upload file listing Class A on 31 October 2026 twice (₹10,200 and ₹10,210) is refused as a whole — which row is right can't be guessed — and no NAV is saved.
  @rack_test
  Scenario: An upload with the same class and date twice is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV            | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | 1,00,00,00,000 | 1,00,000          | 10,000       |
      | A          | 2026-10-31 | 1,02,00,00,000 | 1,00,000          | 10,200       |
      | A          | 2026-10-31 | 1,02,10,00,000 | 1,00,000          | 10,210       |
    Then the NAV upload should be refused with "Class A on 31 October 2026 appears more than once"
    And there should be no class "A" NAV for "2026-10-31"
    And there should be no class "A" NAV for "2026-09-30"

  # X117 — Error case: a negative NAV (liabilities above assets) is refused on every path — drafting from a −₹1,00,000 fair value, an override of liabilities to ₹103,00,00,000 against ₹102,20,00,000 of assets, and an upload row of −₹1,00,000.
  Scenario: A negative NAV is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | Others   | F-099 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "-1,00,000"
    When I draft the NAV for "2026-10-31"
    Then I should see "The NAV for Class A on 31 October 2026 would be negative"
    And there should be no class "A" NAV for "2026-10-31"
    Given the portfolio fair value is "102,20,00,000"
    When I draft the NAV for "2026-10-31"
    And the admin tries to override line "other_liabilities" of the class "A" NAV for "2026-10-31" to "1030000000" with reason "test" directly
    Then the request is refused with "The NAV for Class A on 31 October 2026 would be negative (₹-80,00,000.00) — liabilities exceed assets; check the valuations and ledger balances"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV       | Units Outstanding | NAV Per Unit |
      | A          | 2026-09-30 | -1,00,000 | 1,000             | -100         |
    Then the NAV upload should have "1" failed rows
    And the NAV upload results should mention "would be negative"
