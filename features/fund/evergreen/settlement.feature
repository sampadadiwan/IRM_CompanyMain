@rack_test
Feature: Evergreen settlement — automatic units, tracker actions, settlement records
  Worked examples H22, H23, H24, H25, H36, E2, E31, E32 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"

  # H25, H24 — Happy path: a paid pre-funded ₹5,00,00,000 subscription is allotted 4,892.3679 units at confirmation and a ₹3,00,00,000 redemption marked paid cancels its units and sends the advice.
  Scenario: Pre-funded allotment at confirmation, then a redemption is marked paid
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" is an investor of the fund with a portal user
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "Others" holds "88000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the units of "P Family Trust" on "2026-11-02" should be "4,892.3679" dated "2026-11-02"
    And the "contract note" of "P Family Trust" on "2026-11-02" should show:
      | Folio          | F-101           |
      | Class          | A               |
      | NAV date       | Oct 31, 2026    |
      | Subscription date | Nov 02, 2026  |
      | NAV per unit   | ₹10,220.00      |
      | Units allotted | 4,892.3679      |
      | Amount         | ₹5,00,00,000.00 |
    And "P Family Trust" receives an email with subject "Alpha Long-Short Fund: Contract note" containing "4,892.3679"
    Given today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR123" in the tracker of "2026-11-02"
    Then the tracker row of "A Ltd" on "2026-11-02" should read "Units cancelled"
    And the tracker row of "A Ltd" on "2026-11-02" should read "Redemption advice sent"
    And folio "F-012" should hold "9,064.5793" units

  # H22, H23 — Happy path: in a pay-after fund the folio opens at confirmation and units are allotted, dated the payment, when the money is recorded.
  Scenario: Pay after dealing — folio at confirmation, units when the money is recorded
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And "Others" holds "100000" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-11-10"
    And "Q Capital" has placed a "subscription" order "amount=50000000" received "2026-11-10 09:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    When the fund admin confirms dealing date "2026-12-01"
    Then folio "F-101" should have subscribed "5,00,00,000"
    And "Q Capital" receives an email with subject "Alpha Long-Short Fund: Payment instructions" containing "5,000.0000"
    Given today is "2026-12-06"
    When I record the payment of "Q Capital" on "2026-12-06" in the tracker of "2026-12-01"
    Then the units of "Q Capital" on "2026-12-01" should be "5,000.0000" dated "2026-12-06"

  # E31 — Edge case: a subscription into an existing folio tops up its subscribed amount by the order amount instead of opening a new folio.
  Scenario: An existing folio is topped up by a subscription
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And "A Ltd" holds "1000" units of class "A" in folio "F-012" issued "2025-09-01"
    And I note the subscribed amount of folio "F-012"
    And today is "2026-10-20"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=10000000" received "2026-10-20 09:00"
    Then folio "F-012" should have subscribed "1,00,00,000" more

  # E32 — Edge case: redeeming all 1,200 locked-up units deducts the 2 % early-redemption fee (₹2,45,280) from the payment, empties the folio and shows the fee on the advice.
  Scenario: An early-redemption fee is deducted and shown on the advice
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;lock_up_months=12;lock_up_type=soft"
    And the fund setting has "early_fee_pct=2"
    And "A Ltd" is an investor of the fund with a portal user
    And "A Ltd" holds "1200" units of class "A" in folio "F-012" issued "2026-03-15"
    And "Others" holds "98800" units of class "A" in folio "F-099" issued "2025-09-01"
    And today is "2026-09-30"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=1200" received "2026-09-30 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    When the fund admin confirms dealing date "2026-11-02"
    Then the redemption payment of "A Ltd" on "2026-11-02" should have net payable "1,20,18,720"
    Given today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR9" in the tracker of "2026-11-02"
    Then folio "F-012" should hold "0" units
    And the "redemption advice" of "A Ltd" on "2026-11-02" should show:
      | Units cancelled      | 1,200.0000      |
      | Gross amount         | ₹1,22,64,000.00 |
      | Exit load            | ₹2,45,280.00    |
      | Net paid             | ₹1,20,18,720.00 |
      | Payment date         | Nov 10, 2026    |

  # H36 — Happy path: the redemption settlement record and the old distribution URL both open the evergreen redemption settlement page.
  Scenario: Settlement records read the evergreen way
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;units=100" received "2026-09-10 09:00"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "12000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
    When I follow the redemption settlement record of "2026-11-02"
    Then I should be on the evergreen redemption settlement of "2026-11-02"
    When I open the old distribution page of "2026-11-02"
    Then I should be on the evergreen redemption settlement of "2026-11-02"

  # E2 — Edge case: a closed-ended call and distribution on the same entity keep their manual Allocate / Redeem units behaviour.
  Scenario: A closed-ended call and distribution are untouched
    Given the closed-ended fund "Beta Growth Fund" has a call with unit price "10,000" and a paid remittance of "10,00,000"
    Then the closed-ended remittance has no units until Allocate units
    And a closed-ended distribution payment redeems amount ÷ price only when Redeem units runs
