@unit
Feature: Access Rights Cache Logic
  The AccessRightsCache concern should correctly update a user's permissions hash
  whenever AccessRight or InvestorAccess records are created, updated, or deleted.

  Background:
    Given there is an entity "name=Fund Entity"
    And there is a fund "name=Main Fund" for the entity "name=Fund Entity"
    And there is an entity "name=Investor Firm"
    And there is an investor "investor_name=Big LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"

  Scenario: Granting AccessRight to an existing approved InvestorAccess user
    Given there is a user "email=lp_user@example.com" for the entity "name=Investor Firm"
    And there is an approved investor access for "lp_user@example.com" and investor "Big LP"
    When I grant "read" access to the fund for investor "Big LP"
    Then the user "lp_user@example.com" should have the fund in their access_rights_cache

  Scenario: Approving InvestorAccess after AccessRight is already granted
    Given there is a user "email=lp_user@example.com" for the entity "name=Investor Firm"
    And there is an unapproved investor access for "lp_user@example.com" and investor "Big LP"
    And I grant "read" access to the fund for investor "Big LP"
    Then the user "lp_user@example.com" should NOT have the fund in their access_rights_cache
    When I approve the investor access for "lp_user@example.com"
    Then the user "lp_user@example.com" should have the fund in their access_rights_cache

  Scenario: Creating and approving InvestorAccess after AccessRight is granted
    Given I grant "read" access to the fund for investor "Big LP"
    When I create and approve an investor access for "lp_user@example.com" and investor "Big LP"
    Then the user "lp_user@example.com" should have the fund in their access_rights_cache

  Scenario: Revoking AccessRight updates the cache
    Given there is a user "email=lp_user@example.com" for the entity "name=Investor Firm"
    And there is an approved investor access for "lp_user@example.com" and investor "Big LP"
    And I grant "read" access to the fund for investor "Big LP"
    Then the user "lp_user@example.com" should have the fund in their access_rights_cache
    When I revoke the access right for investor "Big LP" on the fund
    Then the user "lp_user@example.com" should NOT have the fund in their access_rights_cache

  Scenario: Deleting InvestorAccess updates the cache
    Given there is a user "email=lp_user@example.com" for the entity "name=Investor Firm"
    And there is an approved investor access for "lp_user@example.com" and investor "Big LP"
    And I grant "read" access to the fund for investor "Big LP"
    Then the user "lp_user@example.com" should have the fund in their access_rights_cache
    When I delete the investor access for "lp_user@example.com"
    Then the user "lp_user@example.com" should NOT have the fund in their access_rights_cache

  Scenario: Granting AccessRight to a specific user (Employee)
    Given there is a user "email=employee@example.com" for the entity "name=Fund Entity"
    And the user "employee@example.com" has role "employee"
    When I grant "read,update" access to the fund for user "employee@example.com"
    Then the user "employee@example.com" should have the fund in their access_rights_cache with permissions "read,update"
