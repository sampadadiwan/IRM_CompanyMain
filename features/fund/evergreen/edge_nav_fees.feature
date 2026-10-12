@rack_test
Feature: Evergreen fees — edge cases needing more than one class
  Worked example E135 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # E135 — Edge case: each class accrues at its own rate on its own NAV — over 73 days A (₹80 Cr at 1.5 %) accrues ₹24,00,000 and B (₹20 Cr at 2 %) ₹8,00,000.
  Scenario: Classes accrue the management fee at their own rates
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 80000 | 2025-09-01 |
      | B LLP    | F-031 | B     | 20000 | 2025-09-01 |
    And class "A" charges a management fee of "1.5"
    And class "B" charges a management fee of "2"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "10,000" and units "80000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "10,000" and units "20000"
    And the management fee formula is added
    And the Allocation Run "start_date=2026-10-01;end_date=2026-12-12" is created for the "Alpha Long-Short Fund"
    Then the class "A" management fee entries for "2026-12-12" should total "24,00,000"
    And the class "B" management fee entries for "2026-12-12" should total "8,00,000"
