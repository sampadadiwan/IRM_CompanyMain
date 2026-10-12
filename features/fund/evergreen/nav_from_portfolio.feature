Feature: Evergreen NAV drafted from the fund's actual portfolio
  The draft reads each holding's quantity on the NAV date × its latest valuation on or before that date
  (NavInputs#investments_fmv_cents → AggregatePortfolioInvestment#fmv_on_date) — no fair-value stub.
  Worked examples H9, E18, E19, E20 — openspec/changes/evergreen-folio-soa/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And the evergreen fund "Alpha Long-Short Fund" with classes "A"
    And the evergreen fund has folios:
      | investor | folio | class | units | issued     |
      | A Ltd    | F-012 | A     | 10000 | 2025-09-01 |
    And the fund ledger has "Cash In Hand" of "50,00,000" on "2026-10-31"

  # H9 — Happy path: one holding of 10,000 shares valued ₹1,500 → fair value ₹1,50,00,000; NAV ₹2,00,00,000 = ₹2,000 a unit
  Scenario: The NAV's fair value comes from the holding and its valuation
    Given the fund "buys" "10,000" shares of "Acme Robotics" on "2026-06-01" for "1,00,00,000"
    And "Acme Robotics" is valued at "1,500" a share on "2026-09-30"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | status                | draft          |
      | source                | computed       |
      | investments_fmv_cents | 1,50,00,000    |
      | cash_cents            | 50,00,000      |
      | nav_cents             | 2,00,00,000    |
      | units_outstanding     | 10000          |
      | nav_per_unit_cents    | 2,000          |

  # E18 — Edge case: two companies; a valuation dated after the NAV date is ignored
  # Acme 10,000 × ₹1,500 (the 15 Nov ₹1,800 is too late) + Beta 5,000 × ₹2,000 = ₹2,50,00,000
  Scenario: Several holdings, latest valuation on or before the NAV date
    Given the fund "buys" "10,000" shares of "Acme Robotics" on "2026-06-01" for "1,00,00,000"
    And "Acme Robotics" is valued at "1,500" a share on "2026-09-30"
    And "Acme Robotics" is valued at "1,800" a share on "2026-11-15"
    And the fund "buys" "5,000" shares of "Beta Foods" on "2026-03-01" for "75,00,000"
    And "Beta Foods" is valued at "2,000" a share on "2026-06-30"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | investments_fmv_cents | 2,50,00,000 |
      | nav_cents             | 3,00,00,000 |
      | nav_per_unit_cents    | 3,000       |

  # E19 — Edge case: shares sold before the NAV date leave the holding: (10,000 − 2,000) × ₹1,500 = ₹1,20,00,000
  Scenario: A sale reduces the holding
    Given the fund "buys" "10,000" shares of "Acme Robotics" on "2026-06-01" for "1,00,00,000"
    And the fund "sells" "2,000" shares of "Acme Robotics" on "2026-08-01" for "30,00,000"
    And "Acme Robotics" is valued at "1,500" a share on "2026-09-30"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | investments_fmv_cents | 1,20,00,000 |

  # E20 — Edge case: with no valuation after the purchase, the holding is at the cost valuation the purchase records
  # (10,000 shares for ₹1,00,00,000 → ₹1,000 a share; the ₹1,500 of 15 Nov is after the NAV date)
  Scenario: A holding with only its purchase valuation
    Given the fund "buys" "10,000" shares of "Acme Robotics" on "2026-06-01" for "1,00,00,000"
    And "Acme Robotics" is valued at "1,500" a share on "2026-11-15"
    When I draft the NAV for "2026-10-31"
    Then the class "A" NAV for "2026-10-31" should be:
      | investments_fmv_cents | 1,00,00,000 |
      | nav_cents             | 1,50,00,000 |
