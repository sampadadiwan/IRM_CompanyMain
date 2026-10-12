Feature: Evergreen late management fees across classes
  Worked examples E333, E337 — openspec/changes/archive/2026-10-11-evergreen-late-management-fees/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 75000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 25000 | 2025-09-01 |
    And the portfolio fair value is "102,20,00,000"
    And class "A" charges a management fee of "1.5"
    And class "B" charges a management fee of "1"
    And the class "A" NAV for "2026-09-30" was drafted and approved before a fee was required

  # E333 — Edge case: only class A has a fee booked late (₹2,38,500 dated 30 Sep); class B's 31 Oct draft has nothing late.
  @rack_test
  Scenario: A late fee belongs to its own class only
    Given folio "F-012" accrued a management fee of "2,38,500" on "2026-09-30"
    And folio "F-012" accrued a management fee of "2,46,000" on "2026-10-31"
    And folio "F-031" accrued a management fee of "54,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" draft for "2026-10-31" should have a late fee of "2,38,500" waiting for a decision
    And the class "B" draft for "2026-10-31" should have no late fee

  # E337 — Edge case: A owes ₹3,00,000 and B ₹1,00,000 for October; a ₹1,00,000 payment dated 25 Sep booked late is split 3 : 1 — A ₹75,000, B ₹25,000.
  @rack_test
  Scenario: A late fee payment is split by what each class owed
    Given the fund ledger has "Management Fee Paid" of "1,00,000" on "2026-09-25"
    And folio "F-012" accrued a management fee of "3,00,000" on "2026-10-31"
    And folio "F-031" accrued a management fee of "1,00,000" on "2026-10-31"
    When the NAVs for "2026-10-31" are drafted
    Then the class "A" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 2,25,000 |
    And the class "B" NAV for "2026-10-31" should be:
      | mgmt_fee_payable_cents | 75,000 |
