@rack_test @report_builder
Feature: Report Builder assistant — Describe it

  Worked examples: openspec/changes/report-builder-assistant/business-rules.md
  A question becomes a private draft report. The AI (stubbed here) writes a
  report spec; every part is checked with the template rules, and what fails
  is listed under Couldn't do. The draft is refined in words, previewed and
  saved, fine-tuned or discarded.

  Background:
    Given the Acme report builder data
    And Acme has a default AI model
    And I am signed in as Meera

  # H1 — Happy path: New report › Describe it opens the question box with the template questions as examples
  Scenario: Describe page
    Then the New report menu offers Describe it
    When I open Describe it
    Then the Describe page shows the question box and the template questions as examples

  # H2 — Happy path: the draft is explained as cards, with the fund question and the assumption
  Scenario: A draft
    Given the AI drafts the LP owing report
    When I describe "Which LPs still owe money on calls? Biggest first."
    Then the draft page shows the cards "One row per investor | Committed | Called | Collected | Only include investors where Category is LP | Sorted by Unpaid (largest first) | Calculates Unpaid"
    And the draft asks "Which fund?" with the funds "Global Fund, Growth Fund II"
    And the draft lists the assumption "owe money = Called − Collected"
    And the draft has a preview and Save

  # H3 — Happy path: picking the fund limits the commitments, with no AI call
  Scenario: Pick the fund
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    When I pick the fund "Growth Fund II" for the draft
    Then no AI call was made for it
    And the draft page shows the cards "Only capital commitments in Growth Fund II"

  # H4 — Happy path: a refinement sends the current report and the instruction; the fund stays
  Scenario: Refine
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And I pick the fund "Growth Fund II" for the draft
    And the AI then adds Distributed when refined
    When I refine the draft with "also show what was distributed"
    Then the AI was sent the current report and "also show what was distributed"
    And the draft's columns are "Investor, Category, Committed, Called, Collected, Distributed, Unpaid"
    And the draft's "capital_commitments" are limited to "Growth Fund II"

  # H6 — Happy path: Save and open — no longer a draft, the question kept, others see it
  Scenario: Save and open
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And I pick the fund "Growth Fund II" for the draft
    When I save the draft as "LPs owing — GF2"
    Then I land on the report page of "LPs owing — GF2"
    And the report is no longer a draft and its description is "Which LPs still owe money on calls? Biggest first."
    Given Ravi of Acme is signed in
    Then the Reports page lists "LPs owing — GF2"

  # H9 — Happy path: Fine-tune in builder saves and opens the builder
  Scenario: Fine-tune in builder
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    When I fine-tune the draft in the builder
    Then I land on the builder
    And the report is no longer a draft and its description is "Which LPs still owe money on calls? Biggest first."

  # E1 — Edge case: what the AI says it can't do is listed; the rest is drafted
  Scenario: Something not reportable
    Given the AI picks "Fund" and answers with columns "Fund=name, committed_amount"
    And the AI's answer also says it can't do "IRR isn't a reportable column — try DPI"
    When I describe "Show IRR by fund"
    Then Couldn't do lists "IRR isn't a reportable column — try DPI"
    And the draft has a preview and Save

  # E2 — Edge case: a filter value that matches nothing is left out, with the real values
  Scenario: A value that matches nothing
    Given the AI picks "Investor" and answers with columns "Investor=investor_name"
    And the AI's answer filters the rows by "category_eq" = "Partner"
    When I describe "Partners and their names"
    Then Couldn't do lists "No investors have Category Partner — values: Co-Investor, LP"
    And the draft has a preview and Save

  # E3 — Edge case: relative dates become fixed dates, listed as an assumption
  Scenario: Fixed dates
    Given the AI picks "CapitalCommitment" and answers with columns "Folio=folio_id, Committed=committed_amount"
    And the AI's answer filters the rows by "commitment_date_gteq" = "2026-07-01"
    And the AI's answer assumes "last quarter = 1 Jul – 30 Sep 2026"
    When I describe "Commitments made last quarter"
    Then the draft lists the assumption "last quarter = 1 Jul – 30 Sep 2026"
    And the draft has a preview and Save

  # E4 — Edge case: a table that isn't in reports for the account
  Scenario: Data not in reports
    Given the AI picks "SecondarySale" as the table
    When I describe "Show the secondary sales"
    Then Couldn't do lists "secondary sales aren't available in reports for your account"
    And the draft has no preview and no Save

  # E5 — Edge case: a column removed by hand stays removed — the AI gets the report as it is now
  Scenario: Hand edits kept
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And Meera removed "category" from the draft in the builder
    And the AI then adds Distributed when refined
    When I refine the draft with "also show what was distributed"
    Then the report sent to the AI has no "category" column

  # E7 — Edge case: the maker gets "Your draft report is ready", linking to the draft
  Scenario: Ready alert
    Given the draft alerts are recorded
    And the AI drafts the LP owing report
    When I describe "Which LPs still owe money on calls? Biggest first."
    Then the alert "Your draft report is ready" links to the draft

  # E8 — Edge case: Discard deletes the draft
  Scenario: Discard
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    When I discard the draft
    Then the draft is deleted and I am back on Describe

  # E9 — Edge case: a draft is private to its maker
  Scenario: Private drafts
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And Ravi of Acme is signed in
    Then the Reports page hides "Draft — Which LPs still owe money on calls? Bigg"
    When he opens the draft's address
    Then he is refused

  # E10 — Edge case: the daily clean-up deletes drafts unchanged for 7 days, never saved reports
  Scenario: Clean-up
    Given drafts untouched for 8 and 2 days, and a report saved 30 days ago
    When the draft clean-up runs
    Then only the 8-day-old draft is deleted

  # X1 — Error case: the AI fails twice — "Couldn't draft this right now", the question stays
  Scenario: AI times out
    Given the AI fails every time
    When I describe "Which LPs still owe money on calls?"
    Then the draft page says "Couldn't draft this right now — try again in a moment"
    And the question "Which LPs still owe money on calls?" is still on the draft
    And the AI was asked 2 times

  # X2 — Error case: answers that aren't JSON, twice — the same message
  Scenario: Not JSON twice
    Given the AI answers in prose every time
    When I describe "Which LPs still owe money on calls?"
    Then the draft page says "Couldn't draft this right now — try again in a moment"
    And the AI was asked 2 times

  # X3 — Error case: nothing usable — only Couldn't do, no preview, no Save
  Scenario: Nothing usable
    Given the AI picks "Investor" and answers with columns "no_such_column, another_bad_one"
    When I describe "Something odd"
    Then Couldn't do lists "no_such_column isn't a column of investors"
    And the draft has no preview and no Save

  # X4 — Error case: no AI model — say so and offer the templates
  Scenario: No AI model
    Given Acme has no AI model and there is no platform default
    When I open Describe it
    Then the Describe page says "AI drafting isn't set up for your account" and links to the templates

  # X5 — Error case: a filter on another company is left out; the preview is Acme's
  Scenario: Another company's data
    Given the AI picks "Investor" and answers with columns "Investor=investor_name"
    And the AI's answer filters the rows to Beta Partners' company
    When I describe "Show every company's investors"
    Then Couldn't do lists "Filters on the company itself can't be used"
    And the draft preview shows only Acme's investors

  # X6 — Error case: a refinement while still drafting doesn't start a second conversation
  Scenario: Double click
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And the draft is still drafting
    When I refine the draft with "also show what was distributed"
    Then no AI call was made for it

  # X7 — Error case: another company can't open or refine the draft
  Scenario: Another company
    Given the AI drafts the LP owing report
    And I describe "Which LPs still owe money on calls? Biggest first."
    And I am signed in as Omar from another entity
    When he opens the draft's address
    Then he is refused
    When he refines the draft
    Then he is refused
