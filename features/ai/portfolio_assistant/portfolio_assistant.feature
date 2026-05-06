Feature: Portfolio Assistant chat provider routing
  As an FM analyst chatting via the support_agents bubble
  I want the adapter to wrap the right BaseAssistant subclass
  So that single-company chats are scoped and cross-portfolio chats span all my companies

  Background:
    Given there is a user "first_name=FM-Analyst" for an entity "entity_type=Investment Fund;name=Acme FM"
    And there is a portfolio company "name=AX" for the entity
    And a SupportAgent of type "PortfolioAssistantAgent" exists for the entity

  Scenario: Resolver picks the adapter for PortfolioAssistantAgent
    When the chat provider is resolved with target nil
    Then the provider class should be "PortfolioAssistantChatProvider"

  Scenario: Single-company mode wraps PortfolioCompanyAssistant
    When the chat provider is resolved with target the portfolio company "AX"
    Then the wrapped assistant class should be "PortfolioCompanyAssistant"
    And the provider mode should be "single"

  Scenario: Cross-portfolio mode wraps PortfolioAssistant
    When the chat provider is resolved with target the FM entity
    Then the wrapped assistant class should be "PortfolioAssistant"
    And the provider mode should be "cross"

  Scenario: Provider delegates tools to the wrapped assistant
    When the chat provider is resolved with target the portfolio company "AX"
    Then the provider's tools count should match the wrapped assistant's tools count
    And every provider tool should have a non-empty description

  Scenario: Provider delegates system prompt to the wrapped assistant
    When the chat provider is resolved with target the portfolio company "AX"
    Then the provider's system prompt should equal the wrapped assistant's system prompt
