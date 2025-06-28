Feature: View Shared Document
  As a recipient of a shared document link
  I want to view the document
  So that I can access the shared content

  Background:
    Given there is a user "" for an entity "name=Test Entity"
    And the email queue is cleared

  Scenario: Successfully viewing a document with a valid share link
    Given a document named "My Shared Document" exists for "Test Entity"
    And a doc share exists for "My Shared Document" with email "test@example.com" and email sent is true
    And the doc share has a token "valid_token"
    When I visit the view link for the doc share with token "valid_token"
    Then I should be able to view the document "My Shared Document"
    And the doc share's view count should be 1
    And the doc share's viewed at should be present

  Scenario: Attempting to view a document with an invalid token
    Given a document named "Another Document" exists for "Test Entity"
    And a doc share exists for "Another Document" with email "test@example.com" and email sent is true
    When I visit the view link for the doc share with token "invalid_token"
    Then I should see a "Not Found" page with status 404

  Scenario: Attempting to view a document when doc share record is not found
    Given a document named "Missing DocShare Document" exists for "Test Entity"
    When I visit the view link for the doc share with token "non_existent_doc_share_token"
    Then I should see a "Not Found" page with status 404

  
  Scenario: Policy denies access to the document
    Given a document named "Policy Denied Document" exists for "Test Entity"
    And a doc share exists for "Policy Denied Document" with email "test@example.com" and email sent is false
    And the doc share has a token "valid_token"
    When I visit the view link for the doc share with token "invalid_token"
    Then I should see a "Not Found" page with status 404

  Scenario: Successfully sending a document share email
    Given a document named "Email Test Document" exists for "Test Entity"
    And a doc share exists for "Email Test Document" with email "recipient@example.com"
    Then the doc share email address receives an email with "Email Test Document" in the subject
    And the email body should contain "A document Email Test Document has been shared with you"
    And when I click on the link in the email "View Document"
    Then I should be able to view the document "Email Test Document"
    And the doc share's view count should be 1
    And the doc share's viewed at should be present