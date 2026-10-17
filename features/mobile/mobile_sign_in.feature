# LP mobile app — phone sign-in (design card ②).
# Worked examples: openspec/changes/lp-mobile-app/design.md#worked-examples
@cross-region-cache
Feature: LP mobile app sign-in
  A phone signs in with the same email, password and two-factor code as the website. A user
  with two-factor gets a challenge, never a session, until a valid code is entered.

  Background:
    Given a mobile investor "rahul@sharmafo.in" of "Sharma Family Office" with fund manager "Arka Capital"

  # H1 — Happy path: password + authenticator code gives a session and registers the phone
  Scenario: Sign in with an authenticator code
    Given "rahul@sharmafo.in" has authenticator two-factor
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets a challenge for "authenticator" two-factor with 3 attempts
    And "rahul@sharmafo.in" has no phones
    When the phone "iPhone 15" enters the current authenticator code for "rahul@sharmafo.in"
    Then the phone gets a session
    And "rahul@sharmafo.in" has a live phone "iPhone 15"

  # H2 — Happy path: a user without two-factor gets a session straight away
  Scenario: Sign in without two-factor
    When "rahul@sharmafo.in" signs in on the phone "Pixel 8" with password "password"
    Then the phone gets a session
    And "rahul@sharmafo.in" has a live phone "Pixel 8"

  # H3 — Happy path: refreshing rotates the tokens and the old access token stops working
  Scenario: Refresh rotates the tokens
    Given "rahul@sharmafo.in" is signed in on the phone "iPhone 15"
    When the phone "iPhone 15" refreshes its session
    Then the phone gets the status 201
    When the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 200
    When the phone "iPhone 15" uses its old access token
    And the phone "iPhone 15" requests "/api/mobile/v1/me"
    Then the phone gets the status 401

  # E1 — Edge case: one wrong code uses one attempt; the right code then still works
  Scenario: A wrong code then the right one
    Given "rahul@sharmafo.in" has authenticator two-factor
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    And the phone "iPhone 15" enters the code "000000"
    Then the phone gets the status 422
    And the phone gets the error "invalid_code"
    And the JSON at "attempts_left" is "2"
    When the phone "iPhone 15" enters the current authenticator code for "rahul@sharmafo.in"
    Then the phone gets a session

  # E2 — Edge case: the challenge works at 9:59 and has expired at 10:01
  Scenario: The code screen times out after 10 minutes
    Given "rahul@sharmafo.in" has authenticator two-factor
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    And 9 minutes and 59 seconds pass
    And the phone "iPhone 15" enters the current authenticator code for "rahul@sharmafo.in"
    Then the phone gets a session
    When "rahul@sharmafo.in" signs in on the phone "iPad" with password "password"
    And 10 minutes and 1 seconds pass
    And the phone "iPad" enters the current authenticator code for "rahul@sharmafo.in"
    Then the phone gets the status 401
    And the phone gets the error "challenge_expired"

  # E3 — Edge case: a resend inside the cooldown is refused; after it, a new code is sent
  @stub-twilio
  Scenario: Resending a text message code respects the cooldown
    Given "rahul@sharmafo.in" has sms two-factor
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets a challenge for "sms" two-factor with 3 attempts
    And a text message code was sent 1 time
    When the phone "iPhone 15" asks for the code again
    Then the phone gets the status 429
    And the phone sees the message "Please wait a moment before requesting another code."
    And a text message code was sent 1 time
    When 1 minutes and 1 seconds pass
    And the phone "iPhone 15" asks for the code again
    Then the phone gets the status 204
    And a text message code was sent 2 times

  # E4 — Edge case: two-factor on but no method chosen — finish setting it up on the website
  Scenario: Two-factor switched on but not set up
    Given "rahul@sharmafo.in" has two-factor switched on but no method set up
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets the status 403
    And the phone gets the error "finish_2fa_setup"
    And "rahul@sharmafo.in" has no phones

  # X1 — Error case: a wrong password is refused and counts toward the lockout
  Scenario: Wrong password
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "wrong-password"
    Then the phone gets the status 401
    And the phone sees the message "Incorrect email or password."
    And "rahul@sharmafo.in" has 1 failed password attempt

  # X2 — Error case: the third wrong code ends the challenge, as on the website
  Scenario: Three wrong codes end the sign-in
    Given "rahul@sharmafo.in" has authenticator two-factor
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    And the phone "iPhone 15" enters the code "000000"
    And the phone "iPhone 15" enters the code "000001"
    And the phone "iPhone 15" enters the code "000002"
    Then the phone gets the status 401
    And the phone sees the message "Too many failed attempts. Please sign in again."
    When the phone "iPhone 15" enters the current authenticator code for "rahul@sharmafo.in"
    Then the phone gets the error "challenge_spent"
    And "rahul@sharmafo.in" has no phones

  # X3 — Error case: a locked account is refused with the website's lockout period
  Scenario: Locked account
    Given "rahul@sharmafo.in" is locked out
    When "rahul@sharmafo.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets the status 423
    And the phone sees the message "Your account is locked. Please try again in 5 minutes."

  # X4 — Error case: a fund manager employee is not an investor and cannot use the app
  Scenario: Fund manager employee refused
    Given "meera@arkacapital.in" is an employee of the fund manager "Arka Capital"
    When "meera@arkacapital.in" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets the status 403
    And the phone sees the message "This app is for investors. Please use the CapHive website."
    And "meera@arkacapital.in" has no phones

  # X14 — Error case: an email unknown in this region gets the same answer as a wrong password
  Scenario: Wrong region looks like a wrong password
    When "jane@us-lp.com" signs in on the phone "iPhone 15" with password "password"
    Then the phone gets the status 401
    And the phone sees the message "Incorrect email or password."
