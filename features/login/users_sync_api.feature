Feature: Users Sync API (upsert/disable/digest)

  Background:
    Given the server region is "US" and an HMAC secret is configured

  Scenario: UPSERT creates user + entity and replaces roles
    When I prepare an UPSERT payload for "jane@example.com" from origin "IN" with roles "employee,company_admin" existing "false"
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 200
    And the JSON response should include "applied" = true
    And a user "jane@example.com" should exist with primary_region "IN" and regions "IN,US"
    And the user "jane@example.com" should have roles "employee,company_admin"
    And the user's last_synced_ccf_hex should equal the payload CCF
    And an entity named "Acme Holdings" should exist

  Scenario: UPSERT updates user + entity and replaces roles
    When I prepare an UPSERT payload for "jane@example.com" from origin "IN" with roles "employee,company_admin" existing "true"
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 200
    And the JSON response should include "applied" = true
    And a user "jane@example.com" should exist with primary_region "IN" and regions "IN,US"
    And the user "jane@example.com" should have roles "employee,company_admin"
    And the user's last_synced_ccf_hex should equal the payload CCF
    And an entity named "Acme Holdings" should exist

  Scenario: UPSERT is idempotent when same CCF is sent again
    Given a user exists via a prior UPSERT for "reid@example.com"
    And I reuse the last UPSERT payload
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 200
    And the JSON response should include "applied" = false
    And the JSON response should include "reason" = "no_change"

  Scenario: UPSERT rejects stale primary
    Given an existing user "stale@example.com" with primary_region "SG"
    And I prepare an UPSERT payload for "stale@example.com" from origin "IN" with roles "viewer" existing "false"
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 409
    And the JSON response should include "reason" = "stale_primary"

  Scenario: DISABLE soft-disables a user
    Given a user exists via a prior UPSERT for "disabled@example.com"
    And I prepare a DISABLE payload for "disabled@example.com" from origin "IN"
    When I POST the signed request to "/internal/sync/users/disable"
    Then the response status should be 200
    And the JSON response should include "applied" = true
    And the user "disabled@example.com" should be disabled

  Scenario: DISABLE rejects stale primary
    Given an existing user "wrong@example.com" with primary_region "SG"
    And I prepare a DISABLE payload for "wrong@example.com" from origin "IN"
    When I POST the signed request to "/internal/sync/users/disable"
    Then the response status should be 409
    And the JSON response should include "reason" = "stale_primary"

  Scenario: DIGEST returns digests for found & missing users
    Given a user exists via a prior UPSERT for "digest@example.com"
    And I prepare a DIGEST payload for emails "digest@example.com,missing@example.com"
    When I POST the signed request to "/internal/sync/users/digest"
    Then the response status should be 200
    And the JSON response "digests" should have a non-empty value for "digest@example.com"
    And the JSON response "digests" should have a null value for "missing@example.com"
