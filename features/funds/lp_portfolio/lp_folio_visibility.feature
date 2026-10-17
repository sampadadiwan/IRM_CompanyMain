Feature: LP sees only the holdings allocated to their folio
  Under an Allocated LP portfolio view a holding is listed only when one of the LP's folios has a non-zero
  entry under the fund's allocation formula, dated on or before today. Every LP list and total follows it.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  (H1, H2, H15, E9–E28a, E42, E43, X17)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company         | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics   | Series B CCPS | 2         | 25.00   | 40.00  |
      | Bluefin Health  | Series A CCPS | 1         | 20.00   | 22.00  |
      | Cedar Logistics | Series A CCPS | 1         | 15.00   | 18.00  |
      | Delta AI        | Seed CCPS     | 1         | 3.00    | 3.00   |
      | Fenix Mobility  | Seed CCPS     | 1         | 5.00    | 5.00   |
      | Fenix Mobility  | Series A CCPS | 1         | 8.00    | 8.00   |
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company         | instrument    | amount | purchase |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 1.00   | 1        |
      | Allocated Portfolio Cost | Acme Robotics   | Series B CCPS | 1.50   | 2        |
      | Allocated Portfolio Cost | Cedar Logistics | Series A CCPS | 1.50   | 1        |
      | Allocated Portfolio Cost | Bluefin Health  | Series A CCPS | 0.00   | 1        |
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"

  # H1 — Happy path: under Whole fund portfolio Ravi sees every holding, with no folio banner
  Scenario: Whole fund view unchanged
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Acme Robotics, Bluefin Health, Cedar Logistics, Delta AI, Fenix Mobility"
    And I should not see "Showing investments allocated to your folio"

  # H2 — Happy path: under Allocated Ravi sees Acme and Cedar only; totals are 25 + 15 cost and 40 + 18 = ₹58 Cr FMV
  Scenario: Allocated view narrows to the folio
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Acme Robotics, Cedar Logistics"
    And the LP should not see the holdings "Bluefin Health, Delta AI, Fenix Mobility"
    And the LP folio banner should read "Showing investments allocated to your folio (F-012)"
    And the LP totals should show FMV "58" Cr for "Growth Fund I"

  # H15 — Happy path: a feeder LP sees the master fund holding allocated to their feeder folio
  Scenario: Feeder LP sees master holding
    Given there is a fund "name=Master Fund M;currency=INR;show_portfolios=true" for the entity
    Given the fund "Master Fund M" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Echo Foods | Equity     | 1         | 30.00   | 33.00  |
    Given there is a feeder fund "Feeder Fund F" of "Master Fund M"
    Given the fund "Feeder Fund F" has the formula "Master PI Cost" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Feeder Fund F" LP portfolio view is "allocated" with allocation formula "Master PI Cost"
    Given the fund "Master Fund M" has the formula "Master Fund Cost" of type "AllocatePortfolioInvestment"
    Given the fund "Master Fund M" LP portfolio view is "allocated" with allocation formula "Master Fund Cost"
    Given LP "Sunil Kapoor" has folio "FF-01" in "Feeder Fund F"
    Given folio "FF-01" has allocation entries:
      | formula        | company    | instrument | amount | holding fund  |
      | Master PI Cost | Echo Foods | Equity     | 0.12   | Master Fund M |
    When LP "Sunil Kapoor" opens the portfolio of "Master Fund M"
    Then the LP should see the holdings "Echo Foods"

  # E9 — Edge case: Hidden from LPs shows no holdings at all
  Scenario: Hidden view
    Given the fund "Growth Fund I" LP portfolio view is "hidden"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Acme Robotics, Cedar Logistics, Bluefin Health"

  # E10 — Edge case: Delta AI has no entries, so it is hidden under Allocated (listed under Whole fund, H1)
  Scenario: Holding not yet allocated
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E11 — Edge case: a proforma entry never reveals a holding
  Scenario: Proforma entries don't count
    Given folio "F-012" has allocation entries:
      | formula                           | company  | instrument | amount |
      | Allocated Portfolio Cost Proforma | Delta AI | Seed CCPS  | 0.30   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E12 — Edge case: an entry under one minor unit (0.4 paise) does not make a holding visible
  Scenario: Sub-unit allocation
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount     |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.4 paise  |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E13 — Edge case: exactly one minor unit (₹0.01) makes it visible
  Scenario: Exactly one unit
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount   |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 1 paise  |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Delta AI"

  # E14 — Edge case: a non-zero entry under another portfolio formula does not reveal the holding
  Scenario: Other portfolio formula doesn't count
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.00   |
      | Apportioned Deal Expense | Delta AI | Seed CCPS  | 0.05   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E15 — Edge case: a negative allocation-formula entry counts
  Scenario: Negative amount counts
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | -0.02  |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Delta AI"

  # E16 — Edge case: a non-portfolio formula entry on the holding is ignored
  Scenario: Non-portfolio formula ignored
    Given folio "F-012" has allocation entries:
      | formula        | company  | instrument | amount |
      | Management Fee | Delta AI | Seed CCPS  | 0.10   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E17 — Edge case: an entry dated after today does not count
  Scenario: Future-dated only
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount | date       |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.50   | 31/12/2099 |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E18 — Edge case: an entry dated today counts
  Scenario: Dated today
    Given folio "F-012" has an allocation-formula entry for "Delta AI" "Seed CCPS" of "0.50" dated today
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Delta AI"

  # E19 — Edge case: a deleted entry does not count
  Scenario: Deleted entry ignored
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount | deleted |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.50   | yes     |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"

  # E20 — Edge case: a company-level formula entry does not reveal a holding
  Scenario: Company-level formula doesn't count
    Given folio "F-012" has allocation entries:
      | formula      | company        | instrument | amount |
      | Company Fees | Fenix Mobility | Seed CCPS  | 0.10   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Fenix Mobility"

  # E20a — Edge case: an exited holding (non-zero earlier, zero at the latest date) stays visible
  Scenario: Exited holding stays visible
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount | date       |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.40   | 30/06/2026 |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.00   | 30/09/2026 |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Delta AI"

  # E21 — Edge case: with an aggregated-holding allocation formula, an entry on the holding reveals it
  Scenario: Aggregated-holding allocation formula
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Portfolio FMV by API"
    Given folio "F-012" has allocation entries:
      | formula              | company  | instrument | amount |
      | Portfolio FMV by API | Delta AI | Seed CCPS  | 0.20   |
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Delta AI"
    And the LP should not see the holdings "Acme Robotics"

  # E22 — Edge case: Priya is allocated only to Fenix Series A, so only that holding is listed under Fenix
  Scenario: Company with two holdings
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-051" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Fenix Mobility | Series A CCPS | 0.40   |
      | Allocated Portfolio Cost | Fenix Mobility | Seed CCPS     | 0.00   |
    When LP "Priya Shah" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Fenix Mobility, Series A CCPS"
    And the LP should not see the holdings "Seed CCPS"

  # E23 — Edge case: two folios combine — F-050 excused from Bluefin, F-051 allocated to it
  Scenario: Several folios combined
    Given LP "Priya Shah" has folio "F-050" in "Growth Fund I"
    Given LP "Priya Shah" has folio "F-051" in "Growth Fund I"
    Given folio "F-050" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Bluefin Health | Series A CCPS | 0.00   |
    Given folio "F-051" has allocation entries:
      | formula                  | company        | instrument    | amount |
      | Allocated Portfolio Cost | Bluefin Health | Series A CCPS | 1.00   |
    When LP "Priya Shah" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Bluefin Health"
    And the LP folio banner should read "Showing investments allocated to your folio (F-050, F-051)"

  # E24 — Edge case: a user with access but no folio sees the empty-portfolio message
  Scenario: No folio
    Given LP "Omar Khan" has access to "Growth Fund I" and no folio
    When LP "Omar Khan" opens the portfolio of "Growth Fund I"
    Then the LP folio banner should read "No investments have been allocated to your folio yet."
    And the LP should not see the holdings "Acme Robotics"

  # E25 — Edge case: a new allocation shows on the next page load
  Scenario: Re-run allocation
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should not see the holdings "Delta AI"
    Given folio "F-012" has allocation entries:
      | formula                  | company  | instrument | amount |
      | Allocated Portfolio Cost | Delta AI | Seed CCPS  | 0.70   |
    When the LP reloads the page
    Then the LP should see the holdings "Delta AI"

  # E26 — Edge case: under Whole fund an excused holding is still listed (its company page: card ⑥, phase 5)
  Scenario: Whole fund ignores excusal
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    When LP "Ravi Menon" opens the portfolio of "Growth Fund I"
    Then the LP should see the holdings "Bluefin Health"

  # E27 — Edge case: the holding's own fund decides — a Hidden master hides Echo Foods from a feeder LP
  Scenario: Master fund view governs master holdings
    Given there is a fund "name=Master Fund M;currency=INR;show_portfolios=true" for the entity
    Given the fund "Master Fund M" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Echo Foods | Equity     | 1         | 30.00   | 33.00  |
    Given there is a feeder fund "Feeder Fund F" of "Master Fund M"
    Given the fund "Feeder Fund F" has the formula "Master PI Cost" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Feeder Fund F" LP portfolio view is "allocated" with allocation formula "Master PI Cost"
    Given the fund "Master Fund M" LP portfolio view is "hidden"
    Given LP "Sunil Kapoor" has folio "FF-01" in "Feeder Fund F"
    Given folio "FF-01" has allocation entries:
      | formula        | company    | instrument | amount | holding fund  |
      | Master PI Cost | Echo Foods | Equity     | 0.12   | Master Fund M |
    When LP "Sunil Kapoor" opens the portfolio of "Master Fund M"
    Then the LP should not see the holdings "Echo Foods"

  # E28 — Edge case: a zero feeder allocation keeps the master holding hidden
  Scenario: Feeder folio without master allocation
    Given there is a fund "name=Master Fund M;currency=INR;show_portfolios=true" for the entity
    Given the fund "Master Fund M" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Echo Foods | Equity     | 1         | 30.00   | 33.00  |
    Given there is a feeder fund "Feeder Fund F" of "Master Fund M"
    Given the fund "Feeder Fund F" has the formula "Master PI Cost" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Feeder Fund F" LP portfolio view is "allocated" with allocation formula "Master PI Cost"
    Given the fund "Master Fund M" has the formula "Master Fund Cost" of type "AllocatePortfolioInvestment"
    Given the fund "Master Fund M" LP portfolio view is "allocated" with allocation formula "Master Fund Cost"
    Given LP "Sunil Kapoor" has folio "FF-01" in "Feeder Fund F"
    Given folio "FF-01" has allocation entries:
      | formula        | company    | instrument | amount | holding fund  |
      | Master PI Cost | Echo Foods | Equity     | 0.00   | Master Fund M |
    When LP "Sunil Kapoor" opens the portfolio of "Master Fund M"
    Then the LP should not see the holdings "Echo Foods"

  # E28a — Edge case: a feeder fund with no allocation formula shows no master holdings
  Scenario: Feeder fund with no allocation formula
    Given there is a fund "name=Master Fund M;currency=INR;show_portfolios=true" for the entity
    Given the fund "Master Fund M" holds:
      | company    | instrument | purchases | cost_cr | fmv_cr |
      | Echo Foods | Equity     | 1         | 30.00   | 33.00  |
    Given there is a feeder fund "Feeder Fund F" of "Master Fund M"
    Given the fund "Feeder Fund F" has the formula "Master PI Cost" of type "AllocateMasterFundPortfolioInvestment"
    Given the fund "Master Fund M" has the formula "Master Fund Cost" of type "AllocatePortfolioInvestment"
    Given the fund "Master Fund M" LP portfolio view is "allocated" with allocation formula "Master Fund Cost"
    Given LP "Sunil Kapoor" has folio "FF-01" in "Feeder Fund F"
    Given folio "FF-01" has allocation entries:
      | formula        | company    | instrument | amount | holding fund  |
      | Master PI Cost | Echo Foods | Equity     | 0.12   | Master Fund M |
    When LP "Sunil Kapoor" opens the portfolio of "Master Fund M"
    Then the LP should not see the holdings "Echo Foods"

  # E42 — Edge case: under Allocated the LP's fund Portfolio Dashboard keeps only the holdings list
  Scenario: Fund-wide charts hidden
    When LP "Ravi Menon" opens the portfolio dashboard of "Growth Fund I"
    Then the LP portfolio dashboard should show only the holdings list
    Given the fund "Growth Fund I" LP portfolio view is "whole_fund"
    When LP "Ravi Menon" opens the portfolio dashboard of "Growth Fund I"
    Then the LP portfolio dashboard should show the fund-wide charts

  # E43 — Edge case: the purchases list agrees with the holdings list
  Scenario: Aggregated and instrument lists agree
    When LP "Ravi Menon" opens the purchases list of "Growth Fund I"
    Then the LP should see the holdings "Acme Robotics, Cedar Logistics"
    And the LP should not see the holdings "Bluefin Health, Delta AI, Fenix Mobility"

  # X17 — Error case: a hidden holding requested directly — list filtered to it is empty, detail is refused
  Scenario: Direct request for a hidden holding
    When LP "Ravi Menon" requests the holding "Bluefin Health" "Series A CCPS" of "Growth Fund I" directly
    Then the direct holding page should be refused
