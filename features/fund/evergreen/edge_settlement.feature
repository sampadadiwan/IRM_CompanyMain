@rack_test
Feature: Evergreen settlement edge cases — payments, units, folios
  Boundaries of the settlement tracker: part / exact / tolerance / over / zero payments, repeated and
  misdirected row actions, early-redemption fee on a gated fill, folio numbering and top-up reversal,
  and an investor with nobody to email.
  Worked examples E140–E148, X85–X90 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"

  # E140 — Edge case: a pay-after ₹1,00,00,000 subscription paid in two parts (₹40,00,000 then the remaining ₹60,00,000) gets no units after the first part and exactly 1,000.0000 units (₹1,00,00,000 ÷ ₹10,000) dated the second payment, once.
  Scenario: Two payments that sum exactly to the subscription allot units once, on the second
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-03"
    And "Q Capital" has paid "40,00,000" of the subscription on "2026-12-03"
    Then "Q Capital" on "2026-12-01" should have no units
    Given today is "2026-12-06"
    When I record the payment of "Q Capital" on "2026-12-06" in the tracker of "2026-12-01"
    Then the subscription payment of "Q Capital" should have collected "1,00,00,000"
    And the subscription payment of "Q Capital" should have 2 payment rows
    And the units of "Q Capital" on "2026-12-01" should be "1,000.0000" dated "2026-12-06"
    And folio "F-101" should hold "1,000.0000" units
    And the folio of "Q Capital" on "2026-12-01" should have exactly 1 unit row from the dealing date

  # E141 — Edge case: after a ₹40,00,000 part payment of a ₹1,00,00,000 subscription the tracker row shows the part-paid badge and must not claim "Money received · allotting…" (no units are coming until the rest arrives or the amount received is accepted).
  Scenario: A part-paid tracker row does not say units are being allotted
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-03"
    And "Q Capital" has paid "40,00,000" of the subscription on "2026-12-03"
    When I open the dealing date "2026-12-01"
    Then the tracker row of "Q Capital" on "2026-12-01" should show the part-paid badge
    And the tracker row of "Q Capital" on "2026-12-01" should not read "allotting"
    And the tracker row of "Q Capital" on "2026-12-01" should not read "Money received"

  # E142 — Edge case: a payment exactly 10 paise short (₹99,99,999.90 of ₹1,00,00,000) is within the tolerance, so it counts as fully paid: units 99,99,999.90 ÷ 10,000 = 999.99999999 → 1,000.0000 are allotted and no part-paid badge shows.
  Scenario: A payment short by exactly the 10-paise tolerance counts as fully paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    When "Q Capital" has paid "99,99,999.90" of the subscription on "2026-12-06"
    Then the units of "Q Capital" on "2026-12-01" should be "1,000.0000" dated "2026-12-06"
    When I open the dealing date "2026-12-01"
    Then the tracker row of "Q Capital" on "2026-12-01" should not show the part-paid badge
    And the tracker row of "Q Capital" on "2026-12-01" should read "Allotted"

  # X85 — Error case: a payment 11 paise short (₹99,99,999.89 of ₹1,00,00,000) is one paisa past the tolerance, so it stays part paid: no units are allotted and the part-paid badge shows.
  Scenario: A payment one paisa beyond the tolerance stays part paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    When "Q Capital" has paid "99,99,999.89" of the subscription on "2026-12-06"
    Then "Q Capital" on "2026-12-01" should have no units
    And folio "F-101" should hold "0" units
    When I open the dealing date "2026-12-01"
    Then the tracker row of "Q Capital" on "2026-12-01" should show the part-paid badge

  # E143 — Edge case: an over-payment (₹1,00,10,000 received for a ₹1,00,00,000 subscription) allots units for the subscription only — ₹1,00,00,000 ÷ ₹10,000 = 1,000.0000, not 1,001.0000; the ₹10,000 excess is a refund, not units.
  Scenario: An over-payment allots units for the subscription amount only
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    When "Q Capital" has paid "1,00,10,000" of the subscription on "2026-12-06"
    Then the subscription payment of "Q Capital" should have collected "1,00,10,000"
    And the units of "Q Capital" on "2026-12-01" should be "1,000.0000" dated "2026-12-06"
    And folio "F-101" should hold "1,000.0000" units

  # X86 — Error case: a payment of ₹0 posted to Record payment is refused — no payment row is added, the subscription payment is not marked verified and no units are allotted.
  Scenario: A zero payment is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    When "Asha" posts "record_payment" for the fill of "Q Capital" on "2026-12-01" directly with "amount=0;payment_date=2026-12-06"
    Then the direct request should not say "Payment recorded"
    And the subscription payment of "Q Capital" should have 0 payment rows
    And the subscription payment of "Q Capital" should not be verified
    And "Q Capital" on "2026-12-01" should have no units

  # X87 — Error case: Record payment posted a second time (a double click) after the ₹1,00,00,000 is fully in is refused — no extra (₹0) payment row, and the 1,000.0000 units stay a single allotment.
  Scenario: Recording a payment again on a fully paid subscription is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-06"
    And I record the payment of "Q Capital" on "2026-12-06" in the tracker of "2026-12-01"
    When "Asha" posts "record_payment" for the fill of "Q Capital" on "2026-12-01" directly with "payment_date=2026-12-06"
    Then the direct request should not say "Payment recorded"
    And the subscription payment of "Q Capital" should have 1 payment row
    And the subscription payment of "Q Capital" should have collected "1,00,00,000"
    And the units of "Q Capital" on "2026-12-01" should be "1,000.0000" dated "2026-12-06"
    And the folio of "Q Capital" on "2026-12-01" should have exactly 1 unit row from the dealing date

  # X88 — Error case: Mark paid posted a second time for an already-paid redemption (100 units, ₹10,22,000 at ₹10,220) is refused — the payment keeps its 10 Nov date and UTR-1 reference, the 100 units are cancelled once (12,000 − 100 = 11,900) and one advice email goes out.
  Scenario: Marking a paid redemption paid again is refused
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And today is "2026-11-10"
    And I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-1" in the tracker of "2026-11-02"
    And today is "2026-11-12"
    When "Asha" posts "mark_paid" for the fill of "A Ltd" on "2026-11-02" directly with "payment_date=2026-11-12;reference=UTR-2"
    Then the direct request should not say "Redemption marked paid"
    And the redemption of "A Ltd" on "2026-11-02" should be paid on "2026-11-10" with reference "UTR-1"
    And folio "F-012" should hold "11,900.0000" units
    And the folio of "A Ltd" on "2026-11-02" should have exactly 1 unit row from the dealing date
    And "A Ltd" should have been sent 1 "redemption advice" email

  # X89 — Error case: a row action posted against the wrong kind of row is refused with the reason — Record payment on a redemption row, Mark paid on a subscription row — and nothing changes.
  Scenario: Row actions refuse the wrong kind of row
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" is an investor of the fund with a portal user
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When "Asha" posts "record_payment" for the fill of "A Ltd" on "2026-11-02" directly with "payment_date=2026-11-02"
    Then the direct request should be refused with "This fill has no subscription payment"
    And the redemption of "A Ltd" on "2026-11-02" should not be paid
    When "Asha" posts "mark_paid" for the fill of "P Family Trust" on "2026-11-02" directly with "payment_date=2026-11-02;reference=UTR-X"
    Then the direct request should be refused with "This fill has no redemption payment"
    And the subscription payment of "P Family Trust" should have 1 payment row

  # X90 — Error case: an investor's portal user posting Mark paid on their own redemption row directly is refused (settling is a fund-editor action) and the redemption stays unpaid with no units cancelled.
  Scenario: An investor cannot mark their own redemption paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When "A Ltd" posts "mark_paid" for the fill of "A Ltd" on "2026-11-02" directly with "payment_date=2026-11-02;reference=UTR-LP"
    Then the direct request should be refused
    And the redemption of "A Ltd" on "2026-11-02" should not be paid
    And folio "F-012" should hold "12,000.0000" units

  # E144 — Edge case: a locked-up redemption of 6,000 units cut by the 5 % gate pays the 2 % fee on the filled part only: gate 5 % × 1,00,000 × ₹10,220 = ₹5,11,00,000 → 5,000 units filled, 1,000 carried; fee 2 % × ₹5,11,00,000 = ₹10,22,000; net ₹5,00,78,000; folio 12,000 − 5,000 = 7,000 units.
  Scenario: The early-redemption fee on a gated redemption is charged on the filled units only
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2026-03-15"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-30"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=6000" received "2026-09-30 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the fills of dealing date "2026-11-02" should be:
      | investor | units | amount      |
      | A Ltd    | 5000  | 5,11,00,000 |
    And the redemption payment of "A Ltd" on "2026-11-02" should have net payable "5,00,78,000"
    Given today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-G" in the tracker of "2026-11-02"
    Then folio "F-012" should hold "7,000" units
    And the "redemption advice" of "A Ltd" on "2026-11-02" should show:
      | Units cancelled      | 5,000.0000      |
      | Gross amount         | ₹5,11,00,000.00 |
      | Exit load            | ₹10,22,000.00   |
      | Net paid             | ₹5,00,78,000.00 |
      | Payment date         | Nov 10, 2026    |

  # E145 — Edge case: folio numbering continues one past the highest numeric F- folio (F-150 → F-151) and ignores a non-numeric one (F-ABC); the new folio is subscribed ₹1,00,00,000.
  Scenario: A new folio is numbered after the highest numeric F- folio
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "1000" units of class "A" in folio "F-150" issued "2025-09-01"
    And "Legacy LP" holds "500" units of class "A" in folio "F-ABC" issued "2025-09-01"
    And today is "2026-10-20"
    When "P Family Trust" has placed a "subscription" order "amount=10000000" received "2026-10-20 09:00"
    Then "P Family Trust" should have folio "F-151"
    And folio "F-151" should have subscribed "1,00,00,000"

  # E146 — Edge case: in a pay-after fund a ₹1,00,00,000 top-up of existing folio F-012 is added at confirmation (+₹1,00,00,000) and Undo, before any money, takes it off again (+₹0).
  Scenario: Undo reverses a folio top-up made at confirmation
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "99000" units of class "A" in folio "F-099" issued "2025-09-01"
    And I note the subscribed amount of folio "F-012"
    And today is "2026-11-10"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=10000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    Then folio "F-012" should have subscribed "1,00,00,000" more
    When I open the dealing date "2026-12-01"
    And I undo the dealing date
    Then I should see "Confirmation undone"
    And folio "F-012" should have subscribed "0" more

  # E147 — Edge case: in a pre-funded fund a ₹1,00,00,000 top-up of F-012 is added when the order is placed; cancelling the unpaid order takes it off again (+₹0) and the folio stays.
  Scenario: Cancelling a top-up order reverses the folio top-up
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And I note the subscribed amount of folio "F-012"
    And today is "2026-10-20"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=10000000" received "2026-10-20 09:00"
    Then folio "F-012" should have subscribed "1,00,00,000" more
    When the fund admin cancels the order of "A Ltd"
    Then the order of "A Ltd" should be "cancelled" on dealing date "2026-11-02"
    And folio "F-012" should have subscribed "0" more
    And folio "F-012" should hold "1,000" units

  # E148 — Edge case: an investor with no portal users still gets units at allotment (₹1,02,20,000 ÷ ₹10,220 = 1,000.0000), no contract-note email is sent (nobody to send to) and the date can close.
  Scenario: An investor without portal users is allotted and the date can still close
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "Z Corp" holds "100" units of class "A" in folio "F-050" issued "2025-09-01"
    And "Others" holds "99900" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-10-20"
    And "Z Corp" has placed a "subscription" order "folio=F-050;amount=10220000" received "2026-10-20 09:00"
    And "Z Corp" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the units of "Z Corp" on "2026-11-02" should be "1,000.0000" dated "2026-11-02"
    And folio "F-050" should hold "1,100" units
    And no contract note or redemption advice email should have gone to investors
    When I open the dealing date "2026-11-02"
    Then Close dealing date should be enabled

  # X95 — Error case: a template removed after settlement still gets its email sent and the date can still close — P Family Trust's ₹5,00,00,000 subscription is allotted 4,892.3679 units (₹5,00,00,000 ÷ ₹10,220) under a Contract Note Template, the template is deleted before any document is generated, and the investor still gets the plain contract-note email and Close dealing date becomes available.
  Scenario: A template removed after settlement still lets the contract note go out and the date close
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And the fund has the "Contract Note Template" "Alpha Contract Note"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    And "P Family Trust" should have been sent 0 "contract note" emails
    When the fund's "Contract Note Template" "Alpha Contract Note" is removed
    And the GP sends any outstanding documents of dealing date "2026-11-02"
    Then "P Family Trust" should get the "contract note" email without an attachment
    When I open the dealing date "2026-11-02"
    Then Close dealing date should be enabled
