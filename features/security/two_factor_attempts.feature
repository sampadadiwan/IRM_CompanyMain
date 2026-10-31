@cross-region-cache
Feature: Web two-factor code attempts are counted on the server
  The website's two-factor challenge kept its attempt count only in the cookie session, so an
  attacker who had the password could save the cookie after the password step and replay it for
  unlimited code guesses. Each challenge now also has a server-side counter (attempts are the
  larger of the session and server counts), every wrong code also counts toward a per-user limit
  of 10 an hour that locks the account and sends Devise's unlock email (shared with the phone app
  sign-in), and the code POSTs are throttled at 10 a minute per IP.
  Design: docs/security/security_review_2026_10.md, "H13 — Web 2FA attempt counting".

  The test env runs Rails.cache as :null_store; @cross-region-cache gives each scenario a real
  in-memory store so the server-side counters actually count.

  Background:
    Given there is a user "" for an entity "entity_type=Company"

  # H13-H — Happy path: an authenticator (TOTP) user who types the right code is signed in, with the server counter live
  @rack_test
  Scenario: The right code signs the user in
    Given the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

  # H13-1 — Edge case: the cookie saved after the password step is replayed after 3 wrong codes; the server count still applies, so even the right code is refused
  Scenario: Replaying the session cookie does not buy more guesses
    Given the user has two-factor authentication enabled and configured
    And the user has entered their password on the website
    And the browser cookie is saved
    When the user enters 3 wrong codes
    Then the user should be sent back to sign in with "Too many failed attempts"
    When the saved cookie is restored
    And the user enters the right code
    Then the user should be sent back to sign in with "Too many failed attempts"
    And the replaying browser should not be signed in

  # H13-2 — Error case: 12 wrong codes tried across 4 password logins; the 10th in the hour locks the account and sends the unlock email
  Scenario: Too many wrong codes in an hour lock the account
    Given the user has two-factor authentication enabled and configured
    When the user tries 3 wrong codes on each of 4 password logins
    Then the account should be locked at the 10th wrong code
    And the user should have received an unlock email
    And a password login should be refused

  # H13-3 — Error case: 11 code POSTs from one IP inside a minute; the 11th is throttled with 429
  @rack_attack
  Scenario: Code guesses from one IP are throttled
    Given a visitor "guesser" browsing from IP "203.0.113.90"
    When "guesser" posts 11 two-factor codes
    Then the first 10 code posts should reach the app and the next be throttled

  # H13-X — Error case: 3 wrong codes on the authenticator enrollment screen end the challenge and send the user back to sign in
  @rack_test
  Scenario: Wrong enrollment codes end the challenge like login codes
    Given the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA mode selection page
    When I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    When I enter an invalid TOTP code and confirm
    Then I should see "Invalid code. 2 attempt(s) remaining."
    When I enter an invalid TOTP code and confirm
    And I enter an invalid TOTP code and confirm
    Then I should be redirected to the login page
    And I should see "Too many failed attempts"
    And the user should still have no two-factor method
