# Worked examples H14–H16, E33–E44 (§5): openspec/changes/dashboard-insight-widgets/business-rules.md#5-fund-capital-widgets--phase-1-and-2
# (X9 is in features/security/dashboard_insight_fund_isolation.feature)
@rack_test
Feature: Fund capital insight widgets
  Remittance Ageing groups the fund's unpaid call amounts by days past the due date, NAV per Unit Trend charts
  approved NAV per unit by class, and Hedge Expiries lists open derivative contracts nearing expiry.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity

  # H14 — Happy path: due 15 Oct (not yet due), 15 Sep (15 days), 1 Aug (60 days), 15 Jun (107 days)
  Scenario: Remittance Ageing buckets unpaid amounts
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status  |
      | Call 4 | 2026-10-15 | 10          | 0         | 0         | Pending |
      | Call 3 | 2026-09-15 | 20          | 0         | 0         | Overdue |
      | Call 2 | 2026-08-01 | 5           | 0         | 0         | Overdue |
      | Call 1 | 2026-06-15 | 2           | 0         | 0         | Overdue |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Remittance Ageing should show:
      | Not yet due  | 1 | ₹10,00,000.00 |
      | 0–30 days    | 1 | ₹20,00,000.00 |
      | 31–60 days   | 1 | ₹5,00,000.00  |
      | 61–90 days   | 0 | ₹0.00         |
      | Over 90 days | 1 | ₹2,00,000.00  |

  # E33 — Edge case: a call due today is 0 days overdue, so it is in 0–30 days
  Scenario: Due today is 0–30 days
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status  |
      | Call 1 | 2026-09-30 | 10          | 0         | 0         | Overdue |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Remittance Ageing should put 1 remittance in "0–30 days"
    And Remittance Ageing should put 0 remittances in "Not yet due"

  # E34 — Edge case: 30/31, 60/61 and 90/91 days are the bucket boundaries
  Scenario: Bucket boundaries
    Given the fund "Growth Fund I" has these insight remittances:
      | call    | due_date   | call_amount | other_fee | collected | status  |
      | Call 30 | 2026-08-31 | 1           | 0         | 0         | Overdue |
      | Call 31 | 2026-08-30 | 1           | 0         | 0         | Overdue |
      | Call 60 | 2026-08-01 | 1           | 0         | 0         | Overdue |
      | Call 61 | 2026-07-31 | 1           | 0         | 0         | Overdue |
      | Call 90 | 2026-07-02 | 1           | 0         | 0         | Overdue |
      | Call 91 | 2026-07-01 | 1           | 0         | 0         | Overdue |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Remittance Ageing should put 1 remittance in "0–30 days"
    And Remittance Ageing should put 2 remittances in "31–60 days"
    And Remittance Ageing should put 2 remittances in "61–90 days"
    And Remittance Ageing should put 1 remittance in "Over 90 days"

  # E35 — Edge case: Paid and Overpaid remittances are left out
  Scenario: Paid and overpaid are not counted
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status   |
      | Call 1 | 2026-09-15 | 10          | 0         | 10        | Paid     |
      | Call 2 | 2026-09-15 | 10          | 0         | 12        | Overpaid |
      | Call 3 | 2026-09-15 | 10          | 0         | 0         | Overdue  |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Remittance Ageing should put 1 remittance in "0–30 days"

  # E36 — Edge case: other fees are part of the due — ₹10 L + ₹0.5 L − ₹4 L collected = ₹6.5 L
  Scenario: Fees are part of the due
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status  |
      | Call 1 | 2026-09-15 | 10          | 0.5       | 4         | Overdue |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Remittance Ageing should show:
      | Not yet due  | 0 | ₹0.00        |
      | 0–30 days    | 1 | ₹6,50,000.00 |
      | 31–60 days   | 0 | ₹0.00        |
      | 61–90 days   | 0 | ₹0.00        |
      | Over 90 days | 0 | ₹0.00        |

  # E37 — Edge case: the widget's 4 open remittances are the 4 rows the "View open remittances" grid lists
  Scenario: Totals match the linked grid
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status  |
      | Call 4 | 2026-10-15 | 10          | 0         | 0         | Pending |
      | Call 3 | 2026-09-15 | 20          | 0         | 0         | Overdue |
      | Call 2 | 2026-08-01 | 5           | 0         | 0         | Overdue |
      | Call 1 | 2026-06-15 | 2           | 0         | 0         | Overdue |
      | Call 0 | 2026-05-15 | 2           | 0         | 2         | Paid    |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then the remittances list behind "View open remittances" should hold 4 remittances

  # E38 — Edge case: nothing unpaid
  Scenario: No unpaid remittances
    Given the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status |
      | Call 1 | 2026-09-15 | 10          | 0         | 10        | Paid   |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then the fund insight widget "Remittance Ageing" should say "No unpaid remittances in this fund."

  # H15 — Happy path: one line per class with the approved NAVs per unit
  Scenario: NAV per Unit Trend per class
    Given there is a fund "name=Evergreen Income Fund;currency=INR" for the entity
    And an approved NAV for class "A" on "2026-07-31" with NAV per unit "101.20" and units "1000"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "102.10" and units "1000"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "103.00" and units "1000"
    And an approved NAV for class "B" on "2026-07-31" with NAV per unit "100.50" and units "1000"
    And an approved NAV for class "B" on "2026-08-31" with NAV per unit "101.00" and units "1000"
    And an approved NAV for class "B" on "2026-09-30" with NAV per unit "101.60" and units "1000"
    And the "NAV per Unit Trend" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then NAV per Unit Trend class "Class A" should plot "2026-07-31=101.20,2026-08-31=102.10,2026-09-30=103.00"
    And NAV per Unit Trend class "Class B" should plot "2026-07-31=100.50,2026-08-31=101.00,2026-09-30=101.60"

  # E39 — Edge case: a draft NAV is not plotted
  Scenario: Draft NAVs are left out
    Given there is a fund "name=Evergreen Income Fund;currency=INR" for the entity
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "102.10" and units "1000"
    And an approved NAV for class "A" on "2026-09-30" with NAV per unit "103.00" and units "1000"
    And a draft insight NAV for class "A" on "2026-10-31" with NAV per unit "104.00"
    And the "NAV per Unit Trend" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then NAV per Unit Trend class "Class A" should plot "2026-08-31=102.10,2026-09-30=103.00"

  # E40 — Edge case: with 18 months of NAVs and months 6, the last 6 month ends up to the latest NAV are plotted
  Scenario: Months setting
    Given there is a fund "name=Evergreen Income Fund;currency=INR" for the entity
    And class "A" has approved insight NAVs for each month end from "2025-04-30" to "2026-09-30"
    And the "NAV per Unit Trend" widget on the "Fund Dashboard" has settings "{months: 6}"
    When I open the fund dashboard "Fund Dashboard"
    Then NAV per Unit Trend class "Class A" should plot 6 points

  # E41 — Edge case: a closed-end fund has no NAVs
  Scenario: Closed-end fund has no NAVs
    Given the "NAV per Unit Trend" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then the fund insight widget "NAV per Unit Trend" should say "This fund has no approved NAVs. NAV per unit is kept for evergreen funds."

  # H16 — Happy path: an open forward expiring 15 Oct 2026 is listed with 15 days left
  Scenario: Hedge Expiries lists an open contract nearing expiry
    Given the fund "Growth Fund I" has these insight derivative contracts:
      | name            | status | expiry     | notional |
      | USD/INR Fwd Dec | open   | 2026-10-15 | 500000   |
    And the "Hedge Expiries" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Hedge Expiries should list:
      | USD/INR Fwd Dec | 15 days |

  # E42 — Edge case: an open contract already past expiry is listed first, as expired
  Scenario: Expired but still open
    Given the fund "Growth Fund I" has these insight derivative contracts:
      | name            | status | expiry     | notional |
      | USD/INR Fwd Dec | open   | 2026-10-15 | 500000   |
      | USD/INR Fwd Sep | open   | 2026-09-20 | 300000   |
    And the "Hedge Expiries" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then Hedge Expiries should list:
      | USD/INR Fwd Sep | Expired 10 days ago |
      | USD/INR Fwd Dec | 15 days             |

  # E43 — Edge case: an open contract 182 days out and a closed one are not listed (default 90-day window)
  Scenario: Beyond the window or closed
    Given the fund "Growth Fund I" has these insight derivative contracts:
      | name            | status | expiry     | notional |
      | USD/INR Fwd Mar | open   | 2027-03-31 | 500000   |
      | USD/INR Fwd Oct | closed | 2026-10-10 | 500000   |
    And the "Hedge Expiries" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then the fund insight widget "Hedge Expiries" should say "No open contracts expire in the next 90 days."

  # E44 — Edge case: a fund with no derivative contracts
  Scenario: No derivatives
    Given the "Hedge Expiries" widget on the "Fund Dashboard" has settings ""
    When I open the fund dashboard "Fund Dashboard"
    Then the fund insight widget "Hedge Expiries" should say "No open contracts expire in the next 90 days."
