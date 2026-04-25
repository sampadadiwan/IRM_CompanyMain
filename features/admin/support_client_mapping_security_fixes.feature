Feature: SupportClientMapping Security Fixes
  As a security-conscious system
  I want to verify that all six security vulnerabilities are properly mitigated
  So that support access is correctly bounded and cannot be escalated or retained beyond its intended scope

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 1: Expired mapping must force-revert the user's context
  # ──────────────────────────────────────────────────────────────────────────

  Background:
    Given a user exists with role "support"
    And an entity exists with employees
    And a support client mapping exists linking the user to the entity

  Scenario: Expiring a mapping auto-reverts a currently-switched support user
    Given the mapping is enabled
    And the user has switched
    And it has an end_date in the past
    When I call disable_expired
    Then the mapping should be disabled
    And the user should be back in their original entity
    And the user should not have the "company_admin" role
    And the user should have the "support" role

  Scenario: Administratively disabling a mapping auto-reverts a switched user
    Given the mapping is enabled
    And the user has switched
    When I manually disable the mapping
    Then the mapping should be disabled
    And the user should be back in their original entity
    And the user should not have the "company_admin" role

  Scenario: Destroying a mapping auto-reverts a switched user
    Given the mapping is enabled
    And the user has switched
    When I delete the mapping
    Then the user should be back in their original entity
    And the user should not have the "company_admin" role

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 2: :support role must be removed during switch (cross-entity read prevention)
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: Support role is stripped when switching into a client entity
    Given the mapping is enabled
    When I call switch
    Then the user should not have the "support" role
    And the user should have the "company_admin" role

  Scenario: Support role is restored when reverting from a client entity
    Given the mapping is enabled
    And the user has switched
    When I call revert
    Then the user should have the "support" role
    And the user should not have the "company_admin" role

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 3: Revert must not replay cached roles — revocations must stick
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: Roles revoked while switched remain revoked after revert
    Given the mapping is enabled
    And the user has switched
    And the user is granted the "approver" role while switched
    And the "approver" role is then revoked by an admin
    When I call revert
    Then the user should not have the "approver" role

  Scenario: json_fields cache is cleared after a successful revert
    Given the mapping is enabled
    And the user has switched
    When I call revert
    Then the orig_entity_id should be cleared from json_fields
    And the orig_roles should be cleared from json_fields

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 4: Only the mapped user themselves can trigger switch/revert
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: Super user cannot switch another support user's context
    Given a super user exists
    When the super user checks the switch policy for the support user's mapping
    Then the switch should be denied for the super user

  Scenario: Super user cannot revert another support user's context
    Given a super user exists
    And the mapping is enabled
    And the user has switched
    When the super user checks the revert policy for the support user's mapping
    Then the revert should be denied for the super user

  Scenario: Mapped user can switch their own context
    Given the mapping is enabled
    When the mapped user checks the switch policy
    Then the switch should be permitted for the mapped user

  Scenario: Mapped user can revert their own context
    Given the mapping is enabled
    And the user has switched
    When the mapped user checks the revert policy
    Then the revert should be permitted for the mapped user

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 5: allow_login_as must be enforced — case-insensitive email matching
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: allow_login_as is denied when enable_user_login is false
    Given the mapping has user_emails "allowed@test.com"
    And enable_user_login is false
    When I call allow_login_as with "allowed@test.com"
    Then it should return false

  Scenario: allow_login_as matches email case-insensitively
    Given the mapping has user_emails "Allowed@Test.COM"
    And enable_user_login is true
    When I call allow_login_as with "allowed@test.com"
    Then it should return true

  Scenario: allow_login_as rejects an email not in the whitelist
    Given the mapping has user_emails "allowed@test.com"
    And enable_user_login is true
    When I call allow_login_as with "notallowed@test.com"
    Then it should return false

  Scenario: allow_login_as permits all when user_emails is blank and login enabled
    Given the mapping has no user_emails restriction
    And enable_user_login is true
    When I call allow_login_as with "anyone@anywhere.com"
    Then it should return true

  # ──────────────────────────────────────────────────────────────────────────
  # Finding 6: Index scope must not expose disabled/expired mappings
  # ──────────────────────────────────────────────────────────────────────────

  Scenario: Non-super user cannot see disabled mappings in the index scope
    Given a second mapping exists for the user that is disabled
    When I resolve the scope as the support user
    Then I should see only the enabled mapping
    And I should not see the disabled mapping
