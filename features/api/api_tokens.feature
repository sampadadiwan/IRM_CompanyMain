Feature: Profile › API tokens
  A signed-in user — two-factor already passed on the website — makes named tokens for scripts.
  A token is shown once, acts exactly as its user, lives 90 days, is never refreshed, and stops
  at once when revoked. At most 10 live tokens per user.
  Reference: docs/modules/funds/funds_json_api.md

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity

  # H10 — Happy path: a two-factor user creates "Quarterly script"; it is shown once, then never again
  @rack_test
  Scenario: H10 A two-factor user creates a token
    Given I am signed in to the website with two-factor on
    When I create the API token "Quarterly script" on Profile › API tokens
    Then I see the new token once with a Copy button
    And reloading Profile › API tokens shows "Quarterly script" without the token

  # H11 — Happy path: a token reads exactly what its user can — Meera's one fund
  Scenario: H11 A token acts as its user
    Given "me" has the API token "Quarterly script"
    When "me" sends GET "/funds.json"
    Then the API status is 200
    And the API answer is a list of 1 row
    And the API answer at "0.name" is "Acme Growth Fund I"

  # H12 — Happy path: revoking on the website stops the token at once
  @rack_test
  Scenario: H12 Revoke stops the token
    Given "me" has the API token "Quarterly script"
    And I am signed in as the current user
    When I revoke "Quarterly script" on Profile › API tokens
    Then I should see "has been revoked"
    When "me" sends GET "/funds.json"
    Then the API status is 401

  # E9 — Edge case: on day 89 the token still works
  Scenario: E9 A token on day 89 works
    Given "me" has the API token "Quarterly script"
    And the API token "Quarterly script" was created 89 days ago
    When "me" sends GET "/funds.json"
    Then the API status is 200

  # X16 — Error case: on day 91 the token has expired
  Scenario: X16 An expired token is refused
    Given "me" has the API token "Quarterly script"
    And the API token "Quarterly script" was created 91 days ago
    When "me" sends GET "/funds.json"
    Then the API status is 401

  # X17 — Error case: a revoked token is refused
  Scenario: X17 A revoked token is refused
    Given "me" has the API token "Quarterly script"
    And the API token "Quarterly script" is revoked
    When "me" sends GET "/funds.json"
    Then the API status is 401

  # E10 — Edge case: the 10th live token is allowed
  @rack_test
  Scenario: E10 The tenth token is allowed
    Given "me" already has 9 live API tokens
    And I am signed in as the current user
    When I try to create another API token on Profile › API tokens
    Then "me" has 10 live API tokens

  # X18 — Error case: the 11th live token is refused with a message
  @rack_test
  Scenario: X18 The eleventh token is refused
    Given "me" already has 10 live API tokens
    And I am signed in as the current user
    When I try to create another API token on Profile › API tokens
    Then I should see "You already have 10 live tokens — revoke one first"
    And "me" has 10 live API tokens

  # E11 — Edge case: last used is written at most every 5 minutes
  Scenario: E11 Last used is throttled
    Given "me" has the API token "Quarterly script"
    And the API token "Quarterly script" was last used 2 minutes ago
    When "me" sends GET "/funds.json"
    Then the API token "Quarterly script" last-used time is unchanged
    Given the API token "Quarterly script" was last used 6 minutes ago
    When "me" sends GET "/funds.json"
    Then the API token "Quarterly script" was just used

  # X19 — Error case: another user cannot revoke Meera's token
  @rack_test
  Scenario: X19 Another user cannot revoke a token
    Given "me" has the API token "Quarterly script"
    And "Sam" is an employee of my firm with no fund access
    When "Sam" tries to revoke the API token "Quarterly script" from the website
    Then the API token "Quarterly script" is still live

  # X20 — Error case: a token cannot be used to make tokens
  Scenario: X20 A token cannot make tokens
    Given "me" has the API token "Quarterly script"
    When "me" sends POST "/users/api_tokens.json" with:
      """
      {"api_token": {"name": "Made by a token"}}
      """
    Then the API status is 403
    And "me" has 1 live API token

  # X21 — Error case: an API token cannot be refreshed
  Scenario: X21 An API token cannot be refreshed
    Given "me" has the API token "Quarterly script"
    When "me" tries to refresh the API token "Quarterly script"
    Then the API status is 403
    And the API answer at "error" is "use_website_token"

  # E20 — Edge case: Devices lists phones only, API tokens lists tokens only
  @rack_test
  Scenario: E20 Devices and API tokens are separate lists
    Given "me" has the API token "Quarterly script"
    And "me" is signed in on a phone
    And I am signed in as the current user
    Then Profile › Devices lists only the phone
    And Profile › API tokens lists only the token
