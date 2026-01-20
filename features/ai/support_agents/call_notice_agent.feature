Feature: Call Notice Agent
  As a fund administrator
  I want to validate capital call readiness before sending notices
  So that I can ensure all prerequisites are met

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is a fund with call templates configured
    And there is an existing investor "investor_name=Test Investor"
    And there is an investor_kyc for the investor
    And there is a capital commitment for the investor
    And there is a capital call for the fund

  Scenario: All validations pass - capital call is ready to send
    Given all investors have verified KYC
    And all remittances have generated documents
    And all documents are approved
    And email notification template is configured
    When I run the call notice agent
    Then the agent should complete successfully
    And the final status should be "ready"
    And all steps should have status "success"

  Scenario: KYC verification fails - blocks pipeline
    Given an investor has unverified KYC
    When I run the call notice agent
    Then the agent should stop at step "verify_investor_kyc"
    And the final status should be "blocked"
    And the step "verify_investor_kyc" should have failed records

  Scenario: Missing call notice documents - blocks pipeline
    Given all investors have verified KYC
    And remittances are missing call notice documents
    When I run the call notice agent
    Then the agent should stop at step "check_documents_generated"
    And the final status should be "blocked"

  Scenario: No call templates configured for fund - blocks pipeline
    Given all investors have verified KYC
    And the fund has no call templates
    When I run the call notice agent
    Then the agent should stop at step "check_documents_generated"
    And the step message should contain "No call templates found"

  Scenario: Unapproved documents - blocks pipeline
    Given all investors have verified KYC
    And all remittances have generated documents
    And some documents are not approved
    When I run the call notice agent
    Then the agent should stop at step "check_documents_approved"
    And the final status should be "blocked"

  Scenario: Missing email notification template - blocks pipeline
    Given all investors have verified KYC
    And all remittances have generated documents
    And all documents are approved
    And no email notification template is configured
    When I run the call notice agent
    Then the agent should stop at step "check_notification_configured"
    And the step message should contain "No email notification template configured"


