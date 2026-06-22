@cs_agent
Feature: FM User Chat with Customer Support Agent
  As a fund manager user
  I want to chat with the Customer Support Agent
  So that I can get help with platform features and my data

  Background:
    Given a user exists with role "support"
    And an entity exists with a customer support agent configured
    And a fund manager user exists in that entity
    And the entity has cs_judge_enabled set to true
    And I am logged in as the fund manager user

  Scenario: FM user asks a question covered by user guides
    When I send the message "How do I create a capital call?"
    Then the agent should call the SearchUserGuidesTool
    And the response should reference the capital calls user guide

  Scenario: FM user asks a data-specific question
    When I send the message "How many funds do I have?"
    Then the agent should call the FmRunQueryTool
    And the response should include data from the entity's funds

  Scenario: FM user rates a response positively
    Given I have received an assistant response
    When I click the thumbs up button on the response
    Then the feedback should be recorded as "positive"
    And the feedback should be linked to the assistant message

  Scenario: FM user rates a response negatively
    Given I have received an assistant response
    When I click the thumbs down button on the response
    Then the feedback should be recorded as "negative"
    And the feedback should appear in the CS support team's feedback queue

  Scenario: FM user adds a note with negative feedback
    Given I have received an assistant response
    When I click the thumbs down button on the response
    And I add the note "The steps are wrong, there is no such menu"
    Then the feedback should be recorded with the note

  Scenario: ResponseJudgeJob runs after assistant response
    When I send the message "How do I create a capital call?"
    And the assistant responds
    Then the ResponseJudgeJob should be enqueued
    And the job should score the response on completeness, grounding, and actionability

  Scenario: Chat session expires after 30 minutes of inactivity
    Given I have an existing chat session with messages older than 30 minutes
    When I send a new message
    Then a new chat session should be created
    And the previous session should remain intact

  Scenario: Chat resumes within the same session
    Given I have an existing chat session with a recent message
    When I send a new message
    Then the message should be added to the existing session
    And the agent should have access to the conversation history

  Scenario: FM user can view past chat sessions
    Given I have multiple chat sessions with the CS agent
    When I view the sessions list
    Then I should see all my sessions ordered by most recent
    And each session should show a preview of the first message

  Scenario: FM user can delete a chat session
    Given I have an existing chat session
    When I delete the session
    Then the session should be removed
    And it should no longer appear in the sessions list
