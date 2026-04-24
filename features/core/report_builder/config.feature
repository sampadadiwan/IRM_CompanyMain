Feature: ReportBuilderConfig — template parsing and validation

  Scenarios exercise the Config value object in isolation (no DB needed).

  Scenario: Valid root model produces a valid config
    Given a report builder config with root model "Investor"
    When I check if the config is valid
    Then the config should be valid
    And the root class should be "Investor"

  Scenario: Unknown root model makes the config invalid
    Given a report builder config with root model "NonExistentModelXYZ"
    When I check if the config is valid
    Then the config should not be valid

  Scenario: Blank root model makes the config invalid
    Given a report builder config with root model ""
    When I check if the config is valid
    Then the config should not be valid

  Scenario: Config parses joins from template JSON
    Given a report builder config with template:
      """
      {
        "root_model": "Investor",
        "joins": [
          { "relation": "capital_commitments", "model": "CapitalCommitment" },
          { "relation": "investor_kycs",        "model": "InvestorKyc" }
        ],
        "aggregates": {},
        "root_filters": {},
        "sort": {}
      }
      """
    Then the config should have 2 joins
    And join_for "capital_commitments" should not be nil
    And join_for "investor_kycs" should not be nil

  Scenario: aggregate_for resolves with and without col-type suffix
    Given a report builder config with template:
      """
      {
        "root_model": "Investor",
        "joins": [],
        "aggregates": {
          "capital_commitments.folio_committed_amount": "sum"
        },
        "root_filters": {},
        "sort": {}
      }
      """
    Then the aggregate for "capital_commitments.folio_committed_amount" should be "sum"
    And the aggregate for "capital_commitments.folio_committed_amount; num-col" should be "sum"
    And the aggregate for "capital_commitments.other_column" should be nil

  Scenario: Config handles empty/nil template gracefully
    Given a report builder config with template:
      """
      {}
      """
    When I check if the config is valid
    Then the config should not be valid
    And the config should have 0 joins
