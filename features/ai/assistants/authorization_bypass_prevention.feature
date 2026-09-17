Feature: Cross-tenant authorization boundaries for AI assistant chats
  As a CapHive customer
  I want the AI assistant chat panel to refuse to open a chat scoped to another tenant's record
  So that no user can enumerate ids to read another firm's fund, portfolio company, or capital
  commitment through the chat sidebar

  Background:
    Given there is a user "first_name=Owner" for an entity "entity_type=Investment Fund;name=Acme Capital;currency=USD"
    And there is another user "first_name=Rival" for another entity "entity_type=Investment Fund;name=Rival Capital;currency=USD"
    And the owner user has the company_admin role

  Scenario: A fund belonging to another tenant cannot be opened as a chat owner
    Given the rival entity has a fund named "Rival Fund I"
    And I am logged in as the owner user
    When I request a Specific Fund Assistant chat owned by the rival fund
    Then no chat should exist owned by the rival fund

  Scenario: A portfolio company belonging to another tenant cannot be opened as a chat owner
    Given the rival entity has a portfolio company named "Rival Portco"
    And I am logged in as the owner user
    When I request a Portfolio Company Assistant chat owned by the rival portfolio company
    Then no chat should exist owned by the rival portfolio company

  Scenario: An owner_type outside the allowlist is rejected outright
    Given I am logged in as the owner user
    When I request an assistant chat with owner_type "User" and the rival user's id
    Then no chat should exist owned by the rival user
