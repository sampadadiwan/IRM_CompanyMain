Feature: Class-only expenses — two named ledger entries charged to one class
  Worked examples H4–H6, E14–E24, X1–X7 — openspec/changes/evergreen-share-classes/design.md#worked-examples
  Class A and Class B each hold 50,000 units at ₹10,000 (₹50 Cr) on 30 Sep. The shared pool is the
  portfolio fair value, so a payment from cash shows as a smaller pool on the next NAV.

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"

  # H4 — Happy path: ₹40,00,000 booked to "Class B Servicing Fee" comes off Class B only — B shows class expenses payable ₹40,00,000 with its source and ₹9,920 a unit; A stays ₹10,000.
  Scenario: An expense charged to one class
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-20"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "B" NAV for "2026-10-31"
    Then the NAV line "class_expenses_payable" shows the note "Class B Servicing Fee"
    And the class "B" NAV for "2026-10-31" should be:
      | class_expenses_payable_cents | 40,00,000 |
      | nav_per_unit_cents           | 9,920     |
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # H5 — Happy path: Class B then pays its ₹40,00,000 from cash (pool ₹100 Cr → ₹99.6 Cr); its payable falls to ₹0, its stake by the same amount, so B stays ₹9,920 a unit and A ₹10,000.
  @rack_test
  Scenario: Paying a class expense leaves every class's NAV unchanged
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "9,920", units "50000" and lines:
      | class_expenses_payable | 40,00,000 |
    And the fund ledger has "Class B Servicing Fee Paid" of "40,00,000" on "2026-11-10"
    And the portfolio fair value is "99,60,00,000"
    When the NAV for "2026-11-30" is drafted
    Then the class "B" NAV for "2026-11-30" should be:
      | class_expenses_payable_cents | 0     |
      | nav_per_unit_cents           | 9,920 |
    And the class "A" NAV for "2026-11-30" should be:
      | nav_per_unit_cents | 10,000 |

  # H6 — Happy path: the GP names Class B's two expense entries under Customise this class and saves; both are stored on Class B.
  @rack_test
  Scenario: Name a class's expense entries in the settings
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And I save the evergreen settings
    Then I should see "Settings saved"
    And class "B" should use expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"

  # E14 — Edge case: ₹40,00,000 expensed and paid within October leaves Class B owing nothing, but its NAV still falls by the expense through its stake — ₹9,920 a unit; A ₹10,000.
  @rack_test
  Scenario: Expensed and paid in the same month
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-10"
    And the fund ledger has "Class B Servicing Fee Paid" of "40,00,000" on "2026-10-20"
    And the portfolio fair value is "99,60,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "B" NAV for "2026-10-31" should be:
      | class_expenses_payable_cents | 0     |
      | nav_per_unit_cents           | 9,920 |
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E15 — Edge case: ₹50,00,000 paid against ₹40,00,000 owed leaves Class B ₹10,00,000 in credit (payable −₹10,00,000) and its NAV unchanged at ₹9,920; Class A is untouched at ₹10,000.
  @rack_test
  Scenario: An overpaid class expense stays on that class
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "9,920", units "50000" and lines:
      | class_expenses_payable | 40,00,000 |
    And the fund ledger has "Class B Servicing Fee Paid" of "50,00,000" on "2026-11-10"
    And the portfolio fair value is "99,50,00,000"
    When the NAV for "2026-11-30" is drafted
    Then the class "B" NAV for "2026-11-30" should be:
      | class_expenses_payable_cents | -10,00,000 |
      | nav_per_unit_cents           | 9,920      |
    And the class "A" NAV for "2026-11-30" should be:
      | nav_per_unit_cents | 10,000 |

  # E16 — Edge case: Class A names no expense entries, so its NAV page shows no class expenses row at all.
  Scenario: A class without its own entries shows no class expenses line
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    Then the NAV page should not show the line "class_expenses_payable"

  # E17 — Edge case: an expense dated on the NAV date (31 Oct, ₹40,00,000) is counted; one dated the day after (1 Nov, ₹25,00,000) is not.
  @rack_test
  Scenario: Only expenses on or before the NAV date count
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-31"
    And the fund ledger has "Class B Servicing Fee" of "25,00,000" on "2026-11-01"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "B" NAV for "2026-10-31" should be:
      | class_expenses_payable_cents | 40,00,000 |
      | nav_per_unit_cents           | 9,920     |

  # E18 — Edge case: a −₹40,00,000 reversal of the October expense brings Class B's payable back to ₹0 and its NAV back to ₹10,000 a unit.
  @rack_test
  Scenario: A reversal entry cancels a class expense
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "9,920", units "50000" and lines:
      | class_expenses_payable | 40,00,000 |
    And the fund ledger has "Class B Servicing Fee" of "-40,00,000" on "2026-11-05"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-11-30" is drafted
    Then the class "B" NAV for "2026-11-30" should be:
      | class_expenses_payable_cents | 0      |
      | nav_per_unit_cents           | 10,000 |

  # E19 — Edge case: Class B's class expenses payable is overridden to ₹35,00,000 with reason "per admin"; drafting again keeps the override.
  Scenario: An override of class expenses payable survives a re-draft
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-20"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "B" NAV for "2026-10-31"
    And I override the NAV line "Class expenses payable" to "35,00,000" with reason "per admin"
    And the NAV for "2026-10-31" is drafted
    Then the class "B" NAV for "2026-10-31" should be:
      | class_expenses_payable_cents | 35,00,000 |

  # E20 — Edge case: an uploaded NAV for Class B is taken as given — no class expenses line is added even though Class B names its entries and has ₹40,00,000 booked.
  @rack_test
  Scenario: An uploaded NAV gets no class expenses line
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-20"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV          | Units Outstanding | NAV Per Unit |
      | B          | 2026-10-31 | 49,60,00,000 | 50,000            | 9,920        |
    Then the NAV upload should have "0" failed rows
    And the class "B" NAV for "2026-10-31" should be:
      | source                       | uploaded |
      | class_expenses_payable_cents | 0        |

  # E21 — Edge case: the expense was booked on 20 Oct, before Class B named its entries; the window is by entry date, so the 31 Oct NAV still charges it — ₹40,00,000 payable.
  @rack_test
  Scenario: Expenses booked before the entries were named still count
    Given the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-20"
    And class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "B" NAV for "2026-10-31" should be:
      | class_expenses_payable_cents | 40,00,000 |

  # E22 — Edge case: "Class C Legal" is in the ledger but no class uses it — the NAV warns "Ledger entry 'Class C Legal' looks class-specific but no class uses it — name it on the class or it is ignored"; once Class B names it and the NAV is drafted again, the warning goes.
  Scenario: An unclaimed class-looking ledger entry is flagged until a class names it
    Given the fund ledger has "Class C Legal" of "5,00,000" on "2026-10-15"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "Ledger entry 'Class C Legal' looks class-specific but no class uses it — name it on the class or it is ignored"
    Given class "B" uses expense entries "Class C Legal" and "Class C Legal Paid"
    When the NAV for "2026-10-31" is drafted
    And I open the class "A" NAV for "2026-10-31"
    Then I should not see "looks class-specific"

  # E23 — Edge case: a fund-wide entry named "Class Action Settlement" is flagged too (harmless), and the NAV figures are unaffected — A and B stay ₹10,000 a unit.
  Scenario: A fund-wide entry whose name starts with "Class" is flagged but changes nothing
    Given the fund ledger has "Class Action Settlement" of "1,00,000" on "2026-10-15"
    And the portfolio fair value is "100,00,00,000"
    When I draft the NAV for "2026-10-31"
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "Ledger entry 'Class Action Settlement' looks class-specific"
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E24 — Edge case: a class expense booked after the NAV was drafted (dated before the NAV date) flags the draft as out of date.
  @rack_test
  Scenario: A class expense added after drafting makes the NAV out of date
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    And the fund ledger has "Class B Servicing Fee" of "40,00,000" on "2026-10-25"
    And I open the class "B" NAV for "2026-10-31"
    Then I should see "Inputs changed since drafted"

  # X1 — Error case: naming only the class expenses entry is refused — "Class B needs both a class expenses entry and a class expenses paid entry, or neither".
  @rack_test
  Scenario: Naming only one of the two entries is refused
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "Class B Servicing Fee" and ""
    And I save the evergreen settings
    Then I should see "Class B needs both a class expenses entry and a class expenses paid entry, or neither"

  # X2 — Error case: Class B naming Class A's entry is refused — "Class B's expense entry 'Class A Servicing Fee' is already used by Class A — each class needs its own entries".
  @rack_test
  Scenario: Another class's entry is refused
    Given class "A" uses expense entries "Class A Servicing Fee" and "Class A Servicing Fee Paid"
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "Class A Servicing Fee" and "Class B Servicing Fee Paid"
    And I save the evergreen settings
    Then I should see "Class B's expense entry 'Class A Servicing Fee' is already used by Class A — each class needs its own entries"

  # X3 — Error case: a fund ledger setting cannot be a class's entry — "Class B's expense entry 'Cash In Hand' is already one of the fund's ledger settings".
  @rack_test
  Scenario: A fund ledger setting is refused as a class entry
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "Cash In Hand" and "Class B Servicing Fee Paid"
    And I save the evergreen settings
    Then I should see "Class B's expense entry 'Cash In Hand' is already one of the fund's ledger settings"

  # X4 — Error case: a 126-character entry name sent directly (past the form's limit) is refused — "Class expenses entry is too long (maximum is 125 characters)".
  @rack_test
  Scenario: A name over 125 characters is refused
    When class "B" expense entries are set to a 126-character name directly
    Then the settings should be refused with "Class expenses entry is too long (maximum is 125 characters)"

  # X5 — Error case: clearing Class B's entries while its latest NAV still carries ₹40,00,000 is refused — "Class B still owes ₹40,00,000.00 of class expenses on its latest NAV — pay or reverse it before removing its expense entries".
  @rack_test
  Scenario: Entries cannot be removed while the class still owes class expenses
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "9,920", units "50000" and lines:
      | class_expenses_payable | 40,00,000 |
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "" and ""
    And I save the evergreen settings
    Then I should see "Class B still owes ₹40,00,000.00 of class expenses on its latest NAV — pay or reverse it before removing its expense entries"

  # X6 — Error case: a ₹60 Cr Class B expense against its ₹50 Cr share would make Class B's NAV negative; the draft is refused and nothing is saved.
  @rack_test
  Scenario: A class expense that would make the NAV negative is refused
    Given class "B" uses expense entries "Class B Servicing Fee" and "Class B Servicing Fee Paid"
    And the fund ledger has "Class B Servicing Fee" of "60,00,00,000" on "2026-10-20"
    And the portfolio fair value is "100,00,00,000"
    Then drafting the NAV for "2026-10-31" is refused with "would be negative"

  # X7 — Error case: the same name for both entries is refused — "Class B's class expenses entry and class expenses paid entry must be different" (the payable would otherwise never move).
  @rack_test
  Scenario: The same entry for expenses and payments is refused
    When I open the evergreen settings of the fund
    And I set the expense entries of class "B" to "Class B Servicing Fee" and "Class B Servicing Fee"
    And I save the evergreen settings
    Then I should see "Class B's class expenses entry and class expenses paid entry must be different"
