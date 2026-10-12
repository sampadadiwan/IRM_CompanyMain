Feature: Entity Deactivation
  As CapHive support
  I want to deactivate an off-boarded client entity from the entity page
  So that its employees can no longer log in and its investors lose portal access

  Background:
    Given there is a user "first_name=Client;last_name=Admin" for an entity "name=Acme Fund;entity_type=Investment Fund"
    And the entity has an active employee "staff@acme.com"
    And the entity has an approved investor access for "lp@acme.com"

  @rack_test
  Scenario: Support sees the deactivate button and the popup explaining every effect
    Given Im logged in as a user "first_name=Support" for an entity "name=CapHive Ops;entity_type=Company"
    And the user has role "support"
    And I am at the entity page for "Acme Fund"
    Then I should see "Deactivate"
    When I click on "Deactivate"
    Then I should see "approved investor access(es) revoked"
    And I should see "active employee login(s) disabled"
    And I should see "No data is deleted"
    And I should see "Re-activating does not restore access"

  @rack_test
  Scenario: Deactivating an entity revokes employee logins and investor access
    Given Im logged in as a user "first_name=Support" for an entity "name=CapHive Ops;entity_type=Company"
    And the user has role "support"
    And I am at the entity page for "Acme Fund"
    When I click on "Deactivate"
    And I confirm the entity deactivation
    Then I should see "has been deactivated"
    And the entity "Acme Fund" should be deactivated
    And the investor access for "lp@acme.com" should not be approved
    And the employee "staff@acme.com" should be inactive

  @rack_test
  Scenario: Deactivating from outside the UI still revokes investor access
    When the entity "Acme Fund" is deactivated directly
    Then the investor access for "lp@acme.com" should not be approved
    And the employee "staff@acme.com" should be inactive

  @rack_test
  Scenario: The cascade runs inside a Chewy index strategy when executed by a worker
    When the deactivation job for "Acme Fund" runs the way Sidekiq runs it
    Then the investor access for "lp@acme.com" should not be approved
    And the employee "staff@acme.com" should be inactive

  @rack_test
  Scenario: Re-activating the entity does not restore access
    When the entity "Acme Fund" is deactivated directly
    And the entity "Acme Fund" is activated directly
    Then the investor access for "lp@acme.com" should not be approved
    And the employee "staff@acme.com" should be inactive

  Scenario: A company admin of the entity cannot deactivate it
    Given the user has role "company_admin"
    And the user is logged in
    And I am at the entity page for "Acme Fund"
    Then I should not see "Deactivate"
