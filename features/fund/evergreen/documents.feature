@rack_test
Feature: Evergreen investor documents
  Contract notes and redemption advices are generated only from the fund's own templates; without one
  the investor is emailed the figures straight away and no document is generated.
  Worked examples E51, E151 (contract note contents: H25 in settlement.feature; advice: E32; acknowledgement: H7;
  gate notice and no call notice: H21) — openspec/changes/open-ended-funds/design.md#worked-examples

  # E51 — Edge case: without a Contract Note Template the investor is emailed the contract-note figures at allotment and no document is generated.
  Scenario: Without a template the contract note email is sent at allotment
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the "contract note" of "P Family Trust" on "2026-11-02" should show:
      | Units allotted | 4,892.3679 |
    And "P Family Trust" should get the "contract note" email without an attachment
    And the "contract note" email to "P Family Trust" should show:
      | F-101        |
      | A            |
      | Oct 31, 2026 |
      | Nov 02, 2026 |
      | ₹10,220.00   |
      | 4,892.3679   |
      | ₹5,00,00,000 |
    And no document should be stored on folio "F-101"

  # E151 — Edge case: a fund-level custom evergreen notification for contract_note replaces the default contract-note email subject and body.
  Scenario: A custom evergreen notification is used for the contract note
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund has an evergreen notification for "contract_note" with subject "Your Alpha units" and body "Dear {{investor_name}}, you now hold {{units_dealt}} more units at {{nav_per_unit}}."
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then "P Family Trust" receives an email with subject "Your Alpha units" containing "you now hold 4,892.3679 more units at 10,220.00"
