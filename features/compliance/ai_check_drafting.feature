Feature: Describe a check in words (AI drafting)
  A compliance editor types a rule as a sentence; the AI drafts the check's structured fields, which the
  editor reviews in plain words, edits, test-runs on a fund and saves. AI never runs at check time.
  The AI is stubbed at LlmService.
  Worked examples: openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md (group 8)

  Background:
    Given the Horizon compliance setup
    And Describe in words is on for Horizon
    And Meera has a draft v2 of the fund agreement pack

  # H37 — Happy path: "No more than 15% … LPA clause 8.2" drafts figure per sector ÷ investable ≤ 15%, source "LPA cl. 8.2"
  @rack_test
  Scenario: H37 Draft from sentence
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "citation": "LPA cl. 8.2",
       "figure": {"measure": "cost_per_sector"}, "divided_by": {"measure": "investable_funds"},
       "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector — LPA clause 8.2"
    Then the draft kind reads "Limit check"
    And the draft figure reads "largest investment cost per sector"
    And the draft divided_by reads "investable funds"
    And the draft limit reads "≤ 15%"
    And the draft citation reads "LPA cl. 8.2"

  # H38 — Happy path: a draft test-run at 34.00 ÷ 270.00 = 12.59% passes; Save records "Drafted with AI from: '…' · confirmed by Meera"
  @rack_test
  Scenario: H38 Save with provenance
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "citation": "LPA cl. 8.2",
       "figure": {"measure": "cost_per_sector"}, "divided_by": {"measure": "investable_funds"},
       "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector — LPA clause 8.2"
    And I test-run the draft check on "Horizon Growth Fund I"
    Then the draft test run shows "Pass"
    And the draft test run shows "₹34.00 cr"
    And the draft test run shows "₹270.00 cr"
    And the draft test run shows "12.59%"
    When I save the draft check
    Then the version shows "Drafted with AI from: 'No more than 15% of investable funds in any one sector — LPA clause 8.2' · confirmed by Meera"
    And the fund agreement draft has 4 checks and 1 duties

  # H39 — Happy path: "Key-person event … within 30 days" becomes an on-demand duty with evidence, reason shown
  @rack_test
  Scenario: H39 Rule becomes duty
    Given the compliance AI replies with:
      """
      {"kind": "duty", "name": "Key-person event notified", "duty_trigger": "on_demand", "evidence": true,
       "reason": "CapHive does not record key-person events"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "Key-person event must be notified to LPs within 30 days"
    Then the draft kind reads "Manual duty"
    And the draft when reads "On demand"
    And the draft evidence reads "Required"
    And the draft reason reads "CapHive does not record key-person events"
    When I test-run the draft check on "Horizon Growth Fund I"
    And I save the draft check
    Then the version shows "CapHive does not record key-person events"
    And the saved duty "Key-person event notified" needs evidence on demand

  # E57 — Edge case: "No single LP above 20% of the fund" names its assumption "Assumed: commitments", shown as an editable line
  @rack_test
  Scenario: E57 Assumption named
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single LP limit (AI)",
       "figure": {"op": "sum", "source": "commitments", "field": "amount", "group_by": "investor"},
       "divided_by": {"measure": "corpus"}, "compare": "lte", "limit_value": 20, "limit_unit": "pct",
       "assumptions": [{"part": "divided_by", "text": "commitments"}]}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No single LP above 20% of the fund"
    Then the draft divided_by reads "Assumed: commitments"
    And the draft divided_by reads "corpus"
    And the draft figure reads "largest total amount of commitments per investor"

  # E58 — Edge case: the draft divides by paid-in; Meera switches it to commitments, re-runs and saves — saved with commitments
  @rack_test
  Scenario: E58 Misread basis fixed
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single LP limit (AI)",
       "figure": {"op": "sum", "source": "commitments", "field": "amount", "group_by": "investor"},
       "divided_by": {"op": "sum", "source": "payments", "field": "amount"}, "compare": "lte", "limit_value": 20, "limit_unit": "pct",
       "assumptions": [{"part": "divided_by", "text": "paid-in"}]}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No single LP above 20% of the fund"
    Then the draft divided_by reads "Assumed: paid-in"
    When I change the draft "Divided by: records" to "Commitments"
    Then the draft divided_by reads "total amount of commitments"
    And the draft shows "Draft updated — run the test again"
    When I test-run the draft check on "Horizon Growth Fund I"
    And I save the draft check
    Then the saved check "Single LP limit (AI)" divides by "amount" of "commitments"

  # E59 — Edge case: an untested draft cannot be saved
  @rack_test
  Scenario: E59 Save disabled
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "figure": {"measure": "cost_per_sector"},
       "divided_by": {"measure": "investable_funds"}, "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector"
    Then Save check is disabled
    And the draft shows "Save is available after a test run."

  # E60 — Edge case: editing the limit of a tested draft clears the test run and disables Save
  @rack_test
  Scenario: E60 Edit clears run
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "figure": {"measure": "cost_per_sector"},
       "divided_by": {"measure": "investable_funds"}, "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector"
    And I test-run the draft check on "Horizon Growth Fund I"
    Then Save check is enabled
    When I change the draft "Limit" to "12"
    Then the draft has no test run
    And Save check is disabled
    And the draft limit reads "≤ 12%"

  # E61 — Edge case: cancelling a draft saves nothing
  @rack_test
  Scenario: E61 Cancel
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "figure": {"measure": "cost_per_sector"},
       "divided_by": {"measure": "investable_funds"}, "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector"
    And I test-run the draft check on "Horizon Growth Fund I"
    And I cancel the draft check
    Then the fund agreement draft is unchanged

  # E62 — Edge case: a sentence of exactly 1,000 characters is accepted
  @rack_test
  Scenario: E62 1,000 characters
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "figure": {"measure": "cost_per_sector"},
       "divided_by": {"measure": "investable_funds"}, "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe a check of exactly 1000 characters
    Then a draft check was created
    And the draft kind reads "Limit check"

  # E63 — Edge case: an AI-drafted check runs twice on the same data with no AI call and identical results
  Scenario: E63 Deterministic runs
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "Single-sector limit (AI)", "citation": "LPA cl. 8.2", "figure": {"measure": "cost_per_sector"},
       "divided_by": {"measure": "investable_funds"}, "compare": "lte", "limit_value": 15, "limit_unit": "pct"}
      """
    And "Horizon Growth Fund I" also carries the fund agreement pack
    And the AI-drafted check "Single-sector limit (AI)" is saved and published in the fund agreement pack
    When the nightly compliance runs happen on "2026-12-02" and "2026-12-03" with the AI watched
    Then the AI was not called and both results of the AI-drafted check are identical

  # X39 — Error case: a sentence of 1,001 characters is refused with "Keep the rule under 1,000 characters"
  @rack_test
  Scenario: X39 1,001 characters
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "x"}
      """
    And I am signed in to compliance as "Meera"
    When I describe a check of exactly 1001 characters
    Then the compliance page shows "Keep the rule under 1,000 characters"
    And no draft check was created

  # X40 — Error case: the AI names "lp_tier" — "Unknown field: lp_tier" is shown and the draft cannot be saved
  @rack_test
  Scenario: X40 Unknown field in draft
    Given the compliance AI replies with:
      """
      {"kind": "limit", "name": "LP tier limit (AI)",
       "figure": {"op": "sum", "source": "commitments", "field": "lp_tier", "group_by": "investor"},
       "divided_by": {"measure": "corpus"}, "compare": "lte", "limit_value": 20, "limit_unit": "pct"}
      """
    And I am signed in to compliance as "Meera"
    When I describe the check "No tier-1 LP above 20% of the fund"
    Then the draft shows "Unknown field: lp_tier"
    And Save check is disabled
    When I test-run the draft check on "Horizon Growth Fund I"
    Then the draft shows "Unknown field: lp_tier"
    And the draft has no test run
    And the fund agreement draft is unchanged

  # X41 — Error case: with the entity's AI-drafting switch off, Describe in words says it is unavailable; the form still works
  @rack_test
  Scenario: X41 AI drafting switched off
    Given Describe in words is off for Horizon
    And I am signed in to compliance as "Meera"
    When I open the fund agreement draft version
    Then the compliance page shows "Describe in words is unavailable — use the form"
    And the "definition" tab of the fund agreement draft shows "Definition (JSON)"
    When I send a draft request for the fund agreement draft
    Then the compliance page shows "Describe in words is unavailable — use the form"
    And no draft check was created

  # X42 — Error case: the AI provider errors or times out — "Drafting failed — try again or use the form", nothing saved
  @rack_test
  Scenario Outline: X42 AI errors or times out
    Given the compliance AI fails with "<failure>"
    And I am signed in to compliance as "Meera"
    When I describe the check "No more than 15% of investable funds in any one sector"
    Then the compliance page shows "Drafting failed — try again or use the form"
    And the fund agreement draft is unchanged

    Examples:
      | failure         |
      | a provider error |
      | a timeout       |
