@rack_test
Feature: Evergreen order journeys
  Worked examples H12, H13, H14, H15, E19, E20, E97 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-10-20"

  # H12 — Happy path: with journeys on subscriptions only, the subscription gets a journey and the redemption doesn't
  Scenario: Journeys on subscriptions only
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=subscriptions;redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-20 09:00"
    When I open the order of "P Family Trust"
    Then the order of "P Family Trust" should have a journey
    When I open the order of "A Ltd"
    Then the order of "A Ltd" should have no journey

  # H13 — Happy path: a subscription can only be placed with an approved KYC (evergreen-folio-soa X1), so its
  # Check investor KYC step passes at once and the journey moves on to the signed form
  Scenario: The KYC step passes for an approved investor
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=subscriptions"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    When I open the order of "P Family Trust"
    Then the order of "P Family Trust" should not be waiting on "Check investor KYC"
    And the order of "P Family Trust" should be waiting on "Collect signed subscription form"

  # H14 — Happy path: a redemption with a journey is signatory-verified and accepted, then ready to deal
  Scenario: A redemption is verified and accepted
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=both;redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-20 09:00"
    And there is an approver "Ravi" in the entity
    When I open the order of "A Ltd"
    And I verify the signatory
    Then I should see "Signatory verified"
    When the approver logs in
    And I open the order of "A Ltd"
    And I accept the order
    Then I should see "Order accepted"
    And the order of "A Ltd" should be ready to deal

  # H15 — Happy path: the investor uploads the signed subscription form and the journey moves on to Accept order
  Scenario: The investor uploads the signed form
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=subscriptions"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has a verified KYC
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    When "P Family Trust" logs in to the portal
    And I open the order of "P Family Trust"
    Then I should see "Upload your signed subscription form"
    When I upload the signed subscription form
    Then I should see "Signed form uploaded"
    And the order of "P Family Trust" should be waiting on "Accept order"

  # E19 — Edge case: with order journeys off an order has no step bar and is ready to deal straight away
  Scenario: Journeys off — no step bar, ready once paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-20 09:00"
    When I open the order of "A Ltd"
    Then the order of "A Ltd" should have no journey
    And the order of "A Ltd" should be ready to deal

  # E20 — Edge case: the approver rejects a pending subscription; it becomes Rejected with the reason, and the investor is emailed
  Scenario: The GP rejects an order
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=subscriptions"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has a verified KYC
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    And there is an approver "Ravi" in the entity
    When the approver logs in
    And I open the order of "P Family Trust"
    And I reject the order with reason "Investor not eligible"
    Then I should see "Order rejected"
    And the latest order should be:
      | status          | rejected              |
      | rejected_reason | Investor not eligible |
    And "P Family Trust" receives an email with subject "Alpha Long-Short Fund: Request cancelled" containing "Investor not eligible"

  # E97 — Edge case: the approver rejects a redemption without giving a reason; it is recorded as "Rejected" and its units are free for a new order
  Scenario: Reject without a reason frees the units
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "order_journeys=both;redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-10-20 09:00"
    And there is an approver "Ravi" in the entity
    When the approver logs in
    And I open the order of "A Ltd"
    And I reject the order with reason ""
    Then I should see "Order rejected"
    And the latest order should be:
      | status          | rejected |
      | rejected_reason | Rejected |
    When "A Ltd" tries a "redemption" order "folio=F-012;units=1000" received "2026-10-20 10:00"
    Then the order should be accepted
