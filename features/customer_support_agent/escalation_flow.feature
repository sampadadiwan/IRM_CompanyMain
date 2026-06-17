Feature: Customer Support Escalation Flow
  As a fund manager or support team member
  I want conversations to be escalated to human support when needed
  So that complex issues are handled by the right people

  Background:
    Given a user exists with role "support"
    And an entity exists with a customer support agent configured
    And a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    And a fund manager user exists in that entity

  Scenario: Agent escalates when user explicitly requests it
    Given I am logged in as the fund manager user
    And I have an active chat session
    When I send the message "I need to speak to a human"
    Then the agent should call the EscalateToHumanTool
    And a CustomerSupportEscalation should be created with reason "customer_requested"
    And the chat session status should change to "escalated"
    And I should see a message that my conversation has been escalated

  Scenario: Agent auto-escalates after exceeding tool call limit
    Given I am logged in as the fund manager user
    And I have an active chat session
    When the agent exceeds the maximum tool iterations of 6
    Then a CustomerSupportEscalation should be created with reason "max_iterations"
    And the chat session status should change to "escalated"
    And I should see a message about being connected to the support team

  Scenario: Auto-escalate only fires for CustomerSupportAgent
    Given a different support agent exists with agent_type "PortfolioAssistant"
    And I am logged in as the fund manager user
    When the agent exceeds the maximum tool iterations
    Then no CustomerSupportEscalation should be created
    And I should see a generic error message

  Scenario: Escalation email sent to mapped support users
    Given I am logged in as the fund manager user
    And I have an active chat session
    When a conversation is escalated
    Then an escalation email should be sent
    And the email should be sent to the support user mapped to the entity
    And the email subject should include the entity name and escalation reason

  Scenario: Escalation email falls back to global support when no mappings exist
    Given no support client mappings exist for the entity
    And I am logged in as the fund manager user
    And I have an active chat session
    When a conversation is escalated
    Then an escalation email should be sent to the global support email address

  Scenario: Escalation email sent to multiple mapped support users
    Given a second support user exists
    And a support client mapping exists linking the second support user to the entity
    And I am logged in as the fund manager user
    And I have an active chat session
    When a conversation is escalated
    Then the escalation email should be sent to both mapped support users

  Scenario: Escalation email includes recent conversation history
    Given I am logged in as the fund manager user
    And I have a chat session with 5 messages
    When a conversation is escalated
    Then the escalation email should include the last 10 messages from the session

  Scenario: Escalated session blocks new messages
    Given I am logged in as the fund manager user
    And my chat session has been escalated
    When I try to send a new message
    Then I should see a message that the conversation is being reviewed
    And no new assistant response should be generated

  Scenario: Support user views escalation in the dashboard
    Given I am logged in as the support user
    And an escalation exists for my mapped entity
    When I view the escalations tab on the CS Reviews dashboard
    Then I should see the escalation with its reason and summary
    And I should see the analyst name and entity name
    And I should see when the escalation was created

  Scenario: Escalation records the correct entity
    Given I am logged in as the fund manager user
    And I have an active chat session
    When a conversation is escalated
    Then the escalation entity_id should match the support agent's entity
    And the escalation user_id should match the FM user
