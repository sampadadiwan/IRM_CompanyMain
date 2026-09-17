Feature: PortfolioAssistant data manager correctness fixes
  As a portfolio manager chatting with the Portfolio Assistant
  I want cross-portfolio queries and single-company summaries to be correct and not crash
  So that I can trust the numbers, charts, and reports the assistant gives me

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And there is a portfolio company "name=AX" for the entity
    And the portfolio assistant data manager is initialized for the user

  # Regression test for: plot_chart_from_query(resource: "valuations"/"portfolio_investments"/
  # "documents") used to raise ArgumentError because these data manager methods required
  # portfolio_company_id, but the generic chart-from-query path never passes one.
  Scenario: Listing valuations across the whole portfolio without a company id does not crash
    Given the portfolio company has a valuation of 500000 cents per share
    When I list valuations with no portfolio_company_id
    Then the valuations should include the portfolio company's valuation

  Scenario: Listing portfolio investments across the whole portfolio without a company id does not crash
    Given the portfolio company has a portfolio investment
    When I list portfolio investments with no portfolio_company_id
    Then the portfolio investments should include the portfolio company's investment

  Scenario: Listing documents across the whole portfolio without a company id does not crash
    Given the portfolio company has a document named "Board Deck"
    When I list documents with no portfolio_company_id
    Then the documents should include "Board Deck"

  Scenario: A KPI with no prior period shows a blank percentage_change instead of a bare "%"
    Given the portfolio company has a KPI "Revenue" with no percentage change
    When I list portfolio KPIs for the portfolio company
    Then the "Revenue" KPI's percentage_change should be blank

  Scenario: A company snapshot reports mixed currencies as a breakdown, not one misleading total
    Given the portfolio company has a portfolio investment of 1000000 cents in "USD"
    And the portfolio company has a portfolio investment of 500000 cents in "INR"
    When I get the portfolio company snapshot
    Then the snapshot's current_fmv should report a per-currency breakdown across the investments

  Scenario: Unbounded relations are capped server-side by default
    When I bound a query relation with no explicit limit
    Then the resulting SQL should apply the default query limit of 500

  Scenario: An explicit limit still overrides the default cap
    When I bound a query relation with an explicit limit of 3
    Then the resulting SQL should apply a limit of 3

  Scenario: PortfolioAssistant has a non-empty scheduled report query list
    When I ask PortfolioAssistant for its default report queries
    Then it should return more than one query

  # Regression tests for the scope-based authorization bypass: `scope` used to be applied
  # via `relation.send(scope) if relation.respond_to?(scope)`, and every ActiveRecord
  # relation responds_to? destroy_all/delete_all/update_all, so a hallucinated or
  # prompt-injected scope value could delete every row the current user's Pundit scope
  # covers. It is now routed through a HasScope-declared allowlist instead.
  Scenario: An LLM-supplied scope cannot delete portfolio companies
    When I call list_portfolio_companies with scope "destroy_all"
    Then the portfolio company "AX" should still exist

  Scenario: An LLM-supplied scope cannot delete documents
    Given the portfolio company has a document named "Board Deck"
    When I call list_documents with scope "destroy_all"
    Then the document "Board Deck" should still exist
