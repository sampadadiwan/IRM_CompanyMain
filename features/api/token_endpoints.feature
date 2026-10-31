Feature: The token endpoints do not reveal which accounts exist and cannot be hammered
  devise-api's /users/tokens/sign_in answered an unknown email differently from a wrong password
  (and named a locked account), /users/tokens/sign_up let anyone create a user, the website's
  forgot-password form said "Email not found", and neither the token sign-in nor Doorkeeper's
  /oauth/token, /oauth/revoke and /oauth/introspect were throttled. Now devise-api and Devise run
  in paranoid mode, the API sign-up is off, token sign-in is limited to 10 per 30 s per IP and 5 a
  minute per email, and the OAuth client endpoints to 60 a minute per IP.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", M6.

  Background:
    Given there is a user "first_name=Script-User" for an entity "entity_type=Investment Fund;name=Acme Tokens;currency=INR"

  # M6-H — Happy path: a user without two-factor still gets a token with the right password (onboarding skill, runbooks)
  Scenario: The right password gets a token
    When a script asks for a token for the user with password "password"
    Then the token API should answer 200 with a token

  # M6-1 — Edge case: an unknown email, a wrong password and a locked account all get the same 401 answer, with no account details
  Scenario: An unknown email answers exactly like a wrong password or a locked account
    When a script asks for a token for the user with password "wrong-password"
    Then the token API should answer 401 with the error "invalid_authentication"
    And the token API answer is remembered
    When a script asks for a token for "nobody-here@example.com" with password "wrong-password"
    Then the token API answer should be identical to the remembered one
    Given the user's account is locked
    When a script asks for a token for the user with password "password"
    Then the token API answer should be identical to the remembered one

  # M6-2 — Error case: the API sign-up is off, so no account can be created through it
  Scenario: Signing up through the token API is refused
    When someone tries to sign up "walk-in@example.com" through the token API
    Then the token API should answer 400 with the error "sign_up_disabled"
    And no user "walk-in@example.com" should exist

  # M6-3 — Edge case: the 11th token sign-in from one IP within 30 seconds is throttled
  @rack_attack
  Scenario: Token sign-in is throttled per IP
    Given a visitor "Scripter" browsing from IP "198.51.100.7"
    When "Scripter" posts to "/users/tokens/sign_in" 11 times
    Then the first 10 posts should reach the app and the rest be throttled

  # M6-3 — Edge case: the 6th token sign-in for one email within a minute is throttled, even from different IPs
  @rack_attack
  Scenario: Token sign-in is throttled per email
    When 6 visitors from different IPs ask for a token for "target@example.com"
    Then the first 5 posts should reach the app and the rest be throttled

  # M6-3 — Edge case: Doorkeeper's client endpoints allow 60 posts a minute per IP, then throttle
  @rack_attack
  Scenario Outline: The OAuth client endpoints are throttled per IP
    Given a visitor "Client" browsing from IP "198.51.100.8"
    When "Client" posts to "<path>" 61 times
    Then the first 60 posts should reach the app and the rest be throttled

    Examples:
      | path              |
      | /oauth/token      |
      | /oauth/revoke     |
      | /oauth/introspect |

  # M2 (throttle part of the registration gate) — Edge case: the 31st registration from one IP within an hour is throttled
  @rack_attack
  Scenario: Client registration is throttled per IP
    Given a visitor "Registrar" browsing from IP "198.51.100.9"
    When "Registrar" posts to "/oauth/registration" 31 times
    Then the first 30 posts should reach the app and the rest be throttled

  # M6-4 — Edge case: the forgot-password form answers a known and an unknown address with the same message
  Scenario: Forgot-password does not reveal whether an address has an account
    When someone asks for a password reset for the user
    Then the password reset page should say "If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes."
    When someone asks for a password reset for "nobody-here@example.com"
    Then the password reset page should say "If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes."
