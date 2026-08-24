Feature: FundAssistant data manager authorization fix
  As a fund manager chatting with the Fund Assistant
  I want the assistant's list tools to never let a scope parameter execute a destructive method
  So that a hallucinated or prompt-injected scope value cannot delete fund data

  # Regression test for the scope-based authorization bypass: `scope` used to be applied via
  # `relation.send(scope) if relation.respond_to?(scope)`, and every ActiveRecord relation
  # responds_to? destroy_all/delete_all/update_all, so a hallucinated or prompt-injected scope
  # value could delete every capital call the current user's Pundit scope covers. CapitalCall
  # has no named scopes, so the fix removes the unsafe line outright instead of allowlisting one.
  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM;currency=INR"
    And the user has the company_admin role

  Scenario: An LLM-supplied scope cannot delete capital calls
    Given there is a capital call for the entity
    When I call list_capital_calls with scope "destroy_all"
    Then the capital call should still exist
