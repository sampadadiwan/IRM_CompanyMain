Feature: Multi-site user sync fanout

  @sync-http
  Scenario: Fan out UPSERT to US and SG when CCF changed
    Given a user "a@x.com" exists in region "IN" with regions "IN,US,SG"
    And the user has roles "company_admin,employee"
    And the sync API for "US" is stubbed for UPSERT
    And the sync API for "SG" is stubbed for UPSERT
    When I trigger the orchestrator for that user with force "true"
    Then a signed UPSERT should be sent to "US"
    And a signed UPSERT should be sent to "SG"
    And the UPSERT body should include the user's email and roles

  @sync-http
  Scenario: Do not call UPSERT on the primary region
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the sync API for "IN" is stubbed for UPSERT
    When I enqueue an upsert job to "IN"
    Then no UPSERT should be sent to "IN"

  @sync-http
  Scenario: Send DISABLE when a region is removed
    Given a user "a@x.com" exists in region "IN" with regions "IN,SG"
    And the user is already synced
    And the sync API for "US" is stubbed for DISABLE
    When I orchestrate with previous regions "IN,US,SG"
    Then a signed DISABLE should be sent to "US"
    And no UPSERT should be sent to "SG"

  @sync-http
  Scenario: Skip UPSERT when CCF unchanged
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the user is already synced
    And the sync API for "US" is stubbed for UPSERT
    When I trigger the orchestrator for that user with force "false"
    Then no UPSERT should be sent to "US"

  @sync-http
  Scenario: Entity change causes UPSERT
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the user is already synced
    And the sync API for "US" is stubbed for UPSERT
    When I change the user's entity name to "NewCo"
    And I trigger the orchestrator for that user with force "false"
    Then a signed UPSERT should be sent to "US"

  @sync-http
  Scenario: Roles are sent as unique names
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the user has roles "company_admin,employee"
    And the sync API for "US" is stubbed for UPSERT
    When I enqueue an upsert job to "US"
    Then the UPSERT roles should be "company_admin,employee"

  @sync-http
  Scenario: Retryable on 500
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the UPSERT endpoint for "US" responds 500
    When I perform an upsert to "US" capturing errors
    Then a retryable sync error should occur

  @sync-http
  Scenario: Job swallows fatal 409 from target
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the UPSERT endpoint for "US" responds 409
    When I perform an upsert to "US" capturing errors
    Then no sync exception should be raised
    And a signed UPSERT should be sent to "US"