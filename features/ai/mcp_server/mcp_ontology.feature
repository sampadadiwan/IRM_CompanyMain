Feature: MCP tool surfaces are generated from the ontology and match their models
  As an external AI client querying CapHive over MCP
  I want the tools' advertised attributes to match what the models actually support
  So that a guessed attribute fails loudly instead of silently returning unfiltered data

  # Ransack's ignore_unknown_conditions defaults to true and this app never overrides it, so
  # a condition on an attribute a model does not expose is DROPPED, not rejected: the tool
  # returned every row the user could see and the AI client presented that as a filtered
  # answer. The hand-written descriptions had several of these -- `status` and `verified` on
  # capital calls, `rule_for` on account entries, `text` on documents, `startup`/`proforma`
  # on portfolio investments -- plus sort keys Ransack ignores (`call_amount_cents desc`).
  # Both the descriptions and the validation now come from
  # app/packs/ai/mcp_server/ontology/*.yml.

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role

  Scenario: An attribute the model does not have is rejected, not silently ignored
    Given there is a capital call for the entity
    When I call the list_capital_calls MCP tool with query '{"status_eq": "active"}'
    Then the MCP response should be an error mentioning "approved"
    And the MCP response should not include the capital call

  Scenario: A physical column name is rejected with the queryable attribute to use instead
    Given there is a capital call for the entity
    When I call the list_capital_calls MCP tool with query '{"call_amount_cents_gt": 100}'
    Then the MCP response should be an error mentioning "call_amount"
    And the MCP response should not include the capital call

  Scenario: A predicate the field does not support is rejected
    When I call the list_capital_calls MCP tool with query '{"due_date_matches": "2024%"}'
    Then the MCP response should be an error mentioning "not an allowed predicate"

  Scenario: A sort key Ransack would ignore is rejected instead of silently unsorted
    When I call the list_capital_calls MCP tool with sort "call_amount_cents desc"
    Then the MCP response should be an error mentioning "not a sortable field"

  Scenario: A valid query still returns rows
    Given there is a capital call for the entity
    When I call the list_capital_calls MCP tool with query '{"due_date_lteq": "2099-12-31"}'
    Then the MCP response should not be an error
    And the MCP response should include the capital call

  Scenario: The generated description does not advertise attributes that do not exist
    Then the list_capital_calls tool description should not offer "status" as a filter
    And the list_capital_calls tool description should not offer "verified" as a filter

  # The drift guards. These execute what every ontology advertises against the real models,
  # so a YAML that gets ahead of the schema fails here rather than in front of a client.
  Scenario: Every filter the ontology advertises actually filters
    Then every filter the ontology advertises works against its model

  Scenario: Every sort key the ontology advertises actually sorts
    Then every sort option the ontology advertises is honoured by Ransack

  Scenario: Every aggregate and group_by field resolves to a real column
    Then every aggregate and group_by field the ontology advertises resolves to a column

  Scenario: Every scope the ontology describes is declared on its query object
    Then every scope the ontology describes is declared on its query object

  Scenario: Descriptions only cross-reference tools that exist
    Then every tool name referenced in a description exists
