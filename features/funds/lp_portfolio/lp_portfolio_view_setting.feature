Feature: Fund LP portfolio view
  One dropdown on the fund form decides what LPs see of the portfolio — hidden, the whole fund, only holdings
  allocated to their folio, or those plus their own share — with the allocation and FMV formula picks.
  Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  (H4, H5, H6, H7, E1, E2, E3, E4, E7, E8, E79, E95, X1, X2, X3, X4, X5, X20)

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas

  # H4 — Happy path: Meera chooses Allocated, with their own share, picks #501 / #502; the pickers list only holding-level formulas
  Scenario: Fund team picks the view and formulas
    When I open the LP portfolio view on the fund form
    And I choose "Allocated, with their own share" in the LP portfolio view
    Then the allocation formula picker should list only "Allocated Portfolio Cost,Allocated Portfolio FMV,Apportioned Deal Expense,Portfolio FMV by API"
    When I set the LP portfolio view to "Allocated, with their own share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio FMV" on the fund form and save
    Then I should see "Fund was successfully updated."
    And the fund LP portfolio view should be "allocated_with_share"

  # H5 — Happy path: Meera chooses Allocated to their folio with #501 and saves
  Scenario: Fund team selects Allocated to their folio
    Given the allocation formula "Allocated Portfolio Cost" has a folio entry
    When I set the LP portfolio view to "Allocated to their folio" with allocation formula "Allocated Portfolio Cost" on the fund form and save
    Then I should see "Fund was successfully updated."
    And the fund LP portfolio view should be "allocated"
    And the fund LP allocation formula should be "Allocated Portfolio Cost"

  # H6 — Happy path: a fund that showed portfolios before the change opens as Whole fund portfolio
  Scenario: Existing fund that showed portfolios
    Then the fund LP portfolio view should be "whole_fund"
    And the LP portfolio view on the form should show "Whole fund portfolio"

  # H7 — Happy path: a fund that hid portfolios opens as Hidden from LPs
  Scenario: Existing fund that hid portfolios
    Given the fund LP portfolio view is "hidden"
    Then the LP portfolio view on the form should show "Hidden from LPs"

  # E1 — Edge case: saving an Allocated view whose formula has no folio entries saves, with a warning
  Scenario: Warning when the formula has no folio entries
    When I set the LP portfolio view to "Allocated to their folio" with allocation formula "Allocated Portfolio Cost" on the fund form and save
    Then I should see "Fund was successfully updated."
    And I should see "No folio allocations found for this fund yet. LPs will see an empty portfolio until an allocation run completes."
    And the fund LP portfolio view should be "allocated"

  # E2 — Edge case: a fund uploaded with "Show Fund Portfolios To Lps" = Yes is Whole fund; No is Hidden
  Scenario: Upload creates a Whole fund fund
    When a fund "Uploaded Fund A" is uploaded with "Show Fund Portfolios To Lps" = "Yes"
    Then the fund LP portfolio view should be "whole_fund"
    When a fund "Uploaded Fund B" is uploaded with "Show Fund Portfolios To Lps" = "No"
    Then the fund LP portfolio view should be "hidden"

  # E3 — Edge case: the legacy switch turned off keeps the folio bit and pick; turned on restores Allocated
  Scenario: Legacy switch off and on restores the view
    Given the fund LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    When a client sets the legacy show portfolios switch to "false"
    Then the fund LP portfolio view should be "hidden"
    And the fund LP portfolio bits should include "lp_folio_portfolio"
    And the fund LP allocation formula should be "Allocated Portfolio Cost"
    When a client sets the legacy show portfolios switch to "true"
    Then the fund LP portfolio view should be "allocated"

  # E4 — Edge case: switching to Whole fund and back keeps the formula picks
  Scenario: Picks kept across views
    Given the fund LP portfolio view is "allocated_with_share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio FMV"
    When I set the LP portfolio view to "Whole fund portfolio" on the fund form and save
    Then the fund LP portfolio view should be "whole_fund"
    When I set the LP portfolio view to "Allocated, with their own share" on the fund form and save
    Then the fund LP portfolio view should be "allocated_with_share"
    And the fund LP allocation formula should be "Allocated Portfolio Cost"

  # E7 — Edge case: a new fund starts Hidden from LPs
  Scenario: New fund default
    When a fund "Growth Fund III" is created in the entity
    Then the fund LP portfolio view should be "hidden"

  # E8 — Edge case: the allocation picker shows for both Allocated options, the FMV picker only for own share
  Scenario: Pickers follow the option
    When I open the LP portfolio view on the fund form
    And I choose "Whole fund portfolio" in the LP portfolio view
    Then the allocation formula picker should be "hidden"
    And the FMV formula picker should be "hidden"
    When I choose "Allocated to their folio" in the LP portfolio view
    Then the allocation formula picker should be "visible"
    And the FMV formula picker should be "hidden"
    When I choose "Allocated, with their own share" in the LP portfolio view
    Then the FMV formula picker should be "visible"

  # E79 — Edge case: the ⓘ next to LP portfolio view points to the company switch and LP layouts
  Scenario: Fund view tooltip
    When I open the LP portfolio view on the fund form
    Then the LP portfolio view tooltip should read "Decides which holdings LPs see. To let LPs open a company's page, also switch the company to Show to LPs and set up an LP layout."

  # X1 — Error case: own share without a Your FMV formula is refused
  Scenario: Missing FMV formula
    When I set the LP portfolio view to "Allocated, with their own share" with allocation formula "Allocated Portfolio Cost" on the fund form and save
    Then I should see "Choose the allocation formula that gives the LP's FMV."
    And the fund LP portfolio view should be "whole_fund"

  # X2 — Error case: an Allocated view without an allocation formula is refused
  Scenario: Missing allocation formula
    When I set the LP portfolio view to "Allocated to their folio" on the fund form and save
    Then I should see "Choose the allocation formula that decides which holdings LPs see."
    And the fund LP portfolio view should be "whole_fund"

  # X3 — Error case: the same formula for allocation and Your FMV is refused
  Scenario: Same formula twice
    When I set the LP portfolio view to "Allocated, with their own share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio Cost" on the fund form and save
    Then I should see "Your cost and Your FMV must use different formulas."

  # X4 — Error case: another fund's formula sent directly is refused, for either pick
  Scenario: Formula of another fund
    Given another fund "Feeder Fund F" has the formula "Master PI Cost"
    Given the fund LP portfolio view is "allocated_with_share" with allocation formula "Allocated Portfolio Cost" and FMV formula "Allocated Portfolio FMV"
    When a request sets the fund "lp_allocation_fund_formula_id" to the formula "Master PI Cost"
    Then the fund save should be refused with "Pick one of this fund's portfolio allocation formulas."
    When a request sets the fund "lp_fmv_fund_formula_id" to the formula "Master PI Cost"
    Then the fund save should be refused with "Pick one of this fund's portfolio allocation formulas."

  # X5 — Error case: proforma, company-level or non-portfolio formulas are refused
  Scenario: Proforma, company-level or non-portfolio formula
    Given the fund LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"
    When a request sets the fund "lp_allocation_fund_formula_id" to the formula "Allocated Portfolio Cost Proforma"
    Then the fund save should be refused with "Pick one of this fund's portfolio allocation formulas."
    When a request sets the fund "lp_allocation_fund_formula_id" to the formula "Company Fees"
    Then the fund save should be refused with "Pick one of this fund's portfolio allocation formulas."
    When a request sets the fund "lp_allocation_fund_formula_id" to the formula "Management Fee"
    Then the fund save should be refused with "Pick one of this fund's portfolio allocation formulas."

  # E95 — Edge case: without the fund portfolios module the portfolio settings are hidden; saving keeps their values
  Scenario: Portfolio settings hidden without the module
    Given the fund has the feature "show_valuations" on
    Given the fund manager does not have the "fund portfolios" module
    When I open the LP portfolio view on the fund form
    Then I should not see "LP portfolio view"
    And I should not see "Portfolio valuations"
    When I save the fund features
    Then I should see "Fund was successfully updated."
    And the fund LP portfolio view should be "whole_fund"
    And the fund features should include "show_portfolios,show_valuations"

  # X20 — Error case: without the module a direct request for a portfolio switch is refused, and the view is ignored
  @rack_test
  Scenario: Portfolio switch submitted without the module
    Given the fund manager does not have the "fund portfolios" module
    When a request saves the fund features "show_fund_units,show_valuations" with the LP portfolio view "hidden"
    Then the fund features should not include "show_valuations"
    And the fund LP portfolio view should be "whole_fund"
