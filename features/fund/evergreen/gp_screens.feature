Feature: Evergreen GP screens
  Worked examples H31, H32, H33, H34, H35, E38 (GP), E45, E46, E216, E217, E218, E219, E220 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-12-01"

  # H31 — Happy path: an evergreen fund page shows the evergreen tabs — Subscriptions and Redemptions inside Dealing, Fees inside NAV — and no Commitments or Calls tabs.
  @rack_test
  Scenario: An evergreen fund shows the evergreen tabs
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I open the fund page
    Then I should see the evergreen tabs

  # E219 — Edge case: the inner Subscriptions / Redemptions tabs count only open orders, not dealt ones.
  @rack_test
  Scenario: The Dealing tab counts open orders only
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And a settled "subscription" of "10,000" on dealing date "2026-11-02"
    And "Q Capital" is an investor of the fund with a portal user
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-12-01 09:00"
    When I open the fund page
    Then the fund tab "Dealing" should hold "Subscriptions (1)"
    And the fund tab "Dealing" should hold "Redemptions (0)"

  # E220 — Edge case: a link to an inner tab (?tab=evergreen-redemptions-tab) opens Dealing first, then Redemptions inside it.
  Scenario: A link to an inner tab opens its outer tab
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I open the fund page on the tab "evergreen-redemptions-tab"
    Then the fund tab "Dealing" should be active
    And the inner fund tab "Redemptions" should be active

  # H32 — Happy path: the funds list card of an evergreen fund shows the Evergreen badge and NAV per unit.
  @rack_test
  Scenario: The funds list shows an evergreen card
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "Others" holds "99892.3679" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And there is a fund "name=Beta Growth Fund;currency=INR;unit_types=A" for the entity
    When I open the funds list as cards
    Then the card of "Alpha Long-Short Fund" should show "Evergreen"
    And the card of "Alpha Long-Short Fund" should show "10,160.94"

  # H33 — Happy path: the fund header shows the approved NAV per unit and the quarter's net flows.
  @rack_test
  Scenario: Overview figures
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "Others" holds "99892.3679" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And a settled "subscription" of "5,00,00,000" on dealing date "2026-11-02"
    And a settled "redemption" of "5,11,00,000" on dealing date "2026-11-02"
    When I open the evergreen overview
    Then I should see "10,160.94"
    And I should see "11,00,000"

  # E45 — Edge case: a newer draft NAV exists, so the Overview keeps the approved NAV and notes the draft awaiting approval.
  @rack_test
  Scenario: A newer draft is noted on the Overview
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And a draft NAV for class "A" on "2026-12-31" with NAV per unit "10,300" and units "99892.3679"
    When I open the evergreen overview
    Then I should see "10,160.94"
    And I should see "awaiting approval"

  # H34 — Happy path: the redemptions list shows each queued redemption's value, running total and gate outcome on its own row (one table, no second queue table).
  @rack_test
  Scenario: The redemptions list shows each request against the gate
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5"
    And "B LLP" holds "4935.4207" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=381.6047" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;units=978.4736" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When I open the redemptions list
    Then I should see "Requested for"
    And I should see "Will be paid · "
    And I should not see "Redemption queue"
    And the "Amount" cell of the order of "B LLP" should show "38,77,462"
    And the "Amount" cell of the order of "C HUF" should show "99,42,211"
    And the "Running total" cell of the order of "C HUF" should show "1,38,19,674"
    And the order of "B LLP" should show "Will be paid in full" at the gate
    And the order of "C HUF" should show "Will be paid in full" at the gate

  # E216 — Edge case: under a FIFO gate the queue is bigger than the gate — the first request is paid in full, the second part-filled, and the unpaid units show as carried on its own row.
  @rack_test
  Scenario: The gate part-fills the last request that fits
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "B LLP" holds "4935.4207" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=4935.4207" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;units=978.4736" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When I open the redemptions list
    Then the order of "B LLP" should show "Will be paid in full" at the gate
    And the order of "C HUF" should show "Will be part-filled" at the gate
    And the "Will be carried" cell of the order of "C HUF" should show "919.2760"

  # E217 — Edge case: finished orders are hidden by default; the filter's Dealt option brings them back and hides the open ones.
  @rack_test
  Scenario: The order book opens on open orders only
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And a settled "subscription" of "10,000" on dealing date "2026-11-02"
    And "Q Capital" is an investor of the fund with a portal user
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-12-01 09:00"
    When I open the order book
    Then the order book should list the "subscription" order of "Q Capital"
    And the order book should not list the "subscription" order of "A Ltd"
    When I open the order book filtered to "Dealt"
    Then the order book should list the "subscription" order of "A Ltd"
    And the order book should not list the "subscription" order of "Q Capital"

  # E218 — Edge case: a redemption asked as an amount shows the amount plainly and its units as an estimate at the latest approved NAV.
  @rack_test
  Scenario: Amount and units are separate columns
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "B LLP" holds "4935.4207" units of class "A" in folio "F-031" issued "2025-09-01"
    # A redemption asked as an amount needs an approved NAV when it is placed
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "99892.3679"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=10000000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    And today is "2026-12-01"
    When I open the redemptions list
    Then the "Amount" cell of the order of "B LLP" should show "1,00,00,000.00"
    And the "Units" cell of the order of "B LLP" should show "≈ 984.1609"

  # E46 — Edge case: an unpaid pre-funded subscription two days before the cut-off is highlighted as Awaiting money.
  @rack_test
  Scenario: An unpaid pre-funded subscription is highlighted near the cut-off
    Given today is "2026-11-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "Q Capital" is an investor of the fund with a portal user
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-11-20 09:00"
    And today is "2026-11-24"
    When I open the order book
    Then the order of "Q Capital" should be highlighted as awaiting money

  # H35 — Happy path: the unit register totals units across folios.
  @rack_test
  Scenario: The unit register totals
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "90827.7886" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    When I open the unit register
    Then I should see "99,892.3679"
    And I should see "Total (2 folios)"

  # E38 (GP) — Edge case: NAV per unit is below the high-water mark, so the Fees tab shows the distance below it.
  @rack_test
  Scenario: The fees tab shows the distance below the mark
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And class "A" has the performance fee "pct=20"
    And the high-water mark of class "A" was set to "10,400" on "2025-12-31"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    When I open the fees tab
    Then I should see "239.06 below"

  # E176 — Edge case: the register flags a hard-locked folio with a red lock badge and its unlock date, and a folio with an open redemption with its queued units.
  @rack_test
  Scenario: The unit register shows lock-up and queued badges
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=2000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "13956.9472"
    And today is "2026-12-01"
    When I open the unit register
    Then the register row of folio "F-101" should show the hard lock-up badge "02/11/2027"
    And the register row of folio "F-012" should show no lock-up badge
    And the register row of folio "F-012" should show "2,000" units queued
    And I should see "13,956.9472"
    And I should see "Total (2 folios)"

  # E177 — Edge case: the downloaded register carries the same units, unlock date and queued units as the screen, with a blank unlock date for an unlocked folio.
  @rack_test
  Scenario: The unit register download carries locks and queued units
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2026-11-02"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=2000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "13956.9472"
    And today is "2026-12-01"
    When I download the unit register
    Then the downloaded unit register should have:
      | Folio | Units     | Locked until | Queued units |
      | F-012 | 9064.5793 |              | 2000         |
      | F-101 | 4892.3679 | 2027-11-02   | 0            |

  # E178 — Edge case: a new evergreen fund with no units shows the register's empty state and a zero total.
  @rack_test
  Scenario: An empty unit register
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    When I open the unit register
    Then I should see "No units yet"
    And I should see "Total (0 folios)"

  # X106 — Error case: a user of another entity opening the fund page or the unit register by address sees no evergreen tabs and no holdings.
  @rack_test
  Scenario: A user of another entity cannot open the evergreen screens
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And there is a user "Gary" of another entity "Gamma Advisors"
    When the user "Gary" signs in
    And I open the fund page
    Then I should not see the evergreen tabs
    When I open the unit register
    Then I should not see the unit register
    And I should not see "A Ltd"

  # X107 — Error case: an employee of the entity without access to the fund cannot open its unit register by address.
  Scenario: An employee without fund access cannot open the unit register
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And there is an employee "Nikhil" without access to the fund
    When the user "Nikhil" signs in
    And I open the unit register
    Then I should not see the unit register
    And I should not see "A Ltd"

  # H67 — Happy path: the folio's Requests tab shows what each order got on its dealing date (NAV used, units moved).
  @rack_test
  Scenario: The folio requests show a dealt subscription with its units
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And a settled "subscription" of "10,000" on dealing date "2026-11-02"
    When I open folio "F-012"
    Then the folio request of the "subscription" should show "+1.0000"
    And the folio request of the "subscription" should show "Dealt"

  # H68 — Happy path: the Unit History lists opening units and the dealt subscription with a running balance.
  @rack_test
  Scenario: The folio unit history explains the holding
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And a settled "subscription" of "10,000" on dealing date "2026-11-02"
    When I open folio "F-012"
    Then the folio unit history row 1 should show "Opening units" and balance "9,064.5793"
    And the folio unit history row 2 should show "Subscription · 02/11/2026" and balance "9,065.5793"
    And the subscription row of the unit history should link to its order

  # E206 — Edge case: an order whose dealing date is not confirmed shows "—" for NAV and units.
  @rack_test
  Scenario: A folio request not priced yet shows dashes
    Given today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=2000" received "2026-09-10 09:00"
    When I open folio "F-012"
    Then the folio request of the "redemption" should show "— —"
    And the folio request of the "redemption" should show "Pending"

  # E207 — Edge case: a unit row issued after today is flagged, since Holding only counts units issued up to today.
  @rack_test
  Scenario: A unit movement issued after today is flagged
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-12-15"
    When I open folio "F-012"
    Then the folio unit history row 1 should show "Not yet issued" and balance "100.0000"
