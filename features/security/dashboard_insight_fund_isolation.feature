# Worked examples X7, X9: openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md (§4, §5)
@rack_test
Feature: Fund insight widgets stay inside the firm and away from LPs
  Valuation Freshness counts only the firm's own valuations, and an investor-role user who requests a fund
  dashboard holding an insight widget never sees its content.

  Background:
    Given today is "2026-09-30"
    And Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    And the fund "Growth Fund I" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Zeta Foods | Equity     | 1         | 4.00    | 6.00   |
    And the purchase-date valuations of the insight companies are removed

  # X7 — Error case: another firm's valuation of a same-named company does not make Zeta Foods current
  Scenario: Other firm's valuations are ignored
    Given the insight company "Zeta Foods" was valued on "2026-06-30"
    And another firm values its own company "Zeta Foods" on "2026-09-29"
    And the "Valuation Freshness" widget on the "Portfolio Dashboard" has settings ""
    When I open the "Portfolio Dashboard" of fund "Growth Fund I"
    Then the Valuation Freshness rows should be:
      | Zeta Foods | Due | 92 |

  # X9 — Error case: an LP who requests the Fund Dashboard URL sees nothing of Remittance Ageing
  Scenario: Investor role on the fund dashboard
    Given LP "Lena Capital" has folio "LENA-1" in "Growth Fund I"
    And the fund "Growth Fund I" has these insight remittances:
      | call   | due_date   | call_amount | other_fee | collected | status  |
      | Call 1 | 2026-09-15 | 10          | 0         | 0         | Overdue |
    And the "Remittance Ageing" widget on the "Fund Dashboard" has settings ""
    When LP "Lena Capital" opens the "Fund Dashboard" of fund "Growth Fund I"
    Then the fund insight widget "Remittance Ageing" should render nothing
