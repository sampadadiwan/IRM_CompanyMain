Feature: Evergreen dealing dates — list, pricing, confirm, roll, carry forward, undo
  Worked examples H16, H17, H18, H21, H26, E6, E21, E22, E23, E24, E25, E26, E33, E34, X17, X20, E102, E103, E105–E110, E208, E209, E210, E221, E222, E223, X56–X62
  — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "C HUF" is an investor of the fund with a portal user
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And "Others" holds "79000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"

  # H16 — Happy path: before any orders, the dealing list (All dates) shows the next monthly date (1 Jan 2027) with its cut-off (27 Dec 2026) at "Open for orders".
  @rack_test
  Scenario: Upcoming dealing dates are listed before any orders
    Given today is "2026-11-02"
    When the dealing dates are generated
    And I open the dealing list filtered to "All dates"
    Then the dealing list should show "2027-01-01" with cut-off "2026-12-27" at step "○ Open for orders"

  # E223 — Edge case: once confirmed, the dealing date keeps the same Subscriptions / Redemptions tabs and columns as the preview — past tense, from the stored fills, with a Settlement column — under a "Confirmed … final" line.
  Scenario: A confirmed dealing date keeps the preview's tabs and columns
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    And I confirm the dealing date
    Then I should see "Dealing date confirmed"
    And I should see "these figures are final"
    And the dealing tab "Redemptions (3)" should be active
    And the tracker row of "A Ltd" on "2026-11-02" should read "Filled in full"
    And the tracker row of "B LLP" on "2026-11-02" should read "Part-filled"
    And the tracker row of "C HUF" on "2026-11-02" should read "Carried"
    And the tracker row of "A Ltd" on "2026-11-02" should read "Awaiting payment"

  # E222 — Edge case: by default the dealing list hides generated dates with nothing on them, keeping the next date still taking orders; All dates shows the rest.
  @rack_test
  Scenario: The dealing list hides empty dates by default
    Given today is "2026-11-02"
    When the dealing dates are generated
    And I open the dealing list
    Then the dealing list should show the next date still taking orders
    And the dealing list should not show "2027-01-01"
    When I open the dealing list filtered to "All dates"
    Then the dealing list should show "2027-01-01" with cut-off "2026-12-27" at step "○ Open for orders"

  # H17, H18 — Happy path: a paid pre-funded subscription puts 2 Nov at "Review and confirm dealing" and ₹5,00,00,000 at ₹10,220 prices to 4,892.3679 units.
  @rack_test
  Scenario: Pre-funded steps and subscription pricing
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing list
    Then the dealing list should show "2026-11-02" with cut-off "2026-10-28" at step "● Review and confirm dealing"
    And the pricing of "2026-11-02" should allot "4,892.3679" units to "P Family Trust"

  # H21 — Happy path: confirming creates both settlements, fills A and B up to the 5 % gate and sends gate notices, not call or distribution notices.
  Scenario: Confirm creates the settlements and sends gate notices, not call notices
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the email queue is cleared
    When I open the dealing date "2026-11-02"
    And I confirm the dealing date
    Then I should see "Dealing date confirmed"
    And the dealing date "2026-11-02" should be "confirmed"
    And the subscription settlement of "2026-11-02" should have unit price "10,220" for class "A"
    And the redemption settlement of "2026-11-02" should have "2" payments due "2026-11-16"
    And the fills of dealing date "2026-11-02" should be:
      | investor | units     | amount      |
      | A Ltd    | 2935.4207 | 3,00,00,000 |
      | B LLP    | 2064.5793 | 2,11,00,000 |
    And the order of "B LLP" should be "partially_filled" on dealing date "2026-12-01"
    And "B LLP" received a gate notice
    And "C HUF" received a gate notice
    And no capital call or distribution notice was sent

  # H26 — Happy path: B LLP's carried redemption keeps its received time and stays ahead of D Partners' newer request on 1 Dec.
  @rack_test
  Scenario: A carried redemption heads the next queue
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    And class "A" of the fund has "notice_days=7"
    And "D Partners" holds "4000" units of class "A" in folio "F-050" issued "2025-09-01"
    And "D Partners" has placed a "redemption" order "folio=F-050;units=100" received "2026-11-10 10:00"
    Then in the queue of "2026-12-01" "B LLP" should be ahead of "D Partners"

  # E6 — Edge case: raising the gate to 10 % after 2 Nov is confirmed leaves 2 Nov's stored gate at 5 %.
  @rack_test
  Scenario: Changing the gate applies forward only
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When the fund setting changes to "gate_pct=10"
    Then the confirmed gate of "2026-11-02" should be "5"%

  # E21 — Edge case: a subscription whose journey still waits on the signed form is listed as not ready and rolls to 1 Dec at confirmation.
  @rack_test
  Scenario: An order not ready at the cut-off is rolled
    Given the fund setting has "order_journeys=subscriptions"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-10-20"
    And "P Family Trust" has a verified KYC
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should list "P Family Trust" as "Not ready — waiting on: Collect signed subscription form — will roll to 01 December 2026"
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-12-01"

  # E22 — Edge case: a redemption not accepted by the cut-off rolls to 1 Dec but keeps its queue place ahead of a newer request.
  @rack_test
  Scenario: A rolled redemption keeps its queue place
    Given the fund setting has "order_journeys=both"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-20 09:00"
    And the order of "B LLP" is verified and accepted
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    And class "A" of the fund has "notice_days=7"
    And "D Partners" holds "4000" units of class "A" in folio "F-050" issued "2025-09-01"
    And "D Partners" has placed a "redemption" order "folio=F-050;units=100" received "2026-11-10 10:00"
    And the order of "D Partners" is verified and accepted
    Then the order of "A Ltd" should be "pending" on dealing date "2026-12-01"
    And in the queue of "2026-12-01" "A Ltd" should be ahead of "D Partners"

  # E23 — Edge case: a dealing date with subscriptions only creates no redemption settlement.
  Scenario: Subscriptions only creates no redemption settlement
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the dealing date "2026-11-02" should have no redemption settlement

  # E24 — Edge case: an unpaid pre-funded subscription rolls to 1 Dec and its payment row moves to the 1 Dec settlement.
  @rack_test
  Scenario: An unpaid pre-funded subscription is rolled with its payment row
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-10-25"
    And "P Family Trust" has placed a "subscription" order "amount=25000000" received "2026-10-25 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should list "P Family Trust" as "Not paid by cut-off — will roll to 01 December 2026"
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-12-01"
    And the subscription payment of "P Family Trust" should be in the settlement of "2026-12-01"

  # E25 — Edge case: with unready handling "cancel", a subscription still waiting on its journey (now the signed
  # form: KYC must be approved before ordering — evergreen-folio-soa X1) is cancelled at confirmation.
  @rack_test
  Scenario: A not-ready order is cancelled when the fund cancels
    Given the fund setting has "order_journeys=subscriptions;unready_handling=cancel"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should list "P Family Trust" as "Not ready — waiting on: Collect signed subscription form — will be cancelled"
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "P Family Trust" should be "cancelled" on dealing date "2026-11-02"

  # E26 — Edge case: a dealing date with no orders shows "No orders on …" and Confirm is disabled.
  @rack_test
  Scenario: Nothing to deal
    Given today is "2026-12-15"
    And the fund admin logs in
    When I open the dealing date "2027-01-01"
    Then I should see "No orders on 01 January 2027"
    And the confirm button should be disabled

  # E33 — Edge case: undoing a pay-after date before any money arrives reopens it and returns the subscription to pending with no folio.
  @rack_test
  Scenario: Undo before anything settles
    Given the fund setting has "payment_timing=after"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When I open the dealing date "2026-11-02"
    And I undo the dealing date
    Then I should see "Confirmation undone"
    And the dealing date "2026-11-02" should be "open"
    And the order of "P Family Trust" should be "pending" on dealing date "2026-11-02"
    And "P Family Trust" should have no folio in the fund

  # E34 — Edge case: an all-units redemption counts units allotted after the request (2,000 + 200 = 2,200) at confirmation.
  @rack_test
  Scenario: An all-units redemption counts units at confirmation
    Given the fund setting has "gate_pct=0"
    And today is "2026-09-10"
    And "C HUF" has placed a "redemption" order "folio=F-044;all_units=true" received "2026-09-10 09:00"
    And "C HUF" holds "200" units of class "A" in folio "F-044" issued "2026-10-15"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the fills of dealing date "2026-11-02" should be:
      | investor | units |
      | C HUF    | 2200  |

  # X17 — Error case: Confirm is disabled while the 31 Oct NAV is still a draft, naming the NAV to approve.
  @rack_test
  Scenario: Confirm needs an approved NAV
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And a draft NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then I should see "Approve the NAV for Class A dated 31 October 2026 first"
    And the confirm button should be disabled

  # X20 — Error case: confirm is refused with "Pricing changed — review again" when an order was cancelled after the preview.
  @rack_test
  Scenario: Confirm refuses when pricing changed since the preview
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=1000000" received "2026-10-20 10:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And the fund setting has "payment_timing=after"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02" with a stale preview
    Then the confirm should be refused with "Pricing changed — review again"

  # E102 — Edge case: a subscription received at 23:59 on the cut-off day (28 Oct) still makes 2 Nov, while one received at 00:00 the next day moves to 1 Dec.
  @rack_test
  Scenario: The cut-off is inclusive to the last minute of the day
    Given today is "2026-10-29"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-28 23:59"
    And "B LLP" has placed a "subscription" order "amount=50000000" received "2026-10-29 00:00"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-11-02"
    And the order of "B LLP" should be "pending" on dealing date "2026-12-01"

  # E103 — Edge case: an approved NAV dated after the dealing date (3 Nov) is ignored; 2 Nov prices at the latest NAV on or before it (31 Aug, ₹10,000), so ₹5,00,00,000 buys 5,000 units.
  @rack_test
  Scenario: A NAV dated after the dealing date is not used for pricing
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-11-03" with NAV per unit "10,500" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should allot "5,000.0000" units to "P Family Trust"
    When the fund admin confirms dealing date "2026-11-02"
    Then the subscription settlement of "2026-11-02" should have unit price "10,000" for class "A"

  # E105 — Edge case: an all-units redemption on 1 Dec excludes the 500 units already dealt but unpaid on 2 Nov, so it asks for 2,000 − 500 = 1,500 units.
  @rack_test
  Scenario: An all-units redemption excludes units dealt but not yet paid on an earlier date
    Given the fund setting has "gate_pct=0"
    And today is "2026-09-10"
    And "C HUF" has placed a "redemption" order "folio=F-044;units=500" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    And class "A" of the fund has "notice_days=7"
    And "C HUF" has placed a "redemption" order "folio=F-044;all_units=true" received "2026-11-10 10:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,220" and units "100000"
    And today is "2026-12-01"
    Then the pricing of "2026-12-01" should fill:
      | investor | filled      | carried | units |
      | C HUF    | 1,53,30,000 | 0       | 1500  |

  # E106 — Edge case: undo returns a fully filled redemption, a carried redemption (moved to 1 Dec) and a cancelled not-ready subscription all to pending on 2 Nov.
  @rack_test
  Scenario: Undo restores carried and cancelled orders to the dealing date
    Given the fund setting has "order_journeys=subscriptions;unready_handling=cancel"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And the order of "B LLP" should be "partially_filled" on dealing date "2026-12-01"
    And the order of "P Family Trust" should be "cancelled" on dealing date "2026-11-02"
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should succeed
    And the dealing date "2026-11-02" should be "open"
    And the dealing date "2026-11-02" should have "0" fills
    And the dealing date "2026-11-02" should have no redemption settlement
    And the order of "A Ltd" should be "pending" on dealing date "2026-11-02"
    And the order of "B LLP" should be "pending" on dealing date "2026-11-02"
    And the order of "P Family Trust" should be "pending" on dealing date "2026-11-02"
    And the order of "P Family Trust" should have no cancellation recorded

  # E107 — Edge case: a subscriptions-only date whose units were allotted and contract note emailed at confirmation can be closed at once, and a closed date cannot be undone.
  @rack_test
  Scenario: Close once every step is done, then undo is refused
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When the fund admin closes dealing date "2026-11-02"
    Then the close should succeed
    And the dealing date "2026-11-02" should be "closed"
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should be refused with "Only a confirmed dealing date can be undone"
    And the dealing date "2026-11-02" should be "closed"

  # E108 — Edge case: a part-paid pre-funded subscription (₹1 Cr of ₹5 Cr received) is rolled, not cancelled, even when the fund cancels unready orders — and the preview must say so.
  @rack_test
  Scenario: A part-paid subscription rolls under cancel handling, and the preview says it will
    Given the fund setting has "unready_handling=cancel"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid "1,00,00,000" of the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should list "P Family Trust" as "Not paid by cut-off — will roll to 01 December 2026"
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-12-01"
    And the subscription payment of "P Family Trust" should be in the settlement of "2026-12-01"

  # E109 — Edge case: when the custom redemption calendar has no date after 2 Nov, B LLP's gated remainder (₹39,00,000) cannot be carried, so the order closes as dealt on what was filled, saying why.
  @rack_test
  Scenario: A gated redemption with no later redemption date is closed on its fill
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And the fund setting has "redemption_calendar=custom;redemption_dates=2026-11-02"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the fills of dealing date "2026-11-02" should be:
      | investor | units     | amount      |
      | A Ltd    | 2935.4207 | 3,00,00,000 |
      | B LLP    | 2064.5793 | 2,11,00,000 |
    And the order of "B LLP" should be "dealt" on dealing date "2026-11-02"
    And the reason of the order of "B LLP" should be "No later redemption date in the calendar — the rest was not carried"
    And "B LLP" receives an email with subject "Alpha Long-Short Fund: Redemption partly filled" containing "Not carried"

  # E196 — Edge case: a dealing date with only a subscription still shows the fund gate on the whole fund's NAV — 5% of ₹102,20,00,000 (1,00,000 units × ₹10,220) = ₹5,11,00,000.00 — not "= ₹0.00".
  @rack_test
  Scenario: The gate summary uses the whole fund's NAV even with no redemptions
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the gate card should show "₹5,11,00,000.00" with "Gate · 5% of NAV"

  # E110 — Edge case: a not-ready redemption with no later redemption date in the calendar is cancelled (not rolled) even though the fund rolls unready orders.
  @rack_test
  Scenario: A not-ready order with no later dealing date is cancelled
    Given the fund setting has "order_journeys=both"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-09-20 09:00"
    And the order of "B LLP" is verified and accepted
    And the fund setting has "redemption_calendar=custom;redemption_dates=2026-11-02"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should list "A Ltd" with fate "will be cancelled — no later redemption date in the calendar"
    When the fund admin confirms dealing date "2026-11-02"
    Then the order of "A Ltd" should be "cancelled" on dealing date "2026-11-02"
    And the reason of the order of "A Ltd" should end with "— no later redemption date in the calendar"
    And the order of "B LLP" should be "dealt" on dealing date "2026-11-02"

  # X56 — Error case: a second confirm from a copy loaded before the first confirm (double click / two tabs) is refused with "This dealing date is already confirmed" and stores no second set of fills.
  @rack_test
  Scenario: Confirming twice is refused
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And a second admin has dealing date "2026-11-02" open
    And the fund admin confirms dealing date "2026-11-02"
    When the second admin confirms their copy
    Then the confirm should be refused with "This dealing date is already confirmed"
    And the dealing date "2026-11-02" should have "1" fills

  # E181 — Edge case: a dealing date whose only order is an unpaid pre-funded subscription is still confirmable — nothing is priced, the order rolls to 01 December 2026, and the workspace says so (decision 2026-10-08).
  @rack_test
  Scenario: Only not-ready orders — confirming rolls them
    Given today is "2026-10-25"
    And "P Family Trust" has placed a "subscription" order "amount=25000000" received "2026-10-25 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then I should see "Nothing to price on 02 November 2026"
    And I should see "will roll to 01 December 2026"
    When the fund admin confirms dealing date "2026-11-02"
    Then the dealing date "2026-11-02" should be "confirmed"
    And the order of "P Family Trust" should be "pending" on dealing date "2026-12-01"

  # X58 — Error case: undoing 2 Nov after 1 Dec has dealt the redemptions carried from it is refused until 1 Dec is undone first; then 2 Nov undoes and B LLP returns to 2 Nov.
  @rack_test
  Scenario: Undo is refused while a moved order has been dealt on a later date
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;amount=10000000" received "2026-09-19 11:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,220" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should be refused with "Orders moved on from this date have since been dealt on a later date — undo that date first"
    And the dealing date "2026-11-02" should be "confirmed"
    When the fund admin undoes dealing date "2026-12-01"
    Then the undo should succeed
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should succeed
    And the order of "B LLP" should be "pending" on dealing date "2026-11-02"
    And the order of "C HUF" should be "pending" on dealing date "2026-11-02"

  # X59 — Error case: once a pre-funded subscription's units are allotted at confirmation, Undo is disabled and a direct undo is refused with "Units allotted or payments recorded — reverse them first" (covers design row X18).
  @rack_test
  Scenario: Undo after units are allotted
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the undo button should be disabled with "Units allotted or payments recorded — reverse them first"
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should be refused with "Units allotted or payments recorded — reverse them first"
    And the dealing date "2026-11-02" should be "confirmed"

  # X60 — Error case: undoing a dealing date that was never confirmed is refused with "Only a confirmed dealing date can be undone".
  @rack_test
  Scenario: Undo of an open dealing date is refused
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-11-02"
    When the fund admin undoes dealing date "2026-11-02"
    Then the undo should be refused with "Only a confirmed dealing date can be undone"
    And the dealing date "2026-11-02" should be "open"

  # X61 — Error case: closing a confirmed date whose redemption is not yet paid is refused with "Finish settling this dealing date before closing it".
  @rack_test
  Scenario: Close before redemptions are paid is refused
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When the fund admin closes dealing date "2026-11-02"
    Then the close should be refused with "Finish settling this dealing date before closing it"
    And the dealing date "2026-11-02" should be "confirmed"

  # X62 — Error case: an investor's portal user who requests the dealing-date workspace directly is denied, and may not confirm it.
  Scenario: An investor cannot open or confirm a dealing date
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When "A Ltd" logs in to the portal
    And I open the dealing date "2026-11-02"
    Then I should not see the dealing date workspace
    And the portal user of "A Ltd" may not confirm dealing date "2026-11-02"

  # E208 — Edge case: a dealing date with only a subscription opens on the Subscriptions tab with its count; the empty Redemptions tab says so.
  @rack_test
  Scenario: The pricing tabs count orders and open on subscriptions
    Given today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the dealing tab "Subscriptions (1)" should be active
    And the dealing tab "Redemptions (0)" should not be active
    And I should see "No redemptions to price for this redemption date."

  # E209 — Edge case: a dealing date with only redemptions opens on the Redemptions tab, so the queue is the first thing shown.
  @rack_test
  Scenario: The pricing tabs open on redemptions when there are no subscriptions
    # Received inside the notice period it would move to the next redemption date, so it is placed in September
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=2000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the dealing tab "Redemptions (1)" should be active
    And the dealing tab "Subscriptions (0)" should not be active

  # E210 — Edge case: redemptions on a date are summarised as cards — gate, requested, what will be paid with its %, and what will be carried and to which date.
  @rack_test
  Scenario: The redemptions tab summarises the gate as cards
    # Received inside the notice period it would move to the next redemption date, so it is placed in September
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=12000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the gate card should show "₹5,11,00,000.00" with "Gate · 5% of NAV · FIFO"
    And the gate cards should show "Requested"
    And the gate cards should show "Will be paid · "
    And the gate cards should show "Will be carried to 01/12/2026"

  # E221 — Edge case: before confirming, the dealing date says it is a preview and each redemption row says what will happen — the same rows as the fund's Redemptions list.
  @rack_test
  Scenario: The dealing date's redemptions read as a preview
    # Received inside the notice period it would move to the next redemption date, so it is placed in September
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=12000" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then I should see "Preview — nothing is allotted, paid, carried or cancelled until you click Confirm dealing date."
    And the dealing redemption row of "A Ltd" should show "Will be part-filled"
    And the dealing redemption row of "A Ltd" should show "5,000.0000"
