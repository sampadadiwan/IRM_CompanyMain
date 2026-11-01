@rack_test @report_builder
Feature: Report Builder guided wizard — five steps onto the same report

  Worked examples: openspec/changes/report-builder-live-builder/business-rules.md
  1 Each row (a card per table), 2 What to show (own and related columns with
  totals), 3 Fund and filters (read back as sentences), 4 Order and
  calculations (suggested formulas), 5 Check and save (summary, check, name).

  Background:
    Given the Acme report builder data
    And I am signed in as Meera

  # H18 — Happy path: step 1 has a card per reportable table, each with an icon and an example question
  Scenario: Cards with examples
    When I open the wizard
    Then the wizard offers a card with an example question for every reportable table

  # H19 — Happy path: choosing Investors creates "Untitled Investor report" and opens step 2 (no name asked yet)
  Scenario: No name yet
    When I start a wizard report on "Investor"
    Then the wizard report is named "Untitled Investor report"
    And I am on wizard step "show"

  # H20 — Happy path: own and related columns added together; the join is added and both amounts total with Sum (also report-builder-trust H25: Sum shown and saved)
  Scenario: Own and related columns together
    Given a wizard "Investor" report
    When I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    Then the report includes related data "capital_commitments"
    And the report has 3 columns in all
    And the stored total for "capital_commitments.committed_amount" is "sum"
    And the stored total for "capital_commitments.call_amount" is "sum"
    And the wizard step shows the total "Sum" for "capital_commitments.committed_amount"

  # H21 — Happy path: setting Called to Count on step 2 is saved and shown (also report-builder-trust H26)
  Scenario: Change a total inline
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    When I set the total for "capital_commitments.call_amount" to "count" in the wizard
    Then I am on wizard step "show"
    And the stored total for "capital_commitments.call_amount" is "count"
    And the wizard step shows the total "Count" for "capital_commitments.call_amount"

  # H22 — Happy path: step 3 has the 5-row sample beside it
  Scenario: Sample beside the step
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount" in the wizard
    When I open wizard step "fund_filters"
    Then the step has the 5-row sample

  # H23 — Happy path: picking Growth Fund II limits the commitments and reads back as a sentence
  Scenario: Fund on related data
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount" in the wizard
    When I pick the fund "Growth Fund II" in the wizard
    Then the related data "capital_commitments" is limited to the fund "Growth Fund II"
    And the step reads "Only capital commitments in Growth Fund II"

  # H24 — Happy path: Category is LP reads back as a sentence
  Scenario: Sentence filters
    Given a wizard "Investor" report
    And I add "investor_name" in the wizard
    When I add the wizard filter "category" "eq" "LP"
    Then I am on wizard step "fund_filters"
    And the step reads "Only include investors where Category is LP"

  # H25 — Happy path: with Committed, Called and Collected, step 4 suggests Called %, Unpaid and Uncalled
  Scenario: Suggestions offered
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount, capital_commitments.collected_amount" in the wizard
    When I open wizard step "order"
    Then the wizard suggests "Called %, Unpaid, Uncalled"

  # H26 — Happy path: adding Called % saves the formula and the suggestion shows Added
  Scenario: Add a suggestion
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    And I open wizard step "order"
    When I add the suggestion "Called %"
    Then the report has the formula "Called %"
    And I am on wizard step "order"
    And the suggestion "Called %" shows Added

  # H27 — Happy path: step 5 has the summary cards and suggests "Investors — Committed, Called — Growth Fund II"
  Scenario: Summary and suggested name
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    And I pick the fund "Growth Fund II" in the wizard
    When I open wizard step "check"
    Then the summary has the cards "Each row, Columns, Only include, Order and calculations"
    And the step reads "Only capital commitments in Growth Fund II"
    And the name box suggests "Investors — Committed, Called — Growth Fund II"

  # H28 — Happy path: the Only include card opens step 3
  Scenario: Card opens its step
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount" in the wizard
    And I open wizard step "check"
    When I follow the "Only include" card
    Then I am on wizard step "fund_filters"

  # H29 — Happy path: Save and open names the report and opens its report page
  Scenario: Save and open
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    And I pick the fund "Growth Fund II" in the wizard
    And I open wizard step "check"
    When I save and open the wizard report with the suggested name
    Then the wizard report is named "Investors — Committed, Called — Growth Fund II"
    And I am on the report's page

  # H30 — Happy path: Fine-tune in builder opens the builder
  Scenario: Fine-tune
    Given a wizard "Investor" report
    And I add "investor_name" in the wizard
    And I open wizard step "check"
    When I choose Fine-tune in builder
    Then the builder opens

  # E21 — Edge case: with several related sources, only the exchange rate's own columns start open
  Scenario: Many related sources
    Given a wizard "ExchangeRate" report
    When I open wizard step "show"
    Then the wizard picker opens only "About the exchange rate"
    And the wizard picker lists "From documents, From leg1, From leg2" closed

  # E22 — Edge case: All funds removes the fund filter
  Scenario: All funds
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount" in the wizard
    And I pick the fund "Growth Fund II" in the wizard
    When I pick the fund "All funds" in the wizard
    Then the report has no fund filter

  # E23 — Edge case: neither exchange rates nor their related data have a fund, so there is no fund picker
  Scenario: No fund
    Given a wizard "ExchangeRate" report
    When I open wizard step "fund_filters"
    Then the step has no fund picker

  # E24 — Edge case: with only the investor's name there is nothing to suggest
  Scenario: Nothing to suggest
    Given a wizard "Investor" report
    And I add "investor_name" in the wizard
    When I open wizard step "order"
    Then the step reads "No suggestions for these columns"

  # E25 — Edge case: a blank name keeps the suggested one
  Scenario: Blank name
    Given a wizard "Investor" report
    And I add "investor_name, capital_commitments.committed_amount, capital_commitments.call_amount" in the wizard
    And I pick the fund "Growth Fund II" in the wizard
    When I save and open the wizard report with a blank name
    Then the wizard report is named "Investors — Committed, Called — Growth Fund II"

  # E26 — Edge case: links to the old six steps land on the steps that replaced them
  Scenario: Old links
    Given a wizard "Investor" report
    Then the old wizard steps redirect as "columns → show, joins → show, aggregates → show, filters → fund_filters, sort → order, review → check"

  # X4 — Error case: an unknown table goes back to step 1 with a message and creates nothing
  Scenario: Unknown table
    When I start a wizard report on "NotAModel"
    Then I am back on the wizard start with "Choose one of the listed tables"
    And no report is created

  # X5 — Error case: a user of another entity can't open the report's step 2
  Scenario: Another entity
    Given a wizard "Investor" report
    And I am signed in as Omar from another entity
    When I open wizard step "show"
    Then the change is refused
