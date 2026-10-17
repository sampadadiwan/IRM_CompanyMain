Feature: LP assistant follows the LP's visible holdings
  The LP assistant reads portfolio holdings only through the visible-holdings placeholders, filled from the same
  rule as every LP portfolio screen; a query on holdings without them is rejected.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md (H19, E69, E70, E71, X18)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company         | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics   | Series B CCPS | 1         | 25.00   | 40.00  |
      | Bluefin Health  | Series A CCPS | 1         | 20.00   | 22.00  |
      | Cedar Logistics | Series A CCPS | 1         | 15.00   | 18.00  |
      | Delta AI        | Seed CCPS     | 1         | 3.00    | 3.00   |
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company         | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 2.50   |
      | Allocated Portfolio Cost | Cedar Logistics | Series A CCPS | 1.50   |
      | Allocated Portfolio Cost | Bluefin Health  | Series A CCPS | 0.00   |
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"

  # H19 — Happy path: under Allocated the assistant names Acme and Cedar only
  Scenario: Assistant uses the visible set
    When LP "Ravi Menon" asks the assistant for their portfolio companies
    Then the assistant answer should name "Acme Robotics, Cedar Logistics"
    And the assistant answer should not name "Bluefin Health, Delta AI"

  # E69 — Edge case: a holding hidden from Ravi returns no rows
  Scenario: Assistant and a hidden holding
    When LP "Ravi Menon" asks the assistant for their portfolio companies
    Then the assistant answer should not name "Bluefin Health"

  # E70 — Edge case: a Hidden fund's holdings are never read
  Scenario: Assistant and a hidden fund
    Given there is a fund "name=Growth Fund II;currency=INR;show_portfolios=false" for the entity
    Given the fund "Growth Fund II" holds:
      | company     | instrument | purchases | cost_cr | fmv_cr |
      | Kestrel Bio | Seed CCPS  | 1         | 4.00    | 4.00   |
    Given LP "Anita Rao" has folio "G-007" in "Growth Fund II"
    When LP "Anita Rao" asks the assistant for their portfolio companies
    Then the assistant answer should not name "Kestrel Bio"

  # E71 — Edge case: under Whole fund the assistant names every holding
  Scenario: Assistant under whole fund
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    When LP "Ravi Menon" asks the assistant for their portfolio companies
    Then the assistant answer should name "Acme Robotics, Bluefin Health, Cedar Logistics, Delta AI"

  # X18 — Error case: a holdings query without the visible-holdings placeholder is rejected
  Scenario: Assistant query without scope
    When the assistant runs a holdings query for LP "Ravi Menon" without the visible-holdings placeholder
    Then the assistant answer should name "missing {VISIBLE_API_IDS} placeholder — scope required."
