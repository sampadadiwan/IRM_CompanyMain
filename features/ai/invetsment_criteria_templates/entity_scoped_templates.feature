Feature: Entity Scoped Investment Criteria Templates
  As a user
  I want to see templates created by my colleagues
  So that we can share criteria within our firm

  Scenario: User sees the templates from their own entity
    Given I am logged in as a user in entity "Acme Corp"
    And another user in entity "Acme Corp" has created a template "Growth Criteria"
    When I visit the investment criteria templates page
    Then I should see template "Growth Criteria"
