Feature: CS Dashboard Access Control
  As a support team member
  I want to access the CS Feedback Reviews dashboard
  So that I can review flagged agent responses for my mapped entities

  Background:
    Given a user exists with role "support"
    And an entity exists with a customer support agent configured
    And a fund manager user exists in that entity
    And a support client mapping exists linking the support user to the entity
    And the mapping is enabled


  Scenario: Support user sees CS Reviews link in sidebar
    Given I am logged in as the support user
    When I view the sidebar navigation
    Then I should see the "CS Reviews" link

  Scenario: Non-support user does not see CS Reviews link
    Given a user exists with role "employee"
    And I am logged in as the employee user
    When I view the sidebar navigation
    Then I should not see the "CS Reviews" link

  Scenario: Support user can access the CS Reviews index page
    Given I am logged in as the support user
    When I navigate to /cs_feedback_reviews
    Then I should see the feedback reviews dashboard
    And I should see the "Feedback Queue" tab
    And I should see the "Escalation Queue" tab

  Scenario: Support user sees only feedback from mapped entities
    Given another entity exists with a customer support agent configured
    And feedback exists for both entities
    And I am logged in as the support user
    When I view the feedback queue
    Then I should only see feedback from my mapped entity
    And I should not see feedback from the unmapped entity

  Scenario: Support user with multiple entity mappings sees all mapped feedback
    Given a second entity exists with a customer support agent configured
    And a support client mapping exists linking the support user to the second entity
    And feedback exists for both entities
    And I am logged in as the support user
    When I view the feedback queue
    Then I should see feedback from both mapped entities

  Scenario: Non-support user is denied access to CS Reviews
    Given a user exists with role "employee"
    And I am logged in as the employee user
    When I navigate to /cs_feedback_reviews
    Then I should be denied access

  Scenario: Support user can filter feedback by status
    Given feedback exists with status "needs_review"
    And feedback exists with status "resolved"
    And I am logged in as the support user
    When I filter the feedback queue by status "needs_review"
    Then I should only see feedback with status "needs_review"

  Scenario: Support user can filter feedback by rating
    Given feedback exists with rating "negative"
    And feedback exists with rating "positive" and judge_total 3
    And I am logged in as the support user
    When I filter the feedback queue by rating "negative"
    Then I should only see feedback with rating "negative"

  Scenario: Support user can filter feedback by entity
    Given a second entity exists with a customer support agent configured
    And a support client mapping exists linking the support user to the second entity
    And feedback exists for both entities
    And I am logged in as the support user
    When I filter the feedback queue by entity
    Then I should only see feedback from the selected entity

  Scenario: Support user can filter feedback by judge score threshold
    Given feedback exists with judge_total 3
    And feedback exists with judge_total 7
    And I am logged in as the support user
    When I filter the feedback queue by judge_max 4
    Then I should only see feedback with judge_total 4 or below

  Scenario: Feedback queue only shows actionable items
    Given feedback exists with rating "positive" and judge_total 8
    And feedback exists with rating "negative"
    And feedback exists with rating "positive" and judge_total 3
    And I am logged in as the support user
    When I view the feedback queue
    Then I should see the negative-rated feedback
    And I should see the low-judge-score feedback
    And I should not see the positive feedback with high judge score

  Scenario: Tab badges show correct counts
    Given 5 actionable feedback items exist for my mapped entities
    And 2 open escalations exist for my mapped entities
    And I am logged in as the support user
    When I view the CS Reviews dashboard
    Then the Feedbacks tab should show a badge with count 5
    And the Escalations tab should show a badge with count 2
