@rack_test
Feature: Evergreen dealing dates — calendar and multi-class edge cases
  Worked examples E100, E101, E104, X55 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And today is "2026-09-01"

  # E100 — Edge case: last-business-day dealing moves weekend month-ends back to Friday across the year end (31 Oct 2026 Sat → 30 Oct; 31 Jan 2027 Sun → 29 Jan), and generating twice creates no duplicates.
  Scenario: Month-end dealing dates fall back to the last business day
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "dealing_day=last"
    And today is "2026-10-01"
    When the dealing dates are generated
    Then the fund should have dealing dates:
      | date       | cutoff     |
      | 2026-10-30 | 2026-10-25 |
      | 2026-11-30 | 2026-11-25 |
      | 2026-12-31 | 2026-12-26 |
      | 2027-01-29 | 2027-01-24 |
    And the fund should have no dealing date on "2026-10-31"
    And the fund should have no dealing date on "2027-01-31"
    Given I note the dealing date count
    When the dealing dates are generated
    Then the dealing date count should be unchanged

  # E101 — Edge case: day-15 dealing moves a 15th that falls on a weekend (Sun 15 Nov 2026) to the next business day (Mon 16 Nov), with the cut-off counted from the moved date.
  Scenario: A day-N dealing date on a weekend moves to Monday
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly"
    And the fund setting has "dealing_day=day_n;dealing_day_n=15"
    And today is "2026-10-01"
    When the dealing dates are generated
    Then the fund should have dealing dates:
      | date       | cutoff     |
      | 2026-10-15 | 2026-10-10 |
      | 2026-11-16 | 2026-11-11 |
      | 2026-12-15 | 2026-12-10 |
    And the fund should have no dealing date on "2026-11-15"

  # E104 — Edge case: subscriptions in two classes on one dealing date are each priced at their own class NAV — ₹5,00,00,000 at ₹10,220 → 4,892.3679 A units; ₹5,00,00,000 at ₹9,500 → 5,263.1579 B units.
  Scenario: Each class prices at its own NAV
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B" and settings "redemption_calendar=monthly;payment_timing=after"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Q Capital" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=50000000;class=B" received "2026-10-20 09:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And an approved NAV for class "B" on "2026-10-31" with NAV per unit "9,500" and units "20000"
    And today is "2026-11-02"
    Then the pricing of "2026-11-02" should allot "4,892.3679" units to "P Family Trust"
    And the pricing of "2026-11-02" should allot "5,263.1579" units to "Q Capital"
    When the fund admin confirms dealing date "2026-11-02"
    Then the subscription settlement of "2026-11-02" should have unit price "10,220" for class "A"
    And the subscription settlement of "2026-11-02" should have unit price "9,500" for class "B"

  # X55 — Error case: with class A's NAV approved but class B's 31 Oct NAV still a draft, confirm is refused naming class B and nothing is stored — class A does not deal alone.
  Scenario: One class's draft NAV blocks the whole dealing date
    Given the evergreen fund "Alpha Long-Short Fund" with classes "A,B" and settings "redemption_calendar=monthly;payment_timing=after"
    And "P Family Trust" is an investor of the fund with a portal user
    And "Q Capital" is an investor of the fund with a portal user
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "Q Capital" has placed a "subscription" order "amount=50000000;class=B" received "2026-10-20 09:30"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And a draft NAV for class "B" on "2026-10-31" with NAV per unit "9,500" and units "20000"
    And today is "2026-11-02"
    When the fund admin tries to confirm dealing date "2026-11-02"
    Then the confirm should be refused with "Approve the NAV for Class B dated 31 October 2026 first"
    And the dealing date "2026-11-02" should be "open"
    And the dealing date "2026-11-02" should have "0" fills
