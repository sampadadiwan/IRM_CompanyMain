Feature: Evergreen part-paid subscriptions — accept the amount received
  The GP can accept the money received as the whole subscription; units follow that amount.
  Worked examples E72, E73, X31, X54 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # E72 — Edge case: a pre-funded subscription only half paid is reduced to the amount received before dealing and dealt as fully paid
  Scenario: A part-paid pre-funded subscription is accepted at the amount received
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And "P Family Trust" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid "50,00,000" of the subscription on "2026-10-25"
    When I accept the amount received for the order of "P Family Trust"
    Then the order of "P Family Trust" should be for "50,00,000" reduced from "1,00,00,000"
    And the subscription payment of "P Family Trust" should ask for "50,00,000"
    And folio "F-101" should have subscribed "50,00,000"
    Given an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the units of "P Family Trust" on "2026-11-02" should be "489.2368" dated "2026-11-02"
    And the "contract note" of "P Family Trust" on "2026-11-02" should show:
      | Amount                    | ₹50,00,000.00   |
      | Subscription reduced from | ₹1,00,00,000.00 |

  # E73 — Edge case: a pay-after-dealing subscription half paid after dealing has its fill re-sized at the same dealing NAV, then units are allotted
  Scenario: A part-paid subscription after dealing is re-sized and allotted
    Given today is "2026-11-10"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    And "Q Capital" has paid "50,00,000" of the subscription on "2026-12-06"
    When I accept the amount received for the order of "Q Capital"
    Then the order of "Q Capital" should be for "50,00,000" reduced from "1,00,00,000"
    And the fills of dealing date "2026-12-01" should be:
      | investor  | units | amount    |
      | Q Capital | 500   | 50,00,000 |
    And the units of "Q Capital" on "2026-12-01" should be "500.0000" dated "2026-12-06"
    And folio "F-101" should have subscribed "50,00,000"

  # X31 — Error case: with nothing received the order offers no Accept received amount, and a direct request is refused
  @rack_test
  Scenario: Accepting needs a part payment
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:00"
    Then the order page of "P Family Trust" should not offer to accept the amount received
    When the fund admin accepts the amount received for "P Family Trust" directly
    Then accepting is refused with "No money has been received for this subscription — cancel it instead"

  # X54 — Error case: accepting the amount received a second time is refused as already fully paid, and a redemption can never be accepted at an amount received
  Scenario: Accept received amount twice, or on a redemption
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "P Family Trust" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:00"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-20 09:00"
    And "P Family Trust" has paid "50,00,000" of the subscription on "2026-10-25"
    When I accept the amount received for the order of "P Family Trust"
    Then the order of "P Family Trust" should be for "50,00,000" reduced from "1,00,00,000"
    And the order page of "P Family Trust" should not offer to accept the amount received
    When the fund admin accepts the amount received for "P Family Trust" directly
    Then accepting is refused with "This subscription is already fully paid"
    When the fund admin accepts the amount received for the redemption of "A Ltd" directly
    Then accepting is refused with "Only a subscription can be accepted at the amount received"
