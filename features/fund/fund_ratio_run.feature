@import @rack_test
Feature: Fund Ratio Run — Cross-Fund and Cross-Portfolio Computations
  FundRatiosScenarioJob creates a FundRatioRun that records the exact
  parameters used in the calculation. FundRatio rows produced by the
  job must be linked to that run and must have fund_id set to nil.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1" for the entity
    And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"

  # ─── Cross-fund ───────────────────────────────────────────────────────────────

  Scenario: Cross-fund job creates a FundRatioRun and produces fund-id-less ratios
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed for scenario "CF-Test" on "31-03-2024" with the two funds
    Then a FundRatioRun should exist with run_type "cross-fund" and scenario "CF-Test"
    And the FundRatioRun should record both fund ids
    And all FundRatios for the run should have fund_id nil
    And all FundRatios for the run should be linked to the FundRatioRun

  Scenario: Cross-fund FundRatioRun is queryable by source fund via scope
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed for scenario "Scope-Test" on "31-03-2024" with the two funds
    Then FundRatioRun.for_source_fund should return the run for each selected fund
    And FundRatioRun.for_source_fund should not return the run for an unrelated fund

  Scenario: Re-running a cross-fund job on the same date reuses the existing FundRatioRun
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed for scenario "Idem-Test" on "31-03-2024" with the two funds
    And the cross-fund ratios are computed for scenario "Idem-Test" on "31-03-2024" with the two funds
    Then only one FundRatioRun should exist for the run's fingerprint on "31-03-2024"
    And the FundRatios for the run should not be duplicated

  Scenario: Cross-fund job creates all eight expected ratio names
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed for scenario "Names-Test" on "31-03-2024" with the two funds
    Then the cross-fund run should contain ratios named:
      | XIRR                         |
      | MOIC                         |
      | RVPI                         |
      | DPI                          |
      | TVPI                         |
      | Portfolio Value to Cost      |
      | Paid In to Committed Capital |
      | Gross Portfolio IRR          |

  Scenario: FundRatio.scenario is auto-populated from FundRatioRun.name
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed for scenario "Scenario-Pop-Test" on "31-03-2024" with the two funds
    Then all FundRatios for the run should have scenario set to the run name

  # ─── Cross-portfolio — explicit company selection ─────────────────────────────

  Scenario: Cross-portfolio job creates a FundRatioRun linked to selected companies
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector     | tag_list |
      | Alpha Co | Fintech    | growth   |
      | Beta Co  | Healthcare | stable   |
    And the cross-portfolio ratios are computed for scenario "CP-Test" on "31-03-2024" with portfolio company ids
    Then a FundRatioRun should exist with run_type "cross-portfolio" and scenario "CP-Test"
    And the FundRatioRun should record both portfolio company ids
    And all FundRatios for the run should have fund_id nil
    And per-company FundRatios should exist for each selected portfolio company

  # ─── Cross-portfolio — sector filter ─────────────────────────────────────────

  Scenario: Cross-portfolio sector filter resolves correct companies
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector     | tag_list |
      | Alpha Co | Fintech    | growth   |
      | Beta Co  | Healthcare | stable   |
      | Gamma Co | Fintech    | seed     |
    And the cross-portfolio ratios are computed for scenario "Sector-Test" on "31-03-2024" with sectors "Fintech"
    Then a FundRatioRun should exist with run_type "cross-portfolio" and scenario "Sector-Test"
    And the FundRatioRun should store sector "Fintech"
    And per-company FundRatios should exist for "Alpha Co" and "Gamma Co"
    And no FundRatios should exist for "Beta Co" in scenario "Sector-Test"

  Scenario: FundRatioRun.for_source_sector scope returns correct runs
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector     | tag_list |
      | Alpha Co | Fintech    | growth   |
      | Beta Co  | Healthcare | stable   |
    And the cross-portfolio ratios are computed for scenario "Fintech-Run" on "31-03-2024" with sectors "Fintech"
    And the cross-portfolio ratios are computed for scenario "Health-Run" on "31-03-2024" with sectors "Healthcare"
    Then FundRatioRun.for_source_sector "Fintech" should return only the "Fintech-Run" run
    And FundRatioRun.for_source_sector "Healthcare" should return only the "Health-Run" run

  Scenario: FundRatioRun.for_source_tag scope returns correct runs
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector     | tag_list |
      | Alpha Co | Fintech    | growth   |
      | Beta Co  | Healthcare | stable   |
    And the cross-portfolio ratios are computed for scenario "Growth-Tag-Run" on "31-03-2024" with tag "growth"
    And the cross-portfolio ratios are computed for scenario "Stable-Tag-Run" on "31-03-2024" with tag "stable"
    Then FundRatioRun.for_source_tag "growth" should return only the "Growth-Tag-Run" run
    And FundRatioRun.for_source_tag "stable" should return only the "Stable-Tag-Run" run

  # ─── Cross-portfolio — per-company metrics and scope ─────────────────────────

  Scenario: Cross-portfolio job creates Value To Cost and MOIC per company
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector  | tag_list |
      | Alpha Co | Fintech | growth   |
      | Beta Co  | SaaS    | stable   |
    And the cross-portfolio ratios are computed for scenario "Metrics-Test" on "31-03-2024" with portfolio company ids
    Then per-company Value To Cost and MOIC FundRatios should exist for each selected portfolio company

  Scenario: FundRatioRun.for_source_portfolio_company returns the run for each selected company
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector  | tag_list |
      | Alpha Co | Fintech | growth   |
      | Beta Co  | SaaS    | stable   |
    And the cross-portfolio ratios are computed for scenario "PC-Scope-Test" on "31-03-2024" with portfolio company ids
    Then FundRatioRun.for_source_portfolio_company should return the run for each selected company
    And FundRatioRun.for_source_portfolio_company should not return the run for an unrelated company

  # ─── Cross-portfolio — explicit IDs bypass tag+sector AND ────────────────────
  # Tags and sectors are AND'd when both are supplied. Explicit portfolio_company_ids
  # are always included regardless of the tag/sector filters.

  Scenario: Explicit IDs always included; tags and sectors that share no common company both exclude non-matching companies
    Given there are portfolio companies with sectors for cross-portfolio testing:
      | name     | sector     | tag_list |
      | Alpha Co | Fintech    | growth   |
      | Beta Co  | Healthcare | stable   |
      | Gamma Co | SaaS       | growth   |
    And the cross-portfolio ratios are computed for scenario "ExplicitBypass-Test" on "31-03-2024" with:
      | filter              | value      |
      | portfolio_company   | Alpha Co   |
      | tag                 | stable     |
      | sector              | SaaS       |
    Then per-company FundRatios should exist for "Alpha Co"
    And no FundRatios should exist for "Beta Co" in scenario "ExplicitBypass-Test"
    And no FundRatios should exist for "Gamma Co" in scenario "ExplicitBypass-Test"
    And the FundRatioRun for scenario "ExplicitBypass-Test" should store sector "SaaS"

  # ─── Cross-portfolio — fund_ids filter ────────────────────────────────────────

  Scenario: Cross-portfolio fund_ids filter limits companies to those funds' investments
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And there are portfolio companies in different funds for cross-portfolio testing:
      | name     | fund   | sector  | tag_list |
      | Alpha Co | first  | Fintech | growth   |
      | Beta Co  | second | SaaS    | stable   |
    And the cross-portfolio ratios are computed for scenario "FundFilter-Test" on "31-03-2024" with all company ids and first fund filter
    Then per-company FundRatios should exist for "Alpha Co"
    And no FundRatios should exist for "Beta Co" in scenario "FundFilter-Test"
    And FundRatioRun.for_source_fund should return the cross-portfolio run for the first fund
    And FundRatioRun.for_source_fund should not return the cross-portfolio run for the second fund

  Scenario: Cross-portfolio without fund_ids filter spans all entity funds
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And there are portfolio companies in different funds for cross-portfolio testing:
      | name     | fund   | sector  | tag_list |
      | Alpha Co | first  | Fintech | growth   |
      | Beta Co  | second | SaaS    | stable   |
    And the cross-portfolio ratios are computed for scenario "AllFunds-Test" on "31-03-2024" with all company ids and no fund filter
    Then per-company FundRatios should exist for "Alpha Co"
    And per-company FundRatios should exist for "Beta Co"

  # ─── Nil anchor fund ──────────────────────────────────────────────────────────

  Scenario: Cross-fund job with nil anchor fund still creates FundRatioRun and ratios
    Given there is a second fund "name=Demo Fund B;currency=INR" for the entity
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And the cross-fund ratios are computed with nil anchor fund on "31-03-2024" with the two funds
    Then a FundRatioRun should exist with run_type "cross-fund" and scenario "nil-anchor"
    And the FundRatioRun should have nil anchor_fund
    And all FundRatios for the run should have fund_id nil
