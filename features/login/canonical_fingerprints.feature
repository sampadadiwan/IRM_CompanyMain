Feature: Canonical fingerprinting for multi-site user sync

  Background:
    Given a baseline user "a@x.com" with primary region "IN" and regions "IN,US"
    And the user has roles "employee"

  Scenario: CCF changes when canonical user fields change
    When I capture the user's CCF
    And I update the user field "first_name" to "JaneX"
    Then the user's CCF should change

  Scenario: CCF does not change for telemetry fields
    When I capture the user's CCF
    And I update the telemetry field "last_sign_in_at" to now
    Then the user's CCF should not change

  Scenario: CCF changes when roles set changes; order-insensitive & unique
    When I capture the user's CCF
    And I set the user roles to "viewer,admin,viewer"
    Then the user's CCF should change
    When I capture the user's CCF
    And I set the user roles to "admin,viewer"
    Then the user's CCF should not change

  Scenario: CCF changes when the linked entity changes (full entity sync)
    When I capture the user's CCF
    And I update the entity field "name" to "Acme Holdings"
    Then the user's CCF should change

  Scenario: Normalization: email case / phone formatting should not change CCF
    When I capture the user's CCF
    And I update the user field "email" to "A@X.COM"
    And I update the user field "phone" to "4155551212"
    Then the user's CCF should not change

  Scenario: needs_sync? requires non-primary targets and changed CCF
    Given the user is already marked synced
    When I set user regions to "IN"
    Then needs_sync? should be "false"
    When I set user regions to "IN,US"
    And I update the user field "last_name" to "xxxxxx"
    Then needs_sync? should be "true"
    When I mark the user as synced now
    Then needs_sync? should be "false"

