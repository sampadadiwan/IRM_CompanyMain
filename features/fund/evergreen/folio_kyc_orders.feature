@rack_test
Feature: Evergreen orders and folios carry an approved KYC
  Worked examples H1, H2, H3, E1, E2, E3, E4, E5, X1, X2, X3, X4, X5 — openspec/changes/evergreen-folio-soa/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"

  # H1 — Happy path: a pay-after subscription from an investor with one approved KYC opens its folio at confirm with that KYC
  Scenario: One approved KYC is linked to the folio opened at dealing
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "payment_timing=after"
    And "P Family Trust" is an investor of the fund with a portal user
    When "P Family Trust" tries to place a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    Then the order should be accepted
    And the latest order of "P Family Trust" should be for investing entity "P Family Trust"
    Given an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the latest folio of "P Family Trust" should be for investing entity "P Family Trust"

  # H2 — Happy path: an investor with two approved KYCs picks one in the subscription form; the new folio is for it
  Scenario: The investor picks the investing entity
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When "P Family Trust" logs in to the portal
    And I start a "subscription" for the fund
    Then the order form should ask for the investing entity with "P Family Trust, P Holdings LLP"
    When I choose the investing entity "P Holdings LLP"
    And I fill the order with "amount=50000000"
    And I submit the order
    Then I should see "Subscription request received"
    And the latest folio of "P Family Trust" should be for investing entity "P Holdings LLP"

  # H3 — Happy path: a top-up into an existing folio takes the folio's KYC and the form doesn't ask for one
  Scenario: A top-up keeps the folio's KYC
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When "P Family Trust" logs in to the portal
    And I start a subscription into folio "F-101"
    Then the order form should not ask for the investing entity
    When "P Family Trust" tries to place a "subscription" order "folio=F-101;amount=1000000" received "2026-10-20 09:00"
    Then the order should be accepted
    And the latest order of "P Family Trust" should be for investing entity "P Family Trust"

  # E1 — Edge case: a pre-funded subscription opens its folio at order time, already linked to the KYC
  Scenario: Pre-funded folio opens with its KYC at once
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    When "P Family Trust" tries to place a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    Then the order should be accepted
    And the latest folio of "P Family Trust" should be for investing entity "P Family Trust"

  # E2 — Edge case: the GP enters a subscription for an investor with two approved KYCs; the form comes back asking which one
  Scenario: GP entry asks for the investing entity once the investor is known
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When I start a "subscription" for the fund
    And I fill the order with "investor=P Family Trust;amount=50000000"
    And I submit the order
    Then I should see "Choose the investing entity for this subscription."
    And the order form should ask for the investing entity with "P Family Trust, P Holdings LLP"
    When I choose the investing entity "P Family Trust"
    And I fill the order with "amount=50000000"
    And I submit the order
    Then I should see "Subscription request received"
    And the latest folio of "P Family Trust" should be for investing entity "P Family Trust"

  # E3 — Edge case: a pending KYC is not offered; the single approved one is used without asking
  Scenario: Only approved KYCs count
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has a pending KYC "P Holdings LLP"
    When "P Family Trust" logs in to the portal
    And I start a "subscription" for the fund
    Then the order form should not ask for the investing entity
    When I fill the order with "amount=50000000"
    And I submit the order
    Then I should see "Subscription request received"
    And the latest folio of "P Family Trust" should be for investing entity "P Family Trust"

  # E4 — Edge case: an order upload names the investing entity; a row without one for an investor with two approved KYCs fails
  Scenario: Order upload with an Investing Entity column
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When I upload the order rows with headers:
      | Type         | Folio No | Investor       | Unit Class | Amount   | Units | All Units | Received At      | Investing Entity |
      | Subscription |          | P Family Trust | A          | 50000000 |       |           | 2026-10-20 09:00 | P Holdings LLP   |
      | Subscription |          | P Family Trust | A          | 10000000 |       |           | 2026-10-20 09:30 |                  |
    Then the order upload should have "1" failed rows
    And the order upload results should mention "Choose the investing entity for this subscription."
    And the latest folio of "P Family Trust" should be for investing entity "P Holdings LLP"

  # E5 — Edge case: a redemption on a linked folio records the folio's KYC, whatever other KYCs the investor has
  Scenario: A redemption takes the folio's KYC
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has another approved KYC "A Holdings"
    When "A Ltd" tries to place a "redemption" order "folio=F-012;units=100" received "2026-10-20 09:00"
    Then the order should be accepted
    And the latest order of "A Ltd" should be for investing entity "A Ltd"

  # X1 — Error case: an investor without an approved KYC can't subscribe (it replaces open-ended-funds H13's wait on the KYC step)
  Scenario: No approved KYC, no subscription
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "order_journeys=subscriptions"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has no approved KYC
    When "P Family Trust" tries to place a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    Then the order should be refused with "P Family Trust has no approved KYC — it must be approved before subscribing."
    And "P Family Trust" should have no folio

  # X2 — Error case: two approved KYCs and none picked
  Scenario: Several approved KYCs and none picked
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When "P Family Trust" tries to place a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    Then the order should be refused with "Choose the investing entity for this subscription."

  # X3 — Error case: a request naming another investor's KYC is refused
  Scenario: Another investor's KYC is refused
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    When "P Family Trust" tries to place a "subscription" order "amount=50000000;other_investor=B LLP;other_entity=B LLP" received "2026-10-20 09:00"
    Then the order should be refused with "Choose one of P Family Trust's approved investing entities."

  # X4 — Error case: a folio with no KYC linked can't take orders
  Scenario: Orders on a folio without a KYC are refused
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And folio "F-031" has no KYC linked
    When "B LLP" tries to place a "redemption" order "folio=F-031;units=100" received "2026-10-20 09:00"
    Then the order should be refused with "Folio F-031 has no approved KYC linked — link one on the folio before placing orders."

  # X5 — Error case: an order that reaches dealing without a KYC, for an investor with two, can't open a folio; the confirm is refused
  Scenario: Confirm refuses to open a folio without a KYC
    Given the evergreen fund "Alpha Evergreen Fund" with classes "A" and settings "payment_timing=after"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has another approved KYC "P Holdings LLP"
    When "P Family Trust" tries to place a "subscription" order "amount=50000000;entity=P Holdings LLP" received "2026-10-20 09:00"
    Then the order should be accepted
    Given the latest order of "P Family Trust" has no investing entity
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin tries to confirm dealing date "2026-11-02"
    Then the confirm should be refused with "P Family Trust has no single approved KYC for this order — choose the investing entity on the order"
    And "P Family Trust" should have no folio
