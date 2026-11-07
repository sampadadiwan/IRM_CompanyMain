# Worked examples H19, H20, E28–E32 —
# openspec/changes/grid-columns-inline-settings/business-rules.md#1b-hand-built-list-tables--phase-2
Feature: Hand-built lists get the columns button
  Lists that used to render fixed columns, sorted and searched in the page by jQuery DataTables, now use the firm's
  chosen columns. With none chosen they show exactly what they showed before; in-page search and sort still work.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And my firm has funds "Growth Fund I, Fund II"

  # H19 — Happy path: the Funds list shows today's columns, links and the button beside the DataTables search box
  Scenario: Funds list unchanged by default
    When I open the "/funds" page
    Then the "funds" table headings should be "Name, Category, Tag List, Committed, Collected, Distributed"
    And the "funds" list should link each name to its record
    And the columns button should be beside the DataTables search box

  # H20 — Happy path: a custom field column added to the Distributions list shows its value
  Scenario: Add a column to Distributions
    Given my firm's "CapitalDistribution" form type has a text field "tranche"
    And the fund "Growth Fund I" has distributions "Dec 2025, Jun 2026"
    And the distribution "Dec 2025" has "tranche" set to "T1"
    When I open the distributions of the fund "Growth Fund I"
    Then the "capital_distributions" table headings should be "Name, Distribution Date, Gross Payable, Net Payable, Distributed, Approved"
    When I open the columns panel
    And I add the column "Tranche"
    And I save the columns
    Then the "capital_distributions" table headings should include "Tranche"
    And the "capital_distributions" table should show "T1"

  # E28 — Edge case: after changing the columns, the in-page search and sort still work
  Scenario: Search and sort after customising
    Given my firm's "CapitalDistribution" form type has a text field "tranche"
    And the fund "Growth Fund I" has distributions "Dec 2025, Jun 2026"
    And my firm's "CapitalDistribution" columns are "title_link, distribution_date, custom_fields.tranche"
    When I open the distributions of the fund "Growth Fund I"
    And I search the DataTables list for "Dec"
    Then the "capital_distributions" list should show only "Dec 2025"
    When I clear the DataTables search
    And I sort the "capital_distributions" list by "Name"
    And I sort the "capital_distributions" list by "Name"
    Then the first row of the "capital_distributions" list should be "Jun 2026"

  # E29 — Edge case: Configure Grids is offered for a record type that now has standard columns
  Scenario: Configure Grids offered
    When I open the form type page for my firm's "CapitalDistribution"
    Then the page should offer Configure Grids

  # E31 — Edge case: at phone width the first column (the name) stays; the actions fold behind ▶
  Scenario: Phone width keeps the name
    Given my browser is 400 pixels wide
    When I open the "/funds" page
    Then the "funds" list should show its first column "Name"
    And the "funds" list should fold its actions column

  # E32 — Edge case: slightly too wide — the name and the buttons stay, middle columns fold
  Scenario: Slightly too wide keeps the name and the buttons
    Given my firm's "Fund" columns are "name, category, tag_badges, committed_amount, collected_amount, distributed_amount_abs, call_amount"
    And my browser is 1000 pixels wide
    When I open the "/funds" page
    Then the "funds" list should show its first column "Name"
    And the "funds" list should show its actions column
    And the "funds" list should fold some middle columns

  # E30 — Edge case: every converted list renders, with the columns button, for the firm's admin
  Scenario: Every converted list renders
    Given my firm has one record for each converted list
    Then each converted list should render with the columns button:
      | list                     | path                                                  |
      | Funds                    | /funds                                                |
      | Distributions            | /capital_distributions?fund_id={fund}                 |
      | Investments              | /investments                                          |
      | Investment Instruments   | /investment_instruments                               |
      | Portfolio Cashflows      | /portfolio_cashflows                                  |
      | Deal Investors           | /deal_investors?deal_id={deal}                        |
      | Approvals                | /approvals                                            |
      | Approval Responses       | /approval_responses?approval_id={approval}            |
      | Expressions of Interest  | /expression_of_interests?investment_opportunity_id={io} |
      | Investment Opportunities | /investment_opportunities?view=row                    |
      | Investor KPI Mappings    | /investor_kpi_mappings?investor_id={investor}         |
      | Users                    | /users                                                |
      | Secondary Sales          | /secondary_sales                                      |
      | Allocations              | /allocations                                          |
