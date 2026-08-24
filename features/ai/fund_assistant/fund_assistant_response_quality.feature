Feature: FundAssistant data manager response-quality fixes
  As a fund manager chatting with the Fund Assistant
  I want unbounded requests capped and invalid scope names reported back to me
  So that I never silently get a truncated/timed-out answer or a quietly-unfiltered one

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role

  # Regression test for: every list_* method here previously only applied `limit` when the
  # caller supplied one, so an unfiltered "list all capital calls" on a large fund could pull
  # thousands of rows into the LLM's context (truncating or timing out the response).
  Scenario: Unbounded relations are capped server-side by default
    When I bound a fund assistant query relation with no explicit limit
    Then the resulting SQL should apply the default query limit of 500

  Scenario: An explicit limit still overrides the default cap
    When I bound a fund assistant query relation with an explicit limit of 3
    Then the resulting SQL should apply a limit of 3

  # Regression test for: an unrecognized/hallucinated `scope` value used to be silently
  # dropped -- the tool call looked successful but quietly returned an unfiltered result,
  # with no signal to the LLM that the requested scope didn't exist.
  Scenario: An unrecognized scope on a fund ratio query is reported back instead of silently ignored
    When I call list_fund_ratios with scope "nonexistent_scope"
    Then I should get an unrecognized scope error naming the valid scopes "latest, default"

  Scenario: A recognized scope on a fund ratio query is applied normally
    Given there is a fund ratio named "TVPI" marked latest for the entity
    When I call list_fund_ratios with scope "latest"
    Then the fund ratio results should include "TVPI"
