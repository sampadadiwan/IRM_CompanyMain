Feature: Evergreen investor portal for investor advisors
  Worked examples H63, H64, H65, H66, E182, E183, E184, E185, E186, E187, X118, X119, X120, X121, X122, X123 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user

  # H63 — Happy path: Vikram advises P Family Trust; switched into P he sees P's folio F-101 (5,000 units, ₹5,11,00,000.00), P's allotment and requests, and none of B LLP's folios, allotment or requests.
  @rack_test
  Scenario: An advisor sees the investor's holding, transactions and requests, and none of another investor's
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=51100000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And "B LLP" has placed a "subscription" order "amount=10220000" received "2026-10-20 10:00"
    And "B LLP" has paid the subscription on "2026-10-25"
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "107000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=300" received "2026-11-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-11-10 10:00"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the fund as an investor
    Then the holding of folio "F-101" should show "5,000.0000"
    And the holding of folio "F-101" should show "₹10,220.00"
    And the holding of folio "F-101" should show "₹5,11,00,000.00"
    And I should not see "F-031"
    And I should not see "F-102"
    And I should not see "7,000.0000"
    When I open the investor tab "Transactions"
    Then the investor transactions should show "5,000.0000"
    And the investor transactions should show "₹5,11,00,000.00"
    And the investor transactions should not show "1,000.0000"
    And the investor transactions should not show "₹1,02,20,000.00"
    When I open the investor tab "Requests"
    Then the investor requests should show "300.0000"
    And the investor requests should not show "100.0000"
    And the request of "B LLP" should not be listed

  # E182 — Edge case: Vikram advises both P Family Trust (F-101, 1,000 units) and Q Capital (F-201, 2,500 units); switched into P he sees only F-101, and after switching to Q in the topbar only F-201 (₹2,50,00,000.00).
  Scenario: An advisor of two investors sees each investor's folios separately
    Given "Q Capital" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "Q Capital" holds "2500" units of class "A" in folio "F-201" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "3500"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And "Q Capital" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-09-10"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the fund as an investor
    Then the holding of folio "F-101" should show "1,000.0000"
    And the holding of folio "F-101" should show "₹1,00,00,000.00"
    And I should not see "F-201"
    And I should not see "2,500.0000"
    When I switch the advisor persona to "Q Capital"
    And I open the fund as an investor
    Then the holding of folio "F-201" should show "2,500.0000"
    And the holding of folio "F-201" should show "₹2,50,00,000.00"
    And I should not see "F-101"
    And I should not see "1,000.0000"

  # X118 — Error case: Vikram's access to P Family Trust is still pending approval, so P's folio F-101 and its request are hidden and P's order page shows no order.
  @rack_test
  Scenario: An advisor whose access is not approved sees none of the investor's data
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "1000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And the access of advisor "Vikram" to "P Family Trust" is not approved
    And today is "2026-09-10"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=300" received "2026-09-10 09:00"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the fund as an investor
    Then I should not see "F-101"
    And I should not see "1,000.0000"
    And I should not see "₹1,00,00,000.00"
    When I open the order of "P Family Trust" directly
    Then I should not see the order

  # X123 — Error case: Vikram's access to P Family Trust is not approved; a direct subscription post of ₹10,00,000 places no order at all (no investor of his own to place it for).
  Scenario: An advisor whose access is not approved cannot place an order
    Given "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And the access of advisor "Vikram" to "P Family Trust" is not approved
    And the advisor "Vikram" is switched into "P Family Trust"
    And today is "2026-09-10"
    When the advisor "Vikram" tries to place a "subscription" order of "1000000" directly
    Then no order should have been created
    And "P Family Trust" should have no orders

  # X119 — Error case: the fund admin removes Vikram as P Family Trust's advisor while he is still switched in; he no longer sees F-101 and P's order page shows no order.
  @rack_test
  Scenario: A revoked advisor sees none of the investor's data
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "1000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And the advisor "Vikram" is switched into "P Family Trust"
    And today is "2026-09-10"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=300" received "2026-09-10 09:00"
    And the fund admin removes the advisor "Vikram" from "P Family Trust"
    When the advisor "Vikram" logs in to the portal
    And I open the fund as an investor
    Then I should not see "F-101"
    And I should not see "1,000.0000"
    When I open the order of "P Family Trust" directly
    Then I should not see the order

  # E183 — Edge case: P Family Trust's folio F-101 has an approved and an unapproved generated contract note; the advisor's Documents tab lists only the approved one.
  @rack_test
  Scenario: The advisor sees approved contract notes only
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And folio "F-101" has an approved generated document "Contract note F-101 Oct 2026"
    And folio "F-101" has an unapproved generated document "Contract note F-101 Nov 2026"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the fund as an investor
    And I open the investor tab "Documents"
    Then I should see "Contract note F-101 Oct 2026"
    And I should not see "Contract note F-101 Nov 2026"

  # H64 — Happy path: switched into P Family Trust, Vikram redeems 200 of F-101's 1,000 units (≈ 200 × ₹10,000 = ₹20,00,000); the order is P's, on F-101, from the portal, and B LLP's F-031 is not offered.
  Scenario: An advisor places a redemption on behalf of the investor
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-09-10"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I start a "redemption" for the fund
    Then the folio choices should not include "F-031"
    When I fill the order with "folio=F-101;units=200"
    And I check the order
    Then I should see "20,00,000"
    When I submit the order
    Then I should see "Redemption request received for 200 units"
    And the latest order should be for "P Family Trust" on folio "F-101" from the portal
    And the latest order should be:
      | status | pending |
      | units  | 200     |

  # H65 — Happy path: P Family Trust's ₹5,00,00,000 subscription is still pending, so its advisor Vikram can cancel it from the order page.
  @rack_test
  Scenario: An advisor cancels the investor's pending request
    Given "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the order of "P Family Trust" directly
    And I cancel the order
    Then I should see "Request cancelled"
    And the latest order should be:
      | status | cancelled |

  # X120 — Error case: Vikram advises only P Family Trust and posts a 100-unit redemption naming B LLP's folio F-031; the folio is stripped, so no order is placed at all.
  Scenario: An advisor cannot order on another investor's folio
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And the advisor "Vikram" is switched into "P Family Trust"
    And today is "2026-09-10"
    When the advisor "Vikram" tries to place a "redemption" order of "100" units on folio "F-031" directly
    Then no order should have been created
    And no order should be placed on folio "F-031"
    And "B LLP" should have no orders

  # E184 — Edge case: Vikram advises both P Family Trust and B LLP but is switched into P; a 100-unit redemption naming B's F-031 is refused — he must switch into B LLP to act for it.
  Scenario: An advisor of two investors acts only for the investor he is switched into
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And "B LLP" has an approved advisor "Vikram" from "Vikram Advisors"
    And the advisor "Vikram" is switched into "P Family Trust"
    And today is "2026-09-10"
    When the advisor "Vikram" tries to place a "redemption" order of "100" units on folio "F-031" directly
    Then no order should have been created
    And "B LLP" should have no orders

  # X121 — Error case: switched into P Family Trust, Vikram types the address of B LLP's redemption order and sees no order.
  Scenario: An advisor cannot open another investor's order
    Given "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-09-10"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-10 09:00"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the order of "B LLP" directly
    Then I should not see the order

  # X122 — Error case: switched into P Family Trust, Vikram types the GP unit register and order book addresses and sees no register and none of B LLP's data.
  @rack_test
  Scenario: An advisor cannot open the GP screens directly
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-09-10"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-10 09:00"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I request the evergreen "unit register" page directly
    Then I should not see the unit register
    And I should not see "F-031"
    When I request the evergreen "order book" page directly
    Then I should not see "B LLP"

  # H66 — Happy path: the advisor's portal home shows P Family Trust's F-101 card (4,892.3679 × ₹10,160.94 = ₹4,97,11,056.68) and no card for B LLP's F-031.
  @rack_test
  Scenario: The advisor's portal home shows the investor's folio card
    Given "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "11892.3679"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And today is "2026-12-01"
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the portal home
    Then the portal card of folio "F-101" should show "₹4,97,11,056.68"
    And the portal card of folio "F-101" should show "4,892.3679"
    And the portal card of folio "F-101" should not show "Committed"
    And the portal card of folio "F-101" should offer Redeem
    And there should be no portal card of folio "F-031"

  # E185 — Edge case: Vikram advises Q Capital, which has fund access but no folio; he sees "You hold no units yet." with Subscribe, and none of P Family Trust's F-101.
  @rack_test
  Scenario: An advisor of an investor with no folios sees an empty holding
    Given "Q Capital" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "Q Capital" has an approved advisor "Vikram" from "Vikram Advisors"
    When the advisor "Vikram" logs in to the portal for "Q Capital"
    And I open the fund as an investor
    Then I should see "You hold no units yet."
    And I should see "Subscribe"
    And I should not see "Redeem"
    And I should not see "F-101"

  # E186 — Edge case: Vikram advises P Family Trust but is still in his own firm (an employee of Vikram Advisors, not switched in); the fund page shows none of P's evergreen data.
  Scenario: An advisor in his own firm sees no investor data
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "1000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    When the advisor "Vikram" requests the fund page directly
    Then the response should not show the evergreen investor page
    And the response should not show "F-101"

  # E187 — Edge case: Vikram is still P Family Trust's approved advisor but his access right on the fund was removed; switched into P he sees none of F-101.
  Scenario: An advisor without the fund access right sees no investor data
    Given "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "1000"
    And "P Family Trust" has an approved advisor "Vikram" from "Vikram Advisors"
    And the fund access right of advisor "Vikram" for "P Family Trust" is removed
    When the advisor "Vikram" logs in to the portal for "P Family Trust"
    And I open the fund as an investor
    Then I should not see "F-101"
    And I should not see "1,000.0000"
