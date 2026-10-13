Feature: Evergreen investor portal
  Worked examples H37, H38, H39, E12, E17, E48, E49, E50, X19, E180, X115, E211, E226 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"

  # H37 — Happy path: an investor's holding shows units, NAV per unit, value and gain, with no committed/called/uncalled figures.
  @rack_test
  Scenario: The investor sees value, units and NAV per unit, not commitment figures
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "4,892.3679"
    And I should see "10,160.94"
    And I should see "4,97,11,056.68"
    And I should see "-0.6%"
    And I should not see closed-ended figures

  # E12 — Edge case: a newer draft NAV exists, so the investor still sees the last approved NAV per unit and never the draft.
  @rack_test
  Scenario: Investors never see draft NAVs
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01" at "10,000"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And a draft NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "9,980.69"
    And I should not see "10,220.00"

  # E48 — Edge case: all units are in a hard lock-up, so Holding shows them locked with 0 free and Redeem disabled.
  @rack_test
  Scenario: Units in a hard lock-up are shown locked and Redeem is disabled
    Given the fund setting has "lock_up_months=12;lock_up_type=hard"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "Locked: 4,892.3679 units until 02 November 2027 (hard lock-up)"
    And I should see "Free to redeem: 0 units"
    And I should see "All your units are locked until 02 November 2027"

  # E49 — Edge case: no NAV has been approved yet, so Holding shows units and cost with "NAV not yet published".
  Scenario: No approved NAV yet
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01" at "10,000"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "NAV not yet published"

  # E50 — Edge case: an investor with fund access but no units sees Subscribe and no Redeem.
  @rack_test
  Scenario: An investor with no units can subscribe but not redeem
    Given "Q Capital" is an investor of the fund with a portal user
    When "Q Capital" logs in to the portal
    And I open the fund as an investor
    Then I should see "Subscribe"
    And I should not see "Redeem"

  # H38 — Happy path: a gated redemption shows Part-filled, the paid units, the queue place and the carried units on Requests.
  @rack_test
  Scenario: The request timeline shows a part fill and the queue place
    Given the fund setting has "gate_pct=5;gate_method=fifo"
    And "B LLP" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "Others" holds "81000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    When I mark the redemption of "B LLP" paid on "2026-11-10" with reference "UTR1" in the tracker of "2026-11-02"
    And "B LLP" logs in to the portal
    And I open the fund as an investor
    And I open the investor tab "Requests"
    Then I should see "Part-filled"
    And I should see "2,064.5793 units paid"
    And I should see "Queued #1"
    And I should see "381.6047 units carried"

  # E17 — Edge case: once the dealing date is confirmed the investor's order page offers no Cancel.
  Scenario: No cancel after confirmation
    Given "P Family Trust" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When "P Family Trust" logs in to the portal
    And I open the order of "P Family Trust" directly
    Then I should not see "Cancel"

  # E226 — Edge case: the investor's own order page shows the investor, folio and dealing date as plain text — the links and the Dealing card with settlement actions are for fund users only.
  Scenario: The investor's order page has no fund-user links
    Given "P Family Trust" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When "P Family Trust" logs in to the portal
    And I open the order of "P Family Trust" directly
    Then I should see "P Family Trust"
    And the order page should not link the investor, folio or dealing date

  # H39 — Happy path: the quarterly statement carries opening/closing units and the subscription units and amount.
  @rack_test
  Scenario: The quarterly statement carries units and flows
    Given "P Family Trust" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    Then the statement of folio "F-101" for "2026-10-01" to "2026-12-31" should have:
      | opening_units     | 0         |
      | closing_units     | 4892.3679 |
      | subscribed_units  | 4892.3679 |
      | subscribed_amount | 50000000  |

  # X19 — Error case: an investor opening the address of another investor's order sees no order.
  Scenario: An investor cannot open another investor's order
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And today is "2026-09-10"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-10 09:00"
    When "P Family Trust" logs in to the portal
    And I open the order of "B LLP" directly
    Then I should not see the order

  # E171 — Edge case: two investors hold folios in the same fund; P Family Trust sees only its own folio F-101 and none of B LLP's folio or request.
  @rack_test
  Scenario: The investor sees only its own folios and requests
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And today is "2026-09-10"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-10 09:00"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "F-101"
    And I should see "1,000.0000"
    And I should see "1,00,00,000.00"
    And I should not see "F-031"
    And I should not see "7,000.0000"
    When I open the investor tab "Requests"
    Then I should see "No requests yet."

  # E172 — Edge case: units in a soft lock-up are shown locked but stay free to redeem (with the early fee), so Redeem stays enabled.
  @rack_test
  Scenario: A soft lock-up shows the lock but keeps Redeem enabled
    Given the fund setting has "lock_up_months=12;lock_up_type=soft"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "Locked: 4,892.3679 units until 02 November 2027 (soft lock-up)"
    And I should see "Free to redeem: 4,892.3679 units"
    And the Redeem button of folio "F-101" should be enabled

  # E173 — Edge case: 300 of 1,000 units are already in an open redemption, so only 700 units are shown free to redeem.
  @rack_test
  Scenario: Units already queued for redemption are not free
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And today is "2026-09-10"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=300" received "2026-09-10 09:00"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "Free to redeem: 700 units"
    And the Redeem button of folio "F-101" should be enabled
    When I open the investor tab "Requests"
    Then the investor requests should show "300.0000"

  # E174 — Edge case: one folio holds an old free lot (1,000) and a new hard-locked lot (500), so only the new lot is shown locked and 1,000 units are free.
  @rack_test
  Scenario: Part of a folio is in a hard lock-up
    Given the fund setting has "lock_up_months=12;lock_up_type=hard"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "P Family Trust" holds "500" units of class "A" in folio "F-101" issued "2026-11-02"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then I should see "1,500.0000"
    And I should see "Locked: 500.0000 units until 02 November 2027 (hard lock-up)"
    And I should see "Free to redeem: 1,000 units"
    And the Redeem button of folio "F-101" should be enabled

  # E175 — Edge case: the folio has an approved and an unapproved generated document; the Documents tab shows only the approved one.
  @rack_test
  Scenario: Unapproved generated documents are hidden from the investor
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And folio "F-101" has an approved generated document "Contract note F-101 Oct 2026"
    And folio "F-101" has an unapproved generated document "Contract note F-101 Nov 2026"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    And I open the investor tab "Documents"
    Then I should see "Contract note F-101 Oct 2026"
    And I should not see "Contract note F-101 Nov 2026"

  # X104 — Error case: P Family Trust posts a redemption naming B LLP's folio F-031; the folio is stripped, so no order is placed on B LLP's folio.
  Scenario: An investor cannot order on another investor's folio
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And today is "2026-09-10"
    When "P Family Trust" tries to place a "redemption" order of "100" units on folio "F-031" directly
    Then no order should be placed on folio "F-031"
    And "B LLP" should have no orders

  # X105 — Error case: an investor typing the GP unit register, order book or dealing dates address sees no register and none of another investor's data.
  @rack_test
  Scenario: An investor cannot open the GP screens directly
    Given "P Family Trust" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "8000"
    And today is "2026-09-10"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-10 09:00"
    When "P Family Trust" logs in to the portal
    And I request the evergreen "unit register" page directly
    Then I should not see the unit register
    And I should not see "F-031"
    When I request the evergreen "order book" page directly
    Then I should not see "B LLP"
    When I request the evergreen "dealing dates" page directly
    Then I should not see "B LLP"

  # E180 — Edge case: the portal home card for an evergreen folio uses the closed-ended card layout and shows NAV per unit and value with the currency (₹10,160.94; ₹4,97,11,056.68), not committed or called amounts.
  @rack_test
  Scenario: The portal home card shows value and NAV per unit with the currency
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the portal home
    Then the portal card of folio "F-101" should show "₹4,97,11,056.68"
    And the portal card of folio "F-101" should show "4,892.3679"
    And the portal card of folio "F-101" should not show "Committed"
    And the portal card of folio "F-101" should offer Redeem

  # X115 — Error case: every unit of the folio is in a hard lock-up, so the portal home card's Redeem is disabled and says until when (as the fund page does, E48).
  @rack_test
  Scenario: The portal home card disables Redeem when every unit is hard-locked
    Given the fund setting has "lock_up_months=12;lock_up_type=hard"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the portal home
    Then the portal card of folio "F-101" should not offer Redeem
    And the portal card of folio "F-101" should show "All your units are locked until 02 November 2027"

  # E211 — Edge case: the open section's accordion button is hidden, so the section carries its own header saying what its rows are.
  @rack_test
  Scenario: Each portal section has its own header
    Given "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02" at "10,220"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then the portal section "holding" should have the header "Holding"
    And the portal section "transactions" should have the header "Transactions"
