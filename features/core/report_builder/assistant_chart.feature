@rack_test @report_builder
Feature: Report Builder assistant — charts

  Worked examples: openspec/changes/report-builder-assistant/business-rules.md
  The draft's preview suggests a chart by rules (no AI call); "Describe a
  chart" sends the preview rows to the AI; a saved report shows its chart
  above the table with Hide chart.

  Background:
    Given the Acme report builder data
    And Acme has a default AI model
    And I am signed in as Meera

  # H5 — Happy path: text + amount → a horizontal bar of the first amount by the first text column
  Scenario: Suggested chart
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    When I pick the fund "Growth Fund II" for the draft
    Then the draft's chart is "Bar — Committed by Investor" drawn as a horizontal bar of "Aditi Rao, Kiran Mehta, Nova LP"

  # H7 — Happy path: the saved report shows its chart above the table, with Hide chart
  Scenario: Chart on the report page
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And I pick the fund "Growth Fund II" for the draft
    And I save the draft as "LPs owing — GF2"
    When I open the saved report's page
    Then the report page shows the chart "Bar — Committed by Investor" with Hide chart

  # H8 — Happy path: Describe a chart sends the preview rows to the AI and keeps the chart for the report
  Scenario: Describe a chart
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And the chart AI draws a pie
    When I describe the chart "pie of committed by investor"
    Then the chart AI got the 3 preview rows
    And the draft's chart is "pie of committed by investor"
    And the draft page says "Sends these 20 rows to your configured AI model"

  # E6 — Edge case: one of the largest tables previews, and the report check gives the export row count
  Scenario: A very large table
    Given the AI picks "CapitalRemittance" and answers with columns "Folio=folio_id, Call amount=call_amount"
    And the export threshold is 2 rows
    When I describe "All remittances"
    Then the draft has a preview and Save
    And the draft page says "Export will have 4 rows — it may take a while"

  # E11 — Edge case: a date and an amount → a line over the date
  Scenario: Date and amount
    Given the AI picks "CapitalCall" and answers with columns "Call=name, Due date=due_date, Call amount=call_amount"
    When I describe "Calls by due date"
    Then the draft's chart is "Line — Call amount over Due date"

  # E12 — Edge case: only text columns — no chart suggested, Describe a chart still offered
  Scenario: Nothing to chart
    Given the AI picks "Investor" and answers with columns "Investor=investor_name, Category=category"
    When I describe "Investor names and categories"
    Then the draft page says "No chart suggested"
    And the draft page says "Describe a chart"
