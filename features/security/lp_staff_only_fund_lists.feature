@security
Feature: LPs do not list staff-only fund records - 2026-10 security review (H18)
  Fund reports, fund formulas, capital calls, capital distributions, unit settings and ratio formulas are
  staff-only records: no LP screen, mobile endpoint or MCP answer is meant to list them. The six
  policies' scopes return nothing for an investor persona (an LP, or an advisor switched to investor),
  and a ratio formula opens only for the fund's own staff. LPs keep everything their fund page shows
  (commitments, remittances, distribution payments, units, ratios, documents); staff lists are unchanged.
  Design and worked examples: docs/security/security_review_2026_10.md ("H18 — LPs listing staff-only
  fund records").

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is an existing investor "" with "1" users
    And there is an existing investor "" with "1" users
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And I have an API token
    And my fund also has the staff-only records: a formula "Carry Formula", a fund report, a distribution, a unit setting and a ratio formula
    And "Lena" is the investor user of folio 1

  # H18-1 — Edge case: an LP with access to the fund lists its fund reports: empty
  Scenario: H18-1 An LP lists no fund reports
    When "Lena" sends GET "/fund_reports.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-2 — Edge case: an LP lists the fund's formulas: empty
  Scenario: H18-2 An LP lists no fund formulas
    When "Lena" sends GET "/fund_formulas.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-3 — Edge case: an LP lists the fund's capital calls: empty (their notices open through their remittances)
  Scenario: H18-3 An LP lists no capital calls
    When "Lena" sends GET "/capital_calls.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-4 — Edge case: an LP lists the fund's capital distributions: empty
  Scenario: H18-4 An LP lists no capital distributions
    When "Lena" sends GET "/capital_distributions.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-5 — Edge case: an LP lists the fund's unit settings: empty
  Scenario: H18-5 An LP lists no unit settings
    When "Lena" sends GET "/fund_unit_settings.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-6 — Edge case: an LP lists the fund's ratio formulas (the list has no JSON view, so its scope): empty
  Scenario: H18-6 An LP lists no ratio formulas
    Then "Lena" can list 0 ratio formulas of my fund

  # H18-7 — Edge case: a company admin of another firm opening my fund's ratio formula is refused (403)
  Scenario: H18-7 Another firm's user cannot open a ratio formula
    Given "Zed" is a company admin of another firm "Zeta Partners"
    When "Zed" sends GET "/funds/{fund}/ratio_formulas/{ratio_formula}.json"
    Then the API status is 403

  # H18-8 — Edge case: an LP opening the fund's formula dependencies page sees no formula
  @rack_test
  Scenario: H18-8 An LP sees no formula dependencies
    When "Lena" opens the web page "/fund_formulas/dependencies?fund_id={fund}"
    Then the web page does not mention "Carry Formula"

  # H18-X1 — Edge case: an advisor switched into an investor (the investor persona) lists capital calls: empty
  Scenario: H18-X1 An advisor switched to investor lists no capital calls
    Given an advisor "Arjun" is switched into the investor of folio 2
    When "Arjun" sends GET "/capital_calls.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 0 rows

  # H18-H1 — Happy path: the LP still gets their own fund page data - their statement and their remittance
  Scenario: H18-H1 An LP still sees their own fund data
    When "Lena" sends GET "/capital_commitments/{folio1}/statement.json"
    Then the API status is 200
    And the API answer at "remittances.0.due_amount" is present
    When "Lena" sends GET "/capital_remittances.json?fund_id={fund}"
    Then the API status is 200
    And the API answer is a list of 1 row

  # H18-H2 — Happy path: the fund's company admin still lists every staff-only record
  Scenario: H18-H2 A company admin still lists the six staff-only records
    Then every staff-only list of my fund has 1 row for "me"
    And "me" can list 1 ratio formula of my fund
    And "me" may open the ratio formula
