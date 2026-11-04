@rack_test @report_builder
Feature: Report Builder starter templates — pick one, choose a fund, get a new report

  Worked examples: openspec/changes/report-builder-starting-points/business-rules.md
  New report › From a template lists the templates the company can use. A
  template always creates a new report; templates that add up money need one
  fund, so INR and USD amounts are never summed together.

  Background:
    Given the Acme report builder data
    And Acme has the Funds and Deals features
    And I am signed in as Meera

  # H2 — Happy path: all 10 templates, grouped by area
  Scenario: Templates grouped by area
    When I open the template page
    Then the template page lists the areas "Investors, Capital calls, Distributions, Fund overview, Portfolio, Compliance"
    And the template page lists 10 templates

  # H3 — Happy path: a card says what the template answers, where it starts and that it needs a fund
  Scenario: Card says what the template answers
    When I open the template page
    Then the "lp_capital_account" card reads "Which LPs owe us money, and how much of each commitment is called?"
    And the "lp_capital_account" card reads "Starts from Investors"
    And the "lp_capital_account" card reads "Needs a fund"
    And the "lp_capital_account" card reads "Includes: 3 formulas · sorted by Unpaid"

  # H4 — Happy path: LP Capital Account Summary for Growth Fund II opens in the builder, filtered, sorted and clean
  Scenario: Create from a template with a fund
    When I create "lp_capital_account" from its template with the fund "Growth Fund II"
    Then the builder opens for "LP Capital Account Summary — Growth Fund II" saying "Created from LP Capital Account Summary"
    And the report's columns are "Stakeholder, Category, City, Tags, Committed, Called, Collected, Distributed, # Commitments, Called %, Unpaid, Uncalled"
    And the report's own rows are filtered by '{"category_eq": "LP"}'
    And the report's "capital_commitments" are limited to "Growth Fund II"
    And the created report is sorted by "Unpaid" "desc"
    And the report check says "All good" for the report
    And the created report lists "Aditi Rao" first, then "Kiran Mehta, Nova LP"
    And the created report's rows show "Aditi Rao: Unpaid=20,00,000.00 | Called %=40.00; Kiran Mehta: Unpaid=0.00 | Called %=40.00"

  # H5 — Happy path: Fund Scorecard asks for no fund and lists one row per fund, most committed first
  Scenario: Template without a fund
    When I open the template page
    Then the "fund_scorecard" popup has no Fund field
    When I create "fund_scorecard" from its template with the fund ""
    Then the created report is named "Fund Scorecard"
    And the created report's rows are "Growth Fund II, Global Fund"

  # H6 — Happy path: Unverified KYC with All funds has no fund filter and lists the unverified KYC
  Scenario: Optional fund
    When I create "unverified_kyc" from its template with the fund "All funds"
    Then the created report is named "Unverified KYC: Money at Stake"
    And the report has no fund filter at all
    And the created report's rows are "Mehta HUF"
    And the report check says "All good" for the report

  # H7 — Happy path: the call tracker pivots remittances by status, limited to Growth Fund II's calls
  Scenario: Template with a pivot
    When I create "call_collection" from its template with the fund "Growth Fund II"
    Then the report has a pivot on "capital_remittances"
    And the report's own rows are limited to "Growth Fund II"

  # H8 — Happy path: a typed name is kept exactly, with no fund added
  Scenario: Name typed by the user
    When I create "lp_capital_account" from its template named "Q3 LP accounts" with the fund "Growth Fund II"
    Then the created report is named "Q3 LP accounts"

  # E1 — Edge case: a template that adds up money refuses to create without a fund, and offers no All funds
  Scenario: Required fund
    When I open the template page
    Then the "lp_capital_account" popup's funds are "— choose a fund —, Global Fund, Growth Fund II"
    When I create "lp_capital_account" from its template with the fund ""
    Then no report is created from the template
    And the template popup says "Choose a fund — this template adds up amounts"

  # E2 — Edge case: without the Funds feature only the KPI matrix is listed, and a fund template can't be created
  Scenario: Templates follow the company's features
    Given Acme has the Deals feature but not Funds
    When I open the template page
    Then the template page lists only "Portfolio KPI Matrix"
    When I create "lp_capital_account" from its template with the fund "Growth Fund II"
    Then no report is created from the template
    And the template page says "That template isn't available"

  # E3 — Edge case: with All funds and commitments in INR and USD, the report check warns
  Scenario: Optional fund warns on mixed currencies
    Given K2 also has Aditi's Global Fund commitment
    When I create "unverified_kyc" from its template with the fund "All funds"
    Then the report check warns "Committed adds amounts in INR and USD — pick a fund or split by fund" for the report

  # E6 — Edge case: a blank name becomes the template's name and the fund
  Scenario: Blank name
    When I create "lp_capital_account" from its template named "" with the fund "Growth Fund II"
    Then the created report is named "LP Capital Account Summary — Growth Fund II"

  # E8 — Edge case: the fund list has only Acme's funds
  Scenario: Fund list
    Given Beta Partners has the fund "Beta Fund"
    When I open the template page
    Then the "unverified_kyc" popup's funds are "All funds, Global Fund, Growth Fund II"

  # E9 — Edge case: Fund Scorecard rows are funds (INR and USD) — a note about the totals row, no warning
  Scenario: Fund rows
    When I create "fund_scorecard" from its template with the fund ""
    Then the report check notes "The totals row adds funds in INR and USD" for the report, with no warning

  # X2 — Error case: another company's fund is refused (Access denied, as for any record of another company) and nothing is created
  Scenario: Fund of another company
    When I create "lp_capital_account" from its template with another company's fund
    Then the change is refused
    And no report is created from the template

  # X3 — Error case: an unknown template creates nothing
  Scenario: Unknown template
    When I create "no_such" from its template with the fund ""
    Then no report is created from the template
    And the template page says "That template isn't available"

  # X5 — Error case: a template broken after the check creates nothing and leaves no columns behind
  Scenario: Broken template creates nothing
    Given the template "lp_capital_account" breaks after the template check
    When I create "lp_capital_account" from its template with the fund "Growth Fund II"
    Then no report is created from the template
    And the template page says "That template can't be used right now"
