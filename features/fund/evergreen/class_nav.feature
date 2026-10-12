@rack_test
Feature: Each class's NAV — the shared lines are split by each class's stake
  Worked examples H1–H3, E1–E13 — openspec/changes/evergreen-share-classes/design.md#worked-examples
  The shared pool here is the portfolio fair value (no cash ledger), so a fee "paid from cash" is
  shown by a smaller pool on the next NAV.

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # H1 — Happy path: nothing owed, so the split is by value — A 60,000 units at ₹10,000 (₹60 Cr) and B 20,000 at ₹20,000 (₹40 Cr) share ₹110 Cr 60 : 40 — ₹11,000 and ₹22,000 a unit.
  Scenario: With nothing owed the split is by value
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 60000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 20000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "60000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "20,000" and units "20000"
    And the portfolio fair value is "110,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 11,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 22,000 |

  # H2 — Happy path: class A owes a ₹1 Cr management fee not yet paid (NAV ₹49 Cr, stake ₹50 Cr), B owes nothing (₹50 Cr); with nothing else changing, A stays ₹49 Cr (₹9,800 a unit) and B ₹50 Cr — not A ₹48.49 Cr / B ₹50.51 Cr as the old split gave.
  Scenario: An unpaid fee does not move value between classes
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,800", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 1,00,00,000 |
      | nav_per_unit_cents     | 9,800       |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # H3 — Happy path: A's ₹1 Cr fee is then paid from the shared cash (pool ₹100 Cr → ₹99 Cr); A's stake falls by the payment, so A stays ₹49 Cr with nothing owed and B stays ₹50 Cr.
  Scenario: Paying a fee from shared cash reduces only the owing class
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,800", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the fund ledger has "Management Fee Paid" of "1,00,00,000" on "2026-10-05"
    And the portfolio fair value is "99,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 0     |
      | nav_per_unit_cents     | 9,800 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E1 — Edge case: a one-class fund takes 100% of the shared lines — ₹102.2 Cr over 1,00,000 units is ₹10,220 a unit, as before.
  Scenario: One class takes everything
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 100000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,220 |

  # E2 — Edge case: new class C has no previous NAV, so its stake is its 1,000 units at the ₹10,000 starting price (₹1 Cr) beside A and B at ₹50 Cr each.
  Scenario: A new class's stake is its units at the starting price
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B,C"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
      | C Trust  | F-044 | C     | 1000  | 2026-10-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the portfolio fair value is "101,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "C" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E3 — Edge case: every class B unit was cancelled and its ₹10,00,000 fee paid since; B's stake would be −₹10,00,000, so it is held at zero and A keeps the whole ₹50 Cr pool (₹10,000 a unit).
  Scenario: A fully redeemed class's stake never goes below zero
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "9,980", units "50000" and lines:
      | mgmt_fee_payable | 10,00,000 |
    And folio "F-031" had "50000" units cancelled on "2026-10-15"
    And the fund ledger has "Management Fee Paid" of "10,00,000" on "2026-10-20"
    And the portfolio fair value is "50,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_cents              | 0 |
      | mgmt_fee_payable_cents | 0 |

  # E4 — Edge case: A issued 5,000 units after its previous NAV; its stake grows at the previous gross ₹10,200 a unit (₹50 Cr + ₹1 Cr owed over 50,000) — ₹10,200 × 55,000 = ₹56.1 Cr — so A is ₹55.1 Cr after its fee (₹10,018.1818 a unit) and B ₹50 Cr.
  Scenario: Units issued since the previous NAV join at the previous gross value
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And folio "F-012" was issued "5000" units on "2026-10-01"
    And the portfolio fair value is "106,10,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,018.1818 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E5 — Edge case: both previous NAVs were uploaded (no fee lines), so each stake is the uploaded NAV scaled for units — A ₹60 Cr × 66,000 ÷ 60,000 = ₹66 Cr, B ₹40 Cr — the same split as before the change.
  Scenario: Uploaded previous NAVs split as before
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 60000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 20000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "60000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "20,000" and units "20000"
    And folio "F-012" was issued "6000" units on "2026-10-01"
    And the portfolio fair value is "106,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 20,000 |

  # E6 — Edge case: ₹1.5 Cr paid when only A owed ₹1 Cr; the ₹50 lakh excess is shared by value at the previous NAV (A ₹49 Cr : B ₹50 Cr) as before, each stake falls by what was paid for it, and neither class gains — A ₹9,800, B ₹10,000 a unit.
  Scenario: An over-payment moves no value between classes
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,800", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the fund ledger has "Management Fee Paid" of "1,50,00,000" on "2026-10-05"
    And the portfolio fair value is "98,50,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 9,800 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E7 — Edge case: B crystallised a ₹20,00,000 performance fee on 30 Sep, still unpaid; it is counted in B's stake (₹49.8 Cr + ₹20 lakh = ₹50 Cr), so B stays ₹9,960 a unit with ₹20,00,000 payable and A ₹10,000.
  Scenario: A crystallised but unpaid performance fee does not drift
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "9,960", units "50000" and lines:
      | perf_fee_accrued | 20,00,000 |
      | crystallised     | true      |
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "B" NAV for "2026-10-31" should be:
      | perf_fee_payable_cents | 20,00,000 |
      | nav_per_unit_cents     | 9,960     |
    And the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E8 — Edge case: both classes owe ₹50 lakh (1% of NAV), so the stake split equals the old split — each class ₹49.5 Cr, ₹9,900 a unit.
  Scenario: Fees owed in proportion give the same result as before
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,900", units "50000" and lines:
      | mgmt_fee_payable | 50,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "9,900", units "50000" and lines:
      | mgmt_fee_payable | 50,00,000 |
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 9,900 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 9,900 |

  # E9 — Edge case: drafting 31 Oct under the new split leaves the approved 30 Sep NAV exactly as it was (₹9,800 a unit, ₹1 Cr payable).
  Scenario: Approved NAVs are not re-split
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,800", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the approved class "A" NAV for "2026-09-30" should still be:
      | nav_per_unit_cents     | 9,800        |
      | nav_cents              | 49,00,00,000 |
      | mgmt_fee_payable_cents | 1,00,00,000  |

  # E10 — Edge case: three equal classes share ₹100 Cr; each share rounds to 0.3333333333, the largest class takes the rounding remainder, and the three class NAVs add up to exactly ₹100 Cr.
  Scenario: Three classes add up to the pool exactly
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B,C"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
      | C Trust  | F-044 | C     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "C" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class NAVs for "2026-10-31" should add up to "100,00,00,000"
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 6,666.6667 |

  # E11 — Edge case: no class holds any units, so the ₹1 Cr pool is split equally — ₹50,00,000 each.
  Scenario: With no units anywhere the split is equal
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the portfolio fair value is "1,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_cents | 50,00,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_cents | 50,00,000 |

  # E12 — Edge case: A's 30 Sep management fee payable was overridden to ₹80,00,000; the stake adds back the overridden figure (₹49.2 Cr + ₹80 lakh = ₹50 Cr), so A stays ₹9,840 a unit and B ₹10,000.
  Scenario: An overridden fee line at the previous NAV is what the stake adds back
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,840", units "50000" and lines:
      | mgmt_fee_payable | 80,00,000        |
      | overridden       | mgmt_fee_payable |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 9,840 |
    And the class "B" NAV for "2026-10-31" should be:
      | nav_per_unit_cents | 10,000 |

  # E13 — Edge case: a fee payment dated on the previous NAV date (30 Sep) belongs to that NAV and is not counted again — A still owes ₹1 Cr and stays ₹9,800 a unit.
  Scenario: A payment on the previous NAV date is not counted again
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,800", units "50000" and lines:
      | mgmt_fee_payable | 1,00,00,000 |
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And the fund ledger has "Management Fee Paid" of "1,00,00,000" on "2026-09-30"
    And the portfolio fair value is "100,00,00,000"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 1,00,00,000 |
      | nav_per_unit_cents     | 9,800       |
