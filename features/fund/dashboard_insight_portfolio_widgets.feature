# Worked examples H9–H12, E20–E30, E64 (§4): openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#4-fund-portfolio-widgets--phase-1-and-2
# (Peer KPI Comparison rows H13, E31, E32, X8 are in features/fund/dashboard_insight_peer_kpi.feature; X7 in
# features/security/dashboard_insight_fund_isolation.feature)
@rack_test
Feature: Fund portfolio insight widgets
  Valuation Freshness shows how old each held company's latest valuation is, Winners & Losers ranks unrealised
  gains and losses, and Sector Exposure splits the fund's FMV by the company's sector.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund "Growth Fund I" holds:
      | company       | instrument    | purchases | cost_cr | fmv_cr |
      | Zeta Foods    | Equity        | 1         | 4.00    | 6.00   |
      | Orbit Pay     | Series A CCPS | 1         | 2.00    | 3.00   |
      | Kite Robotics | Seed CCPS     | 1         | 1.00    | 1.00   |
    And the purchase-date valuations of the insight companies are removed

  # H9 — Happy path: valued 92 days ago is Due, 273 days ago is Stale, never valued is Never; stalest first
  Scenario: Valuation Freshness buckets the fund's holdings
    Given the insight company "Zeta Foods" was valued on "2026-06-30"
    And the insight company "Orbit Pay" was valued on "2025-12-31"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness counts should be "Current 0, Due 1, Stale 1, Never 1"
    And the Valuation Freshness rows should be:
      | Kite Robotics | Never | — |
      | Orbit Pay     | Stale | 273 |
      | Zeta Foods    | Due   | 92 |

  # H10 — Happy path: the same rows on the Aggregated Portfolio Dashboard, across all funds
  Scenario: Valuation Freshness on the aggregated dashboard
    Given the insight company "Zeta Foods" was valued on "2026-06-30"
    And the insight company "Orbit Pay" was valued on "2025-12-31"
    And the "Valuation Freshness" widget on the "Aggregated Portfolio Dashboard" has settings ""
    When I open the stakeholders portfolio dashboard
    Then the Valuation Freshness counts should be "Current 0, Due 1, Stale 1, Never 1"
    And the Valuation Freshness rows should be:
      | Kite Robotics | Never | — |
      | Orbit Pay     | Stale | 273 |
      | Zeta Foods    | Due   | 92 |

  # E64 — Edge case: the Age column reads in days up to 30, then months, then years and months
  Scenario: Valuation age reads in days, months and years
    Given the insight company "Zeta Foods" was valued on "2026-09-01"
    And the insight company "Orbit Pay" was valued on "2025-12-31"
    And the insight company "Kite Robotics" was valued on "2022-12-31"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness age of "Zeta Foods" should read "29 days"
    And the Valuation Freshness age of "Orbit Pay" should read "9 months"
    And the Valuation Freshness age of "Kite Robotics" should read "3 years 9 months"

  # E20 — Edge case: exactly 90 days old is still Current (2 Jul → 30 Sep = 90 days)
  Scenario: Exactly 90 days is Current
    Given the insight company "Zeta Foods" was valued on "2026-07-02"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness counts should be "Current 1, Due 0, Stale 0, Never 2"

  # E21 — Edge case: 91 days is Due, 180 days is Due, 181 days is Stale
  Scenario: Due and Stale boundaries
    Given the insight company "Zeta Foods" was valued on "2026-07-01"
    And the insight company "Orbit Pay" was valued on "2026-04-03"
    And the insight company "Kite Robotics" was valued on "2026-04-02"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness rows should be:
      | Kite Robotics | Stale | 181 |
      | Orbit Pay     | Due   | 180 |
      | Zeta Foods    | Due   | 91  |

  # E22 — Edge case: custom limits — with Current up to 30 and Due up to 60 days, 45 days is Due
  Scenario: Custom freshness limits
    Given the insight company "Zeta Foods" was valued on "2026-08-16"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{current_days: 30, due_days: 60}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness rows should be:
      | Kite Robotics | Never | — |
      | Orbit Pay     | Never | — |
      | Zeta Foods    | Due   | 45 |

  # E23 — Edge case: a holding the fund has fully exited is left out
  Scenario: Exited holding is not listed
    Given "Growth Fund I" has fully exited the insight company "Kite Robotics"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then Valuation Freshness should not list "Kite Robotics"
    And the Valuation Freshness counts should be "Current 0, Due 0, Stale 0, Never 2"

  # E24 — Edge case: the limit caps the rows to the stalest, and says how many of the total are shown
  Scenario: Limit caps the rows
    Given the fund "Growth Fund I" holds:
      | company     | instrument | purchases | cost_cr | fmv_cr |
      | Lumen Labs  | Equity     | 1         | 1.00    | 1.00   |
    And the purchase-date valuations of the insight companies are removed
    And the insight company "Zeta Foods" was valued on "2026-09-01"
    And the insight company "Orbit Pay" was valued on "2026-06-01"
    And the insight company "Kite Robotics" was valued on "2026-03-01"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings "{limit: 2}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness rows should be:
      | Lumen Labs    | Never | —   |
      | Kite Robotics | Stale | 213 |
    And Valuation Freshness should say "Showing 2 of 4"

  # E25 — Edge case: a future-dated valuation counts as Current, 0 days old
  Scenario: Future-dated valuation is Current
    Given the insight company "Zeta Foods" was valued on "2026-12-31"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness rows should be:
      | Kite Robotics | Never   | — |
      | Orbit Pay     | Never   | — |
      | Zeta Foods    | Current | 0 |

  # H11 — Happy path: gains Zeta +40 L then Kite +5 L; losses Orbit −15 L
  Scenario: Winners & Losers ranks unrealised gains and losses
    Given the "Equity" holding of "Zeta Foods" in "Growth Fund I" has an unrealised gain of "40" lakh
    And the "Series A CCPS" holding of "Orbit Pay" in "Growth Fund I" has an unrealised gain of "-15" lakh
    And the "Seed CCPS" holding of "Kite Robotics" in "Growth Fund I" has an unrealised gain of "5" lakh
    And the "Winners & Losers" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Winners & Losers "Gains" list should be "Zeta Foods, Kite Robotics"
    And the Winners & Losers "Losses" list should be "Orbit Pay"

  # E26 — Edge case: a company with zero unrealised gain is in neither list
  Scenario: Zero gain is in neither list
    Given the "Equity" holding of "Zeta Foods" in "Growth Fund I" has an unrealised gain of "40" lakh
    And the "Series A CCPS" holding of "Orbit Pay" in "Growth Fund I" has an unrealised gain of "-15" lakh
    And the "Seed CCPS" holding of "Kite Robotics" in "Growth Fund I" has an unrealised gain of "0" lakh
    And the "Winners & Losers" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Winners & Losers "Gains" list should be "Zeta Foods"
    And the Winners & Losers "Losses" list should be "Orbit Pay"

  # E27 — Edge case: with no losses the Losses list explains why
  Scenario: No losses
    Given the "Equity" holding of "Zeta Foods" in "Growth Fund I" has an unrealised gain of "40" lakh
    And the "Series A CCPS" holding of "Orbit Pay" in "Growth Fund I" has an unrealised gain of "15" lakh
    And the "Seed CCPS" holding of "Kite Robotics" in "Growth Fund I" has an unrealised gain of "5" lakh
    And the "Winners & Losers" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Winners & Losers "Losses" list should say "No holding is below cost."

  # E28 — Edge case: a company's gains are summed across its instruments (30 L + 10 L = 40 L)
  Scenario: Gains summed across instruments
    Given the fund "Growth Fund I" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Zeta Foods | CCPS       | 1         | 1.00    | 1.00   |
    And the "Equity" holding of "Zeta Foods" in "Growth Fund I" has an unrealised gain of "30" lakh
    And the "CCPS" holding of "Zeta Foods" in "Growth Fund I" has an unrealised gain of "10" lakh
    And the "Seed CCPS" holding of "Kite Robotics" in "Growth Fund I" has an unrealised gain of "0" lakh
    And the "Series A CCPS" holding of "Orbit Pay" in "Growth Fund I" has an unrealised gain of "0" lakh
    And the "Winners & Losers" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Winners & Losers "Gains" list should show "Zeta Foods" at "40,00,000"

  # H12 — Happy path: FMV ₹6 Cr Consumer + ₹3 Cr Fintech + ₹1 Cr unassigned = ₹10 Cr → 60 / 30 / 10 %
  Scenario: Sector Exposure splits FMV by sector
    Given the insight company "Zeta Foods" is in the "Consumer" sector
    And the insight company "Orbit Pay" is in the "Fintech" sector
    And the insight company "Kite Robotics" is in the "" sector
    And the "Sector Exposure" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then Sector Exposure should show "Consumer 60.00 %, Fintech 30.00 %, Unassigned 10.00 %"

  # E29 — Edge case: the cost measure splits by cost of the holdings still held (4 + 2 + 1 = 7 Cr)
  Scenario: Sector Exposure by cost
    Given the insight company "Zeta Foods" is in the "Consumer" sector
    And the insight company "Orbit Pay" is in the "Fintech" sector
    And the insight company "Kite Robotics" is in the "Fintech" sector
    And the "Sector Exposure" widget on the "Portfolio Dashboard" has settings "{measure: 'cost'}"
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then Sector Exposure should show "Consumer 57.14 %, Fintech 42.86 %"

  # E30 — Edge case: no holding has a fair value
  Scenario: Sector Exposure with no FMV
    Given the fund "Growth Fund I" holdings have no fair value
    And the "Sector Exposure" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the fund insight widget "Sector Exposure" should say "No holding has a fair value yet."
