Feature: CS Feedback Review Actions
  As a support team member
  I want to review, re-test, and resolve flagged agent responses
  So that I can improve the quality of the Customer Support Agent

  Background:
    Given a user exists with role "support"
    And an entity exists with a customer support agent configured
    And a support client mapping exists linking the support user to the entity
    And the mapping is enabled
    And a fund manager user exists in that entity
    And the FM user has a chat session with a negative-rated feedback item
    And I am logged in as the support user

  Scenario: Support user views feedback detail page
    When I click on a feedback item in the queue
    Then I should see the feedback detail page
    And I should see the original user question
    And I should see the agent response rendered as markdown
    And I should see the feedback status
    And I should see the user rating

  Scenario: Support user sees judge scores on feedback detail
    Given the feedback item has been judged
    When I click on a feedback item in the queue
    Then I should see the completeness score out of 3
    And I should see the grounding score out of 3
    And I should see the actionability score out of 3
    And I should see the total score out of 9
    And I should see the list of issues flagged by the judge

  Scenario: Support user sees tool calls summary
    Given the agent used SearchUserGuidesTool to answer the question
    When I click on a feedback item in the queue
    Then the feedback detail page should show the tool calls summary
    And I should see which tools were called

  Scenario: Support user sees guide files searched
    Given the agent searched user guide files
    When I click on a feedback item in the queue
    Then the feedback detail page should show which guide files were searched
    And I should see whether a guide match was found

 