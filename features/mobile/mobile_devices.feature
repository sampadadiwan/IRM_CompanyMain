# LP mobile app — device registry and the website's Profile › Devices page (design card ③).
# Worked examples: openspec/changes/lp-mobile-app/design.md#worked-examples
@cross-region-cache
Feature: LP mobile app devices
  Each phone is one device row holding its session. Signing a phone out — from the app, from
  the website, by a password change or a deactivation — ends that session at once.

  Background:
    Given a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"

  # H14 — Happy path: a phone signed out on the website loses its session
  @rack_test
  Scenario: Sign out a phone from the website
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    And "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    And I am signed in as the current user
    When I visit the Mobile Devices page
    Then I should see "iPhone 15"
    And I should see "Pixel 8"
    When I sign out the phone "iPhone 15" on the Mobile Devices page
    Then I should see "iPhone 15 has been signed out."
    And the phone "iPhone 15" is signed out because "website_sign_out"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 401
    When the phone "Pixel 8" requests "/api/mobile/v1/me"
    Then the phone gets the status 200

  # E5 — Edge case: an eleventh phone signs out the least recently used
  Scenario: Eleventh phone
    Given "rahul@sharmafo.in" already has 10 live phones
    When "rahul@sharmafo.in" signs in on the phone "iPhone 16" with password "password"
    Then the phone gets a session
    And "rahul@sharmafo.in" has 10 live phones
    And the phone "Old phone 1" is signed out because "device_limit"

  # E6 — Edge case: the same install signing in again reuses its row
  Scenario: Same phone signs in again after signing out
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    When the phone "iPhone 15" sends "DELETE" to "/api/mobile/v1/session" with:
      """
      {}
      """
    Then the phone gets the status 204
    And the phone "iPhone 15" is signed out because "app_sign_out"
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets a session
    And "rahul@sharmafo.in" has 1 phone record
    And "rahul@sharmafo.in" has a live phone "iPhone 15"

  # E8 — Edge case: 89 days unused still works; 91 days unused must sign in again
  Scenario: Ninety-day session boundary
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    And "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    And the phone "iPhone 15" was last used 89 days ago
    And the phone "Pixel 8" was last used 91 days ago
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 200
    When the phone "Pixel 8" requests "/api/mobile/v1/me"
    Then the phone gets the status 401

  # X5 — Error case: a deactivated user's phones are signed out
  Scenario: Deactivated user
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    When the investor user "rahul@sharmafo.in" is deactivated
    And the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 401
    And the phone "iPhone 15" is signed out because "deactivated"

  # X6 — Error case: changing the password signs every phone out
  Scenario: Password change
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    And "rahul@sharmafo.in" is signed in on the phone "Pixel 8"
    When the user "rahul@sharmafo.in" changes their password
    And the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 401
    And the phone "iPhone 15" is signed out because "password_changed"
    And the phone "Pixel 8" is signed out because "password_changed"

  # X7 — Error case: a website API token (minted without two-factor) cannot reach the phone API
  Scenario: Website API token refused
    Given "rahul@sharmafo.in" has a website API token
    When the phone "Website client" requests "/api/mobile/v1/me"
    Then the phone gets the status 401
    And the phone gets the error "unauthorised"

  # X15 — Error case: a signed-out phone is refused on every request
  Scenario: Signed-out phone
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    And the phone "iPhone 15" was signed out on the website
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 401

  # X22 — Error case: a two-factor user cannot get an API token without a code (website token endpoint)
  Scenario: Two-factor user refused by the website token endpoint
    Given "rahul@sharmafo.in" has authenticator two-factor
    When "rahul@sharmafo.in" asks the website's token endpoint for a token with password "password"
    Then the phone gets the status 403
    And the phone gets the error "two_factor_required"
    And "rahul@sharmafo.in" has no phones

  # X22 (counterpart) — a user without two-factor still gets a website API token, as before
  Scenario: User without two-factor still gets a website token
    When "rahul@sharmafo.in" asks the website's token endpoint for a token with password "password"
    Then the phone gets the status 200

  # X23 — Error case: a phone's token is refreshed only by the app, never by the website's token endpoint
  Scenario: Website token endpoint will not refresh a phone's token
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    When the phone "iPhone 15" refreshes through the website's token endpoint
    Then the phone gets the status 403
    And the phone gets the error "use_mobile_refresh"
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 200
