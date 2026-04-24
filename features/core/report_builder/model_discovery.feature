Feature: ReportBuilderModelDiscovery — finding eligible root models and associations

  Scenario: roots returns only whitelisted models that have entity_id
    When I request the list of report builder root models
    Then the roots list should include "Investor"
    And every root should be in the ROOT_MODELS whitelist
    And every root should have an entity_id column

  Scenario: Investor associations are discoverable
    When I request associations for "Investor"
    Then the associations list should not be empty
    And each association should have keys "name, model, macro, label"

  Scenario: reset_cache! forces re-discovery on the next call
    When I request the list of report builder root models
    Then reset_cache! should clear the memoized roots
