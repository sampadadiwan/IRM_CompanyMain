Feature: SupportClientMapping Policy
  As a system enforcing authorization
  I want to check the policy rules for support client mappings
  So that only correct users can perform actions

  Background:
    Given a user exists
    And an entity exists
    And a support client mapping exists linking the user to the entity

  Scenario: Switch allowed
    Given the mapping is enabled
    And the mapping status is "Reverted"
    And the entity has enable_support set to true
    When I check the policy for switch
    Then it should permit

  Scenario: Switch denied when already switched
    Given the mapping is enabled
    And the mapping status is "Switched"
    When I check the policy for switch
    Then it should deny

  Scenario: Revert allowed when switched
    Given the mapping status is "Switched"
    When I check the policy for revert
    Then it should permit

  Scenario: Revert denied when not switched
    Given the mapping status is "Reverted"
    When I check the policy for revert
    Then it should deny

  Scenario: Scope for super user
    Given the user is a super user
    When I resolve the policy scope
    Then it should return all mappings

  Scenario: Scope for normal user
    Given the user is not a super user
    When I resolve the policy scope
    Then it should return only the mappings for that user