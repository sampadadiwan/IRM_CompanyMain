Feature: Evergreen NAV — fee payments by class, and money for orders not yet dealt
  Decided 8 Oct 2026 (docs/modules/funds/evergreen_design_decisions.md).
  Worked examples E197–E205 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # E197 — Edge case: only class A owed a ₹2 Cr performance fee; when the fund pays it, A stays ₹48 Cr (₹960 a unit) and B ₹50 Cr (₹1,000) — not A ₹46.98 Cr / B ₹51.02 Cr as a split by value would give.
  @rack_test
  Scenario: A fee payment settles the class that owed it
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 500000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 500000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "960", units "500000" and payables:
      | perf_fee_payable_cents | 2,00,00,000 |
    And an approved NAV for class "B" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | perf_fee_payable_cents | 0 |
    And the portfolio fair value is "98,00,00,000"
    And the fund ledger has "Performance Fee Paid" of "2,00,00,000" on "2027-01-15"
    When the NAV for "2027-01-31" is drafted
    Then the class "A" NAV for "2027-01-31" should be:
      | perf_fee_payable_cents | 0 |
      | nav_per_unit_cents | 960          |
    And the class "B" NAV for "2027-01-31" should be:
      | perf_fee_payable_cents | 0 |
      | nav_per_unit_cents | 1,000        |

  # E198 — Edge case: a ₹6,00,000 part payment of management fees owed A ₹9,00,000 and B ₹3,00,000 is split 9 : 3 — A ₹4,50,000 and B ₹1,50,000 — leaving A ₹4,50,000 and B ₹1,50,000 owed.
  @rack_test
  Scenario: A part payment is split by what each class owes
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 500000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 500000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 9,00,000 |
    And an approved NAV for class "B" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 3,00,000 |
    And the portfolio fair value is "100,00,00,000"
    And the fund ledger has "Management Fee Paid" of "6,00,000" on "2027-01-15"
    When the NAV for "2027-01-31" is drafted
    Then the class "A" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | 4,50,000 |
    And the class "B" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | 1,50,000 |

  # E199 — Edge case: ₹15,00,000 paid against ₹12,00,000 owed (A ₹9,00,000, B ₹3,00,000) settles both; the extra ₹3,00,000 is split by value (₹50 Cr each, 50 : 50), so each class shows ₹1,50,000 paid in advance (payable −₹1,50,000).
  @rack_test
  Scenario: An over-payment's excess is split by value share
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 500000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 500000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 9,00,000 |
    And an approved NAV for class "B" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 3,00,000 |
    And the portfolio fair value is "100,00,00,000"
    And the fund ledger has "Management Fee Paid" of "15,00,000" on "2027-01-15"
    When the NAV for "2027-01-31" is drafted
    Then the class "A" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | -1,50,000 |
    And the class "B" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | -1,50,000 |

  # E200 — Edge case: a ₹1,00,000 fee payment when no class owes anything is split by value (50 : 50) — ₹50,000 each, as before the change.
  @rack_test
  Scenario: A payment when nothing is owed is split by value share
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units  | issued     |
      | A Ltd    | F-012 | A     | 500000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 500000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 0 |
    And an approved NAV for class "B" on "2026-12-31" with NAV per unit "1,000", units "500000" and payables:
      | mgmt_fee_payable_cents | 0 |
    And the portfolio fair value is "100,00,00,000"
    And the fund ledger has "Management Fee Paid" of "1,00,000" on "2027-01-15"
    When the NAV for "2027-01-31" is drafted
    Then the class "A" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | -50,000 |
    And the class "B" NAV for "2027-01-31" should be:
      | mgmt_fee_payable_cents | -50,000 |

  # E201 — Edge case: P's ₹5 Cr, paid on 25 Oct for the 2 Nov dealing date, is in the 31 Oct bank balance but held on its own line — NAV ₹102,20,00,000, ₹10,220 a unit (not ₹10,720) — so P gets 4,892.3679 units on 2 Nov.
  @rack_test
  Scenario: Money paid in advance is kept out of the NAV until the units are issued
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And the portfolio fair value is "102,20,00,000"
    And the fund ledger has "Cash In Hand" of "5,00,00,000" on "2026-10-25"
    And today is "2026-11-01"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | cash_cents                | 5,00,00,000    |
      | dealing_in_progress_cents | 5,00,00,000    |
      | nav_cents                 | 102,20,00,000  |
      | nav_per_unit_cents        | 10,220         |
    And the class "A" NAV for "2026-10-31" should list "P Family Trust — subscription" as money for orders not yet dealt
    When the class "A" NAV for "2026-10-31" is drafted and approved
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    Then the units of "P Family Trust" on "2026-11-02" should be "4,892.3679" dated "2026-11-02"

  # E202 — Edge case: A Ltd's 1,000 units, dealt on 2 Nov at ₹10,220 but paid only on 3 Dec, are no longer counted on the 30 Nov NAV and their ₹1,02,20,000 payout is held on the line — 99,000 units, NAV ₹101,17,80,000, still ₹10,220 a unit.
  @rack_test
  Scenario: A dealt but unpaid redemption is held until it is paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "99000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-12-01"
    When the NAV for "2026-11-30" is drafted
    Then the class "A" NAV for "2026-11-30" should be:
      | units_outstanding         | 99,000         |
      | dealing_in_progress_cents | 1,02,20,000    |
      | nav_cents                 | 101,17,80,000  |
      | nav_per_unit_cents        | 10,220         |
    And the class "A" NAV for "2026-11-30" should list "A Ltd — redemption dealt" as money for orders not yet dealt

  # E203 — Edge case: P's ₹5 Cr advance is for class B, so it sits on class B's line only — class A (₹50 Cr) and class B (₹50 Cr) both stay at ₹10,000 a unit.
  @rack_test
  Scenario: Advance money is charged to its own order's class
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And "P Family Trust" is an investor of the fund with a portal user
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 50000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 50000 | 2025-09-01 |
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "50000"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000;class=B" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And the portfolio fair value is "100,00,00,000"
    And the fund ledger has "Cash In Hand" of "5,00,00,000" on "2026-10-25"
    And today is "2026-11-01"
    When the NAV for "2026-10-31" is drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | dealing_in_progress_cents | 0            |
      | nav_cents                 | 50,00,00,000 |
      | nav_per_unit_cents        | 10,000       |
    And the class "B" NAV for "2026-10-31" should be:
      | dealing_in_progress_cents | 5,00,00,000  |
      | nav_cents                 | 50,00,00,000 |
      | nav_per_unit_cents        | 10,000       |

  # E204 — Edge case: an administrator's uploaded NAV is taken as given — no dealing-in-progress line is added even though P's ₹5 Cr advance is pending.
  @rack_test
  Scenario: An uploaded NAV gets no dealing-in-progress line
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    When I upload the NAV rows:
      | Unit Class | NAV Date   | NAV            | Units Outstanding | NAV Per Unit |
      | A          | 2026-10-31 | 1,02,20,00,000 | 1,00,000          | 10,220       |
    Then the class "A" NAV for "2026-10-31" should be:
      | source                    | uploaded      |
      | dealing_in_progress_cents | 0             |
      | nav_per_unit_cents        | 10,220        |

  # E205 — Edge case: the cash balance was last entered on 20 Oct, before P's ₹5 Cr arrived on 25 Oct, so taking the advance out of it would understate the NAV — the NAV page warns to update the cash balance.
  Scenario: A cash balance older than advance money is flagged
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And the fund ledger has "Cash In Hand" of "10,00,000" on "2026-10-20"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And the portfolio fair value is "102,20,00,000"
    And today is "2026-11-01"
    When the NAV for "2026-10-31" is drafted
    And I open the class "A" NAV for "2026-10-31"
    Then I should see "The cash balance (\"Cash In Hand\") is from 20 October 2026, before money received on 25 October 2026 for orders not yet dealt"
