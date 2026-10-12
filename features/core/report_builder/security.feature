@rack_test
Feature: Report Builder security — injection prevention and allow-listing

  Background:
    Given a report builder entity and user
    And I am signed in as the report builder user

  # ── associations endpoint ─────────────────────────────────────────────────

  Scenario: associations endpoint rejects an arbitrary class name
    When I request the associations endpoint for "Kernel"
    Then the API response should be 422

  Scenario: associations endpoint rejects a non-existent model name
    When I request the associations endpoint for "CompletelyFakeModel123"
    Then the API response should be 422

  Scenario: associations endpoint accepts a known app model
    When I request the associations endpoint for "Investor"
    Then the report builder API response should be successful

  # ── Formula allow-listing ─────────────────────────────────────────────────

  Scenario: validate_formula rejects a column key not in the report's GVPs
    When I create a new report for root model "Investor"
    And the report has selected column "investor_name"
    And I validate the formula "[entity.api_secret] + 1" via the API
    Then the formula validation API response should indicate failure
    And the formula validation error should mention "entity.api_secret"

  Scenario: validate_formula accepts a formula using a column that is in the report's GVPs
    When I create a new report for root model "Investor"
    And I add the column "capital_commitments.folio_committed_amount" to the report
    And I add the join "capital_commitments" with model "CapitalCommitment" to the report
    And I validate the formula "[capital_commitments.folio_committed_amount] * 2" via the API
    Then the formula validation API response should indicate success

  Scenario: add_formula rejects an expression referencing columns outside the report's GVPs
    When I create a new report for root model "Investor"
    And the report has selected column "investor_name"
    And I add the formula with expression "[investor_name] + [hidden_column]" and label "Bad Formula"
    Then the API response should be 302

  # ── Entity scoping ────────────────────────────────────────────────────────

  Scenario: A user cannot view a report belonging to a different entity
    Given a report builder entity and user
    And a report builder report exists for the entity
    And I am signed in as the report builder user
    When I request the associations endpoint for "Investor"
    Then the report builder API response should be successful
