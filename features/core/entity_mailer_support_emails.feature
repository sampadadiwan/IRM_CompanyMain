@notification @rack_test
Feature: Entity Mailer Support Emails
  In order to ensure support emails go to the right people
  As a system
  I want to route EntityMailer notifications based on SupportClientMapping

  Background:
    Given the default support email is "support@example.com"
    And there is a user "first_name=Support;last_name=User;email=support1@mapping.com" for an entity "name=MappingEntity;entity_type=Company"
    And there is a user "first_name=Other;last_name=User;email=other@mapping.com" for an entity "name=OtherEntity;entity_type=Company"

  Scenario: Route notify_info to default support email when no entity_id is provided
    When I trigger "notify_info" with "msg=test:message;subject=INFO"
    Then an email should be sent to "support@example.com" with subject containing "INFO"

  Scenario: Route notify_info to default support email when entity has no mappings
    When I trigger "notify_info" with "msg=test:message;entity_id=OtherEntity;subject=INFO"
    Then an email should be sent to "support@example.com" with subject containing "INFO"

  Scenario: Route notify_info to mapped user when entity has enabled mapping
    Given a support mapping exists for entity "MappingEntity" and user "support1@mapping.com"
    When I trigger "notify_info" with "msg=test:message;entity_id=MappingEntity;subject=INFO"
    Then an email should be sent to "support1@mapping.com" with subject containing "INFO"
    And an email should not be sent to "support@example.com"

  Scenario: Route notify_errors to default support email when no entity_id is provided
    When I trigger "notify_errors" with "error_msg=error:something_went_wrong"
    Then an email should be sent to "support@example.com" with subject containing "Errors"

  Scenario: Route notify_errors to mapped user when entity has enabled mapping
    Given a support mapping exists for entity "MappingEntity" and user "support1@mapping.com"
    When I trigger "notify_errors" with "error_msg=error:something_went_wrong;entity_id=MappingEntity"
    Then an email should be sent to "support1@mapping.com" with subject containing "Errors"
    And an email should not be sent to "support@example.com"
