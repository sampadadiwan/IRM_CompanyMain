Feature: Multi-site user sync fanout

  @sync-http @rack_test
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

  @sync-http @rack_test
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

  @sync-http @rack_test
  Scenario: Entity change causes UPSERT
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the user is already synced
    And the sync API for "US" is stubbed for UPSERT
    When I change the user's entity name to "NewCo"
    And I trigger the orchestrator for that user with force "false"
    Then a signed UPSERT should be sent to "US"

  @sync-http @rack_test
  Scenario: Roles are sent as unique names
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the user has roles "company_admin,employee"
    And the sync API for "US" is stubbed for UPSERT
    When I enqueue an upsert job to "US"
    Then the UPSERT roles should be "company_admin,employee"

  @sync-http @rack_test
  Scenario: Retryable on 500
    Given a user "a@x.com" exists in region "IN" with regions "IN,US"
    And the UPSERT endpoint for "US" responds 500
    When I perform an upsert to "US" capturing errors
    Then a retryable sync error should occur

  @cross-site-redirect @rack_test
  Scenario: redirect_to_subdomain uses the user's entity sub_domain
    Given a user "alice@example.com" exists in region "IN" with regions "IN,US"
    And the user's entity has sub_domain "svr"
    And a cross-site login token is generated for "alice@example.com" targeting site "IN"
    When I request redirect_to_subdomain on host "app.example.com"
    Then I should be redirected to "svr.example.com" for cross-site login

  @cross-site-redirect @rack_test
  Scenario: redirect_to_subdomain falls back to "app" when entity has no sub_domain
    Given a user "bob@example.com" exists in region "IN" with regions "IN,US"
    And the user's entity has no sub_domain
    And a cross-site login token is generated for "bob@example.com" targeting site "IN"
    When I request redirect_to_subdomain on host "app.example.com"
    Then I should be redirected to "app.example.com" for cross-site login

  # Was a 401 rendering the bare string "Invalid or expired link". A failed hand-off now lands
  # on this region's own sign-in screen with a banner saying what went wrong.
  @cross-site-redirect @rack_test
  Scenario: redirect_to_subdomain sends an invalid token to the sign-in screen
    When I request redirect_to_subdomain with invalid token on host "app.example.com"
    Then I should land on the sign-in screen with a cross-region banner

  # This exercises all 3 hops (cross_site_link -> redirect_to_subdomain -> cross_site_login)
  # in a single test process/database, so it proves the routing/token/subdomain logic is
  # correct end-to-end, but it does NOT prove two real separately-deployed instances with
  # separate databases agree on the user's identity - that part is emulated by reusing the
  # same @user/@entity row and just swapping ENV["CURRENT_SITE"] between hops.
  @cross-site-login-flow @rack_test
  Scenario: A US-side user crosses to the IN site and lands signed in on the correct subdomain
    Given a user "neha@siliconroad.com" exists in region "US" with regions "IN,US"
    And the user's entity has sub_domain "srv"
    And site "US" is served at "https://app.caphive.us"
    And site "IN" is served at "https://app.caphive.com"
    And the current site is "US"
    And I am signed in as "neha@siliconroad.com" on host "siliconroad.caphive.us"
    When I click the cross-site link targeting site "IN"
    Then I should be redirected to "app.caphive.com" to resolve the subdomain
    When I follow that redirect
    Then I should be redirected to "srv.caphive.com" for cross-site login
    When I follow that redirect as site "IN"
    Then I should be signed in and redirected to the site root