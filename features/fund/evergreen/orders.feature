Feature: Evergreen orders — subscribe, redeem, queue, cancel, admin entry and upload
  Worked examples H7–H11, E3, E4, E5, E13–E16, E18, E80–E96, X10–X16, X40–X53 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on

  # H7 — Happy path: an investor subscribes through the wizard before the cut-off, sees indicative units and payment instructions, and the order is pending for 2 Nov 2026
  Scenario: Investor subscribes through the wizard (pre-funded)
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;payment_instructions=Alpha LSF Collection A/c"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "9,980.69" and units "98450"
    And "P Family Trust" is an investor of the fund with a portal user
    When "P Family Trust" logs in to the portal
    And I start a "subscription" for the fund
    And I fill the order with "amount=50000000"
    And I check the order
    Then I should see "Indicative units ≈ 5,009.6736"
    And I should see "Indicative — final price is the NAV for 30/09/2026"
    When I submit the order
    Then I should see "Subscription request received"
    And I should see "by 28/10/2026 to be dealt on 02/11/2026"
    And I should see "Alpha LSF Collection A/c"
    And the latest order should be:
      | status       | pending    |
      | dealing_date | 2026-11-02 |
      | folio        | F-101      |
    And "P Family Trust" receives an email with subject "Alpha Long-Short Fund: Subscription received" containing "Oct 28, 2026"

  # H8 — Happy path: in a pay-after-dealing fund the acknowledgement promises payment instructions after the dealing date and opens no folio
  @rack_test
  Scenario: Pay-after-dealing acknowledgement
    Given today is "2026-11-10"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    When I start a "subscription" for the fund
    And I fill the order with "investor=Q Capital;amount=25000000"
    And I submit the order
    Then I should see "You'll receive payment instructions after the 01/12/2026 subscription date, with the exact units"
    And the latest order should be:
      | dealing_date | 2026-12-01 |
      | folio        |            |

  # H9 — Happy path: an investor redeems 2,000 units, seeing the indicative value at the latest NAV and queue position #3
  Scenario: Investor redeems a number of units with an indicative value and queue position
    Given today is "2026-12-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "9064.5793" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "4935.4207" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,160.94" and units "99892.3679"
    # Review fix 7: the queue is per dealing date, so B LLP and C HUF ask on 30 Nov — the same 1 Jan 2027
    # redemption date A Ltd's request joins — to put A Ltd third
    And "B LLP" has placed a "redemption" order "folio=F-031;units=381.6047" received "2026-11-30 09:15"
    And "C HUF" has placed a "redemption" order "folio=F-044;units=978.4736" received "2026-11-30 11:30"
    When "A Ltd" logs in to the portal
    And I start a "redemption" for the fund
    And I fill the order with "folio=F-012;units=2000"
    And I check the order
    Then I should see "2,03,21,880"
    And I should see "#3"
    When I submit the order
    Then I should see "Redemption request received for 2,000 units"
    And the latest order should be:
      | status         | pending    |
      | dealing_date   | 2027-01-01 |
      | queue_position | 3          |

  # H10 — Happy path: open redemptions are queued by received time (09:00, 10:00, 11:00 → #1, #2, #3)
  @rack_test
  Scenario: Queue positions follow received time
    Given today is "2026-10-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "C HUF" holds "2000" units of class "A" in folio "F-044" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-01 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-10-01 10:00"
    And "C HUF" has placed a "redemption" order "folio=F-044;units=100" received "2026-10-01 11:00"
    When I open the order book
    Then the order of "A Ltd" should show queue position "1"
    And the order of "B LLP" should show queue position "2"
    And the order of "C HUF" should show queue position "3"

  # H11 — Happy path: an investor cancels a pending subscription; it becomes Cancelled and the investor is emailed
  @rack_test
  Scenario: Investor cancels a pending subscription
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    When "P Family Trust" logs in to the portal
    And I open the latest order
    And I cancel the order
    Then I should see "Request cancelled"
    And the latest order should be:
      | status | cancelled |
    And "P Family Trust" receives an email with subject "Alpha Long-Short Fund: Request cancelled" containing "Alpha Long-Short Fund"

  # E3 — Edge case: with a custom redemption calendar the order lands on the next listed date (31 Mar 2027), not a monthly/quarterly one
  @rack_test
  Scenario: Custom redemption dates
    Given today is "2027-01-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund setting has "redemption_calendar=custom;redemption_dates=2027-03-31,2027-09-30"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2027-01-01 10:00"
    Then the latest order should be:
      | dealing_date | 2027-03-31 |

  # E4 — Edge case: a class-level notice period (90 days) overrides the fund's 30 days, so the same-day class B order lands a month later than class A
  @rack_test
  Scenario: A class override of the notice period
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A,B" and settings "redemption_calendar=monthly"
    And class "B" of the fund has "notice_days=90"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "1000" units of class "B" in folio "F-031" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    Then the latest order should be:
      | dealing_date | 2027-01-01 |
    Given "B LLP" has placed a "redemption" order "folio=F-031;units=100;class=B" received "2026-11-02 10:00"
    Then the latest order should be:
      | dealing_date | 2027-02-01 |

  # E5 — Edge case: under a fee schedule, units 7 months old pay 3% and units 17 months old pay 2% on the same dealing date
  @rack_test
  Scenario: Early-redemption fee by unit age
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "lock_up_months=24;lock_up_type=soft;early_fee_schedule=3:0-12, 2:12-24"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-04-01"
    And "B LLP" holds "100" units of class "A" in folio "F-031" issued "2025-06-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    Then the latest order should be:
      | early_fee_pct | 3 |
    Given "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-11-02 10:00"
    Then the latest order should be:
      | early_fee_pct | 2 |

  # E13 — Edge case: an investor who already holds units is held to the additional minimum (₹5,00,000), not the initial one, and exactly the minimum is accepted
  @rack_test
  Scenario: An additional subscription uses the additional minimum
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund setting has "min_initial_subscription=2500000;min_additional_subscription=500000"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=500000" received "2026-10-20 10:00"
    Then the latest order should be:
      | status | pending |

  # E14 — Edge case: a subscription received the day after the cut-off is moved to the following dealing date and the message names the missed cut-off
  @rack_test
  Scenario: A subscription after the cut-off moves to the following dealing date
    Given today is "2026-10-29"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    When I start a "subscription" for the fund
    And I fill the order with "investor=P Family Trust;amount=5000000"
    And I submit the order
    Then I should see "Received after the 28 October 2026 cut-off — dealt on 01 December 2026."
    And the latest order should be:
      | dealing_date | 2026-12-01 |

  # E15 — Edge case: a redemption inside the 30-day notice period of the 31 Dec dealing date moves to the next quarter (31 Mar 2027)
  @rack_test
  Scenario: A redemption inside the notice period moves to the next quarter
    Given today is "2026-12-15"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "dealing_day=last"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-12-15 10:00"
    Then the latest order should be:
      | dealing_date | 2027-03-31 |

  # E16 — Edge case: units still inside a soft lock-up on the dealing date are accepted and the 2% early-redemption fee is shown on all 1,200 units
  @rack_test
  Scenario: Units in a soft lock-up can be redeemed with a fee
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" holds "1200" units of class "A" in folio "F-012" issued "2026-03-15"
    When I start a "redemption" for the fund
    And I fill the order with "investor=A Ltd;folio=F-012;units=1200"
    And I submit the order
    Then I should see "An exit load of 2% applies to 1,200 units."

  # E18 — Edge case: a back-dated admin entry keeps its received time, so its dealing date is computed from 1 Oct, and it records who entered it
  @rack_test
  Scenario: A back-dated admin entry keeps its received time
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    When I start a "redemption" for the fund
    And I fill the order with "investor=B LLP;folio=F-031;units=500;received_at=2026-10-01 09:00"
    And I submit the order
    And I open the latest order
    Then I should see "Entered by Asha"
    And the latest order should be:
      | dealing_date | 2026-11-02 |

  # X10 — Error case: a new investor subscribing below the minimum initial subscription is refused with the minimum in the message
  @rack_test
  Scenario: Below the minimum initial subscription
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund setting has "min_initial_subscription=2500000"
    And "P Family Trust" is an investor of the fund with a portal user
    When I start a "subscription" for the fund
    And I fill the order with "investor=P Family Trust;amount=1000000"
    And I submit the order
    Then I should see "Minimum subscription is ₹25,00,000"

  # X11 — Error case: an order on a folio in a currency other than the fund's (USD vs INR) is refused
  @rack_test
  Scenario: A foreign-currency folio is refused
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And folio "F-012" is in "USD"
    When I start a "subscription" for the fund
    And I fill the order with "investor=A Ltd;folio=F-012;amount=1000000"
    And I submit the order
    Then I should see "Evergreen orders must be in the fund currency (INR)"

  # X12 — Error case: redeeming more units than are free after already-queued redemptions is refused, naming held and queued units
  @rack_test
  Scenario: Redeeming more units than are free
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2025-09-01"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=2000" received "2026-11-02 09:00"
    When I start a "redemption" for the fund
    And I fill the order with "investor=P Family Trust;folio=F-101;units=3000"
    And I submit the order
    Then I should see "You hold 4,892.37 units; 2,000 are already queued for redemption."

  # X13 — Error case: an upload row using a redemption form the fund doesn't allow (amount) fails with the allowed forms named
  @rack_test
  Scenario: A redemption form the fund doesn't allow is refused in an upload
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "redemption_forms=units,all"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When I upload the order rows:
      | Type       | Folio No | Investor | Unit Class | Amount | Units | All Units | Received At |
      | Redemption | F-012    | A Ltd    | A          | 100000 |       | No        |             |
    Then the order upload should have "1" failed rows
    And the order upload results should mention "This fund accepts redemptions in units or all units only"

  # X14 — Error case: units still in a hard lock-up on the dealing date are refused; the message names the unlock date
  @rack_test
  Scenario: Units in a hard lock-up cannot be redeemed
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "1200" units of class "A" in folio "F-012" issued "2026-03-15"
    When I start a "redemption" for the fund
    And I fill the order with "investor=A Ltd;folio=F-012;units=1200"
    And I submit the order
    Then I should see "1,200 of these units are locked until 15 March 2027."

  # X15 — Error case: a partial redemption that would leave less than the minimum holding at the latest NAV is refused
  @rack_test
  Scenario: A partial redemption may not leave less than the minimum holding
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "min_holding=5000000"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "1000"
    When I start a "redemption" for the fund
    And I fill the order with "investor=A Ltd;folio=F-012;units=600"
    And I submit the order
    Then I should see "This would leave ₹40,00,000, below the ₹50,00,000 minimum holding. Redeem all units instead."

  # X16 — Error case: an upload with one row over the free units creates the good row and reports the bad one
  @rack_test
  Scenario: An upload with one bad row creates the good one
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "100" units of class "A" in folio "F-031" issued "2025-09-01"
    When I upload the order rows:
      | Type       | Folio No | Investor | Unit Class | Amount | Units | All Units | Received At |
      | Redemption | F-012    | A Ltd    | A          |        | 100   | No        |             |
      | Redemption | F-031    | B LLP    | A          |        | 500   | No        |             |
    Then the order upload should have "1" failed rows
    And the order upload results should mention "You hold 100 units"

  # ---- Lock-up edge cases ----

  # E80 — Edge case: a folio with a free lot and a soft-locked lot redeems oldest first, so the 2% fee falls only on the 100 units taken from the locked lot
  @rack_test
  Scenario: Mixed free and soft-locked lots — fee only on the locked part
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "300" units of class "A" in folio "F-012" issued "2026-06-01"
    When I start a "redemption" for the fund
    And I fill the order with "investor=A Ltd;folio=F-012;units=600"
    And I submit the order
    Then I should see "An exit load of 2% applies to 100 units."
    And the order of "A Ltd" should record an early-redemption fee of "2"% on "100" units

  # X40 — Error case: the same mixed lots under a hard lock-up are refused for only the 100 units the free lot can't cover, naming the locked lot's unlock date
  @rack_test
  Scenario: Mixed free and hard-locked lots — only the locked shortfall is refused
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "300" units of class "A" in folio "F-012" issued "2026-06-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=600" received "2026-11-02 10:00"
    Then the order should be refused with "100 of these units are locked until 01 June 2027."
    When "A Ltd" tries a "redemption" order "folio=F-012;units=500" received "2026-11-02 10:00"
    Then the order should be accepted

  # X41 — Error case: a past redemption is netted against the oldest lot first, so after redeeming 400 of the old 500 only 100 units are free and a 200-unit order is refused
  @rack_test
  Scenario: Past redemptions are netted before lots are classified
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2026-06-01"
    And "A Ltd" redeemed "400" units of class "A" from folio "F-012" on "2026-07-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=200" received "2026-11-02 10:00"
    Then the order should be refused with "100 of these units are locked until 01 June 2027."
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    Then the order should be accepted

  # E81 — Edge case: a lot whose lock-up ends exactly on the dealing date (1 Feb 2027) counts as free, so the hard lock-up does not refuse it
  @rack_test
  Scenario: Dealing date exactly on the unlock date
    Given today is "2026-12-15"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-02-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100" received "2026-12-15 10:00"
    Then the order should be accepted
    And the latest order should be:
      | status       | pending    |
      | dealing_date | 2027-02-01 |
    And the order of "A Ltd" should have no early-redemption fee

  # X42 — Error case: a lot that unlocks one day after the dealing date (2 Feb vs 1 Feb 2027) is still locked and refused
  @rack_test
  Scenario: Dealing date one day before the unlock date
    Given today is "2026-12-15"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-02-02"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100" received "2026-12-15 10:00"
    Then the order should be refused with "100 of these units are locked until 02 February 2027."

  # E82 — Edge case: units still locked when the order is placed (2 Nov 2026) but free by its dealing date (1 Jan 2027, unlock 15 Dec 2026) are accepted — lock-up is judged at the dealing date
  @rack_test
  Scenario: Locked when placed, free by the dealing date
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2025-12-15"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    Then the order should be accepted
    And the latest order should be:
      | dealing_date | 2027-01-01 |
    And the order of "A Ltd" should have no early-redemption fee

  # E83 — Edge case: class lock-up terms override the fund's 12-month hard lock-up — class B is soft with its own 1% fee, class C has no lock-up (0 months), class A keeps the fund's hard lock-up
  @rack_test
  Scenario: A class-level lock-up overrides the fund's
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A,B,C" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And class "B" of the fund has "lock_up_type=soft;early_fee_pct=1"
    And class "C" of the fund has "lock_up_months=0"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-06-01"
    And "B LLP" holds "100" units of class "B" in folio "F-031" issued "2026-06-01"
    And "C HUF" holds "100" units of class "C" in folio "F-044" issued "2026-06-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    Then the order should be refused with "100 of these units are locked until 01 June 2027."
    When "B LLP" tries a "redemption" order "folio=F-031;units=100;class=B" received "2026-11-02 10:00"
    Then the order should be accepted
    And the order of "B LLP" should record an early-redemption fee of "1"% on "100" units
    When "C HUF" tries a "redemption" order "folio=F-044;units=100;class=C" received "2026-11-02 10:00"
    Then the order should be accepted
    And the order of "C HUF" should have no early-redemption fee

  # E84 — Edge case: an all-units redemption reaches into the soft-locked lot, so the fee applies to the 300 locked units only
  @rack_test
  Scenario: All-units redemption reaching soft-locked units
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "300" units of class "A" in folio "F-012" issued "2026-06-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;all_units=true" received "2026-11-02 10:00"
    Then the order should be accepted
    And the order of "A Ltd" should record an early-redemption fee of "2"% on "300" units

  # X43 — Error case: an all-units redemption under a hard lock-up is refused for the 300 locked units
  @rack_test
  Scenario: All-units redemption reaching hard-locked units
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "300" units of class "A" in folio "F-012" issued "2026-06-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;all_units=true" received "2026-11-02 10:00"
    Then the order should be refused with "300 of these units are locked until 01 June 2027."

  # E85 — Edge case: an amount redemption of ₹60,00,000 at ₹10,000 per unit resolves to 600 units, 100 of them from the soft-locked lot, which alone carry the fee
  @rack_test
  Scenario: Amount redemption reaching soft-locked units
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" holds "500" units of class "A" in folio "F-012" issued "2025-06-01"
    And "A Ltd" holds "300" units of class "A" in folio "F-012" issued "2026-06-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "800"
    When "A Ltd" tries a "redemption" order "folio=F-012;amount=6000000" received "2026-11-02 10:00"
    Then the order should be accepted
    And the order of "A Ltd" should record an early-redemption fee of "2"% on "100" units

  # X44 — Error case: with two hard-locked lots (unlocking 1 Mar and 1 Jun 2027) a redemption of both is refused naming the later date, when all 200 units are free
  @rack_test
  Scenario: Two hard-locked lots name the later unlock date
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=hard"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-03-01"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-06-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=200" received "2026-11-02 10:00"
    Then the order should be refused with "200 of these units are locked until 01 June 2027."

  # E86 — Edge case: under a 3% (0–12 months) / 2% (12–24 months) schedule, a lot 18 months old pays 2% and a lot 3 months old pays 3% — ₹20,000 + ₹30,000 = ₹50,000
  @rack_test
  Scenario: Each soft-locked lot pays the fee for its own age
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=24;lock_up_type=soft"
    And the fund setting has "early_fee_schedule=3:0-12, 2:12-24"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2025-07-01"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-10-01"
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "10,000" and units "200"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=200" received "2026-11-02 10:00"
    Then the order should be accepted
    And the pricing of "2027-01-01" should charge "A Ltd" an early-redemption fee of "50,000"

  # E87 — Edge case: a soft-locked redemption rolled from 1 Jan to 1 Feb 2027 is re-judged at the new date; its lot unlocked on 15 Jan 2027, so no fee is charged
  @rack_test
  Scenario: A rolled redemption is re-judged for lock-up at its new dealing date
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft;order_journeys=both"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" holds "100" units of class "A" in folio "F-012" issued "2026-01-15"
    And "B LLP" holds "1000" units of class "A" in folio "F-031" issued "2025-01-01"
    And an approved NAV for class "A" on "2026-12-31" with NAV per unit "10,000" and units "1100"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-11-02 10:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-11-02 10:00"
    Then the order of "A Ltd" should record an early-redemption fee of "2"% on "100" units
    Given the order of "B LLP" is verified and accepted
    And today is "2027-01-01"
    When the fund admin confirms dealing date "2027-01-01"
    Then the order of "A Ltd" should be "pending" on dealing date "2027-02-01"
    Given the order of "A Ltd" is verified and accepted
    # Decision 4: 1 Jan already priced at the 31 Dec NAV, so 1 Feb needs a newer one
    And an approved NAV for class "A" on "2027-01-31" with NAV per unit "10,000" and units "1000"
    Then the pricing of "2027-02-01" should charge "A Ltd" an early-redemption fee of "0"

  # ---- Minimums, free units and forms ----

  # E88 — Edge case: a new investor subscribing exactly the minimum initial subscription (₹25,00,000) is accepted
  @rack_test
  Scenario: Subscription exactly at the minimum initial subscription
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund setting has "min_initial_subscription=2500000"
    And "P Family Trust" is an investor of the fund with a portal user
    When "P Family Trust" tries a "subscription" order "amount=2500000" received "2026-10-20 09:00"
    Then the order should be accepted
    And the latest order should be:
      | status | pending |

  # X45 — Error case: a zero or negative subscription is refused, and one rupee below either minimum (initial for a new investor, additional for a holder) is refused
  @rack_test
  Scenario: Subscription amounts at and below the limits
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund setting has "min_initial_subscription=2500000;min_additional_subscription=500000"
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When "P Family Trust" tries a "subscription" order "amount=0" received "2026-10-20 09:00"
    Then the order should be refused with "Enter an amount greater than zero"
    When "P Family Trust" tries a "subscription" order "amount=-100000" received "2026-10-20 09:00"
    Then the order should be refused with "Enter an amount greater than zero"
    When "P Family Trust" tries a "subscription" order "amount=2499999" received "2026-10-20 09:00"
    Then the order should be refused with "Minimum subscription is ₹25,00,000"
    When "A Ltd" tries a "subscription" order "folio=F-012;amount=499999" received "2026-10-20 09:00"
    Then the order should be refused with "Minimum subscription is ₹5,00,000"

  # E89 — Edge case: redeeming exactly the free units (4,892.3679 held − 2,000 queued = 2,892.3679) is accepted
  @rack_test
  Scenario: Redeeming exactly the units left after queued orders
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2025-09-01"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=2000" received "2026-11-02 09:00"
    When "P Family Trust" tries a "redemption" order "folio=F-101;units=2892.3679" received "2026-11-02 10:00"
    Then the order should be accepted

  # X48 — Error case: asking for 0.0001 of a unit more than is free (2,892.368) is refused
  @rack_test
  Scenario: Redeeming a fraction of a unit more than is free
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "P Family Trust" holds "4892.3679" units of class "A" in folio "F-101" issued "2025-09-01"
    And "P Family Trust" has placed a "redemption" order "folio=F-101;units=2000" received "2026-11-02 09:00"
    When "P Family Trust" tries a "redemption" order "folio=F-101;units=2892.368" received "2026-11-02 10:00"
    Then the order should be refused with "You hold 4,892.37 units; 2,000 are already queued for redemption."

  # E95 — Edge case: a partial redemption leaving exactly the minimum holding (500 × ₹10,000 = ₹50,00,000) is accepted, and one taking every unit without ticking all units leaves nothing and is accepted
  @rack_test
  Scenario: Minimum holding met exactly, or nothing left
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "min_holding=5000000"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "1000" units of class "A" in folio "F-031" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "2000"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=500" received "2026-11-02 10:00"
    Then the order should be accepted
    When "B LLP" tries a "redemption" order "folio=F-031;units=1000" received "2026-11-02 10:00"
    Then the order should be accepted

  # X46 — Error case: the minimum-holding check counts orders already queued — after 300 queued, another 300 would leave 400 × ₹10,000 = ₹40,00,000 and is refused
  @rack_test
  Scenario: Minimum holding counts queued redemptions
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "min_holding=5000000"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,000" and units "1000"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=300" received "2026-11-02 09:00"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=300" received "2026-11-02 10:00"
    Then the order should be refused with "This would leave ₹40,00,000, below the ₹50,00,000 minimum holding. Redeem all units instead."

  # X47 — Error case: a redemption giving both units and an amount, or neither, is refused
  @rack_test
  Scenario: A redemption must give exactly one form
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100;amount=1000000" received "2026-11-02 10:00"
    Then the order should be refused with "Enter units, amount or all units — only one"
    When "A Ltd" tries a "redemption" order "folio=F-012" received "2026-11-02 10:00"
    Then the order should be refused with "Enter units, amount or all units — only one"

  # X126 — Error case: a redemption giving a number of units AND ticking "all units" is refused — it is no longer silently treated as all units.
  @rack_test
  Scenario: Units together with all units is refused
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=100;all_units=true" received "2026-11-02 10:00"
    Then the order should be refused with "Enter units, amount or all units — only one"

  # X49 — Error case: a redemption of zero or negative units is refused
  @rack_test
  Scenario: Zero or negative units cannot be redeemed
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;units=-100" received "2026-11-02 10:00"
    Then the order should be refused
    When "A Ltd" tries a "redemption" order "folio=F-012;units=0" received "2026-11-02 10:00"
    Then the order should be refused

  # X50 — Error case: an amount redemption before any NAV is approved can't be turned into units and is refused
  Scenario: Amount redemption with no approved NAV
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When "A Ltd" tries a "redemption" order "folio=F-012;amount=1000000" received "2026-11-02 10:00"
    Then the order should be refused with "No approved NAV yet — enter units or try after the next NAV is approved"

  # X52 — Error case: a subscription in a class with no initial price, or in a class the fund doesn't have, is refused
  @rack_test
  Scenario: Class checks
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A,B"
    And class "B" of the fund has "initial_price_cents="
    And "P Family Trust" is an investor of the fund with a portal user
    When "P Family Trust" tries a "subscription" order "amount=5000000;class=B" received "2026-10-20 09:00"
    Then the order should be refused with "Class B has no initial price yet"
    When "P Family Trust" tries a "subscription" order "amount=5000000;class=Z" received "2026-10-20 09:00"
    Then the order should be refused with "Choose an investor, a class and subscription or redemption"

  # ---- Dealing date boundaries ----

  # E90 — Edge case: a redemption received at 23:59 on the notice deadline (2 Dec, 30 days before 1 Jan 2027) makes 1 Jan; one received at 00:00 the next day goes to 1 Feb 2027
  @rack_test
  Scenario: Redemption at the notice deadline
    Given today is "2026-12-03"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "1000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-12-02 23:59"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-12-03 00:00"
    Then the order of "A Ltd" should be "pending" on dealing date "2027-01-01"
    And the order of "B LLP" should be "pending" on dealing date "2027-02-01"

  # E91 — Edge case: a subscription received at 23:59 on the cut-off day (28 Oct, 5 days before 2 Nov 2026) makes 2 Nov; one at 00:00 on 29 Oct goes to 1 Dec 2026
  @rack_test
  Scenario: Subscription at the cut-off
    Given today is "2026-10-29"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Q Capital" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-28 23:59"
    And "Q Capital" has placed a "subscription" order "amount=5000000" received "2026-10-29 00:00"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-11-02"
    And the order of "Q Capital" should be "pending" on dealing date "2026-12-01"

  # E92 — Edge case: a back-dated entry whose dealing date (2 Nov 2026) is already confirmed moves to the next open dealing date (1 Dec 2026)
  @rack_test
  Scenario: A back-dated entry skips a confirmed dealing date
    Given today is "2026-11-05"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the fund has a confirmed dealing date on "2026-11-02"
    And "P Family Trust" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    Then the order of "P Family Trust" should be "pending" on dealing date "2026-12-01"

  # ---- Queue and cancel ----

  # E93 — Edge case: cancelling a queued redemption of every unit frees those units, so a new order for all 1,000 is accepted
  @rack_test
  Scenario: A cancelled redemption no longer holds its units
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1000" received "2026-11-02 09:00"
    When the order of "A Ltd" is cancelled directly
    Then cancelling succeeds
    When "A Ltd" tries a "redemption" order "folio=F-012;units=1000" received "2026-11-02 10:00"
    Then the order should be accepted

  # E94 — Edge case: two redemptions received at the same second are queued by creation order
  @rack_test
  Scenario: Queue tie on the received time
    Given today is "2026-10-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "1000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "B LLP" has placed a "redemption" order "folio=F-031;units=100" received "2026-10-01 09:00"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-10-01 09:00"
    When I open the order book
    Then the order of "B LLP" should show queue position "1"
    And the order of "A Ltd" should show queue position "2"

  # X53 — Error case: an order can't be cancelled twice, and a subscription with money received can't be cancelled
  @rack_test
  Scenario: Cancel refusals
    Given today is "2026-10-20"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Q Capital" is an investor of the fund with a portal user
    And "P Family Trust" has placed a "subscription" order "amount=5000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:30"
    When the order of "P Family Trust" is cancelled directly
    Then cancelling succeeds
    When the order of "P Family Trust" is cancelled directly
    Then cancelling is refused with "Only a pending order can be cancelled"
    Given "Q Capital" has paid "10,00,000" of the subscription on "2026-10-22"
    When the order of "Q Capital" is cancelled directly
    Then cancelling is refused with "Money has been received for this order — refund it before cancelling"

  # ---- Upload variants ----

  # E96 — Edge case: an upload row giving only the folio number and All Units = Yes creates an all-units order for the folio's investor
  @rack_test
  Scenario: Upload an all-units redemption by folio number alone
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    When I upload the order rows:
      | Type       | Folio No | Investor | Unit Class | Amount | Units | All Units | Received At |
      | Redemption | F-012    |          | A          |        |       | Yes       |             |
    Then the order upload should have "0" failed rows
    And the latest order should be:
      | status    | pending |
      | all_units | true    |
      | folio     | F-012   |

  # X51 — Error case: upload rows naming another investor's folio, an unknown order type, or an unknown folio each fail with their reason, while the good row is created
  @rack_test
  Scenario: Upload rows with ownership, type and folio errors
    Given today is "2026-11-02"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "100" units of class "A" in folio "F-031" issued "2025-09-01"
    When I upload the order rows:
      | Type       | Folio No | Investor | Unit Class | Amount | Units | All Units | Received At |
      | Redemption | F-031    | A Ltd    | A          |        | 10    | No        |             |
      | Switch     | F-012    | A Ltd    | A          |        | 10    | No        |             |
      | Redemption | F-999    | A Ltd    | A          |        | 10    | No        |             |
      | Redemption | F-012    | A Ltd    | A          |        | 10    | No        |             |
    Then the order upload should have "3" failed rows
    And the order upload results should mention "Choose a folio of this investor in this fund"
    And the order upload results should mention "Choose an investor, a class and subscription or redemption"
    And the order upload results should mention "This folio has no units to redeem"
