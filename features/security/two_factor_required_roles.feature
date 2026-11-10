@security @rack_test
Feature: Required two-factor — refusals and direct requests (OWASP 2026-11 M8)
  Every door that issues a session or acts on two-factor refuses what the rule does not allow,
  even when the request is hand-crafted: the password token endpoint and the LP app for a required
  user without a method, Login as and Set up now for the wrong actor, and every route that would
  switch someone's two-factor off without their password and a current code.
  Design: openspec/changes/require-2fa-privileged-roles (business-rules.md, X3–X10, X15–X25).

  Background:
    Given it is "2026-12-02 10:00" in India

  # ── Phase 1 — other doors ────────────────────────────────────────────────────

  # X3 — Error case: the password token endpoint refuses a required user without two-factor, and makes no token
  Scenario: X3 Token endpoint refuses a required user
    Given I am "Ravi"
    When a script asks for a token for the user with password "password"
    Then the token API should answer 403 with the error "two_factor_required"
    And no token row was made for "Ravi"

  # X4 — Error case: a wrong password at the token endpoint is unchanged — 401, and counted toward the lock
  Scenario: X4 Token endpoint wrong password
    Given I am "Ravi"
    When a script asks for a token for the user with password "wrong-password"
    Then the token API should answer 401 with the error "invalid_authentication"
    And "Ravi" has 1 failed password attempt recorded

  # X5 — Error case: the LP app refuses a support user who is also an LP and has no method
  Scenario: X5 Mobile app refuses a required user without a method
    Given "vikram@caphive.test" is a CapHive support user who is also an LP
    When "vikram@caphive.test" signs in on the phone "Vikram's iPhone" with password "password"
    Then the phone gets the status 403
    And the phone gets the error "finish_2fa_setup"
    And "vikram@caphive.test" has no live phone

  # ── Phase 2 — Login as and Set up now ───────────────────────────────────────

  # X6 — Error case: a support user without a method, still signed in from before the deploy, is refused Login as
  Scenario: X6 Unverified support refused Login as
    Given "Ravi" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Ravi" still has a website session from before the deploy
    When I use Login as on "Dev"
    Then I should see "Set up two-factor authentication before using Login as. Login as opens a client's account, so support and super users need a second factor on their own account first."
    And the alert offers to set up two-factor
    And I am still signed in as "Ravi" and not acting as anyone

  # X7 — Error case: a hand-crafted Login as request from an unverified support user is refused; nothing is impersonated
  Scenario: X7 Direct Login as request refused
    Given "Ravi" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Ravi" has a website session
    When "Ravi" posts Login as for "Dev"
    Then the direct request is refused with "Set up two-factor authentication before using Login as."
    And the session of "Ravi" is not acting as anyone

  # X8 — Error case: Set up now for someone else is refused; neither user changes
  Scenario: X8 Set up now for someone else
    Given the people "Anita" exist
    And "Ravi" has a website session
    When "Ravi" posts to start two-factor set-up for "Anita"
    Then the direct request is refused with "Access Denied"
    And "Anita" has two-factor on with the "authenticator" method
    And "Ravi" is still signed in

  # X9 — Error case: Set up now while acting as a client is refused for the client
  Scenario: X9 Set up now while acting as a client
    Given "Anita" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Anita" has a website session
    And "Anita" posts Login as for "Dev"
    When "Anita" posts to start two-factor set-up for "Dev"
    Then the direct request is refused with "Access Denied"
    And "Dev" has two-factor on with the "authenticator" method

  # X10 — Error case: Set up now is only for required roles — a company admin is refused
  Scenario: X10 Set up now for a non-required role
    Given "Meera" has a website session
    When "Meera" posts to start two-factor set-up for "Meera"
    Then the direct request is refused with "Access Denied"
    And the two-factor flag of "Meera" is off

  # ── Phase 3 — turning two-factor off ────────────────────────────────────────

  # X15 — Error case: a support user cannot turn two-factor off, even with the right password and code
  Scenario: X15 Required user's direct turn-off
    Given "Anita" has a website session
    When "Anita" posts to turn off two-factor for "Anita" with the right password and code
    Then the direct request is refused with "Two-factor authentication is required for your role and cannot be turned off."
    And "Anita" has two-factor on with the "authenticator" method

  # X16 — Error case: a company admin cannot turn off an employee's two-factor
  Scenario: X16 Company admin turns off an employee
    Given the people "Dev" exist
    And "Neha" has a website session
    When "Neha" posts to turn off two-factor for "Dev"
    Then the direct request is refused with "Access Denied"
    And "Dev" has two-factor on with the "authenticator" method

  # X17 — Error case: another firm's company admin is refused too
  Scenario: X17 Other firm's admin
    Given the people "Dev" exist
    And "Tara" has a website session
    When "Tara" posts to turn off two-factor for "Dev"
    Then the direct request is refused with "Access Denied"
    And "Dev" has two-factor on with the "authenticator" method

  # X18 — Error case: a JSON update switching two-factor off is refused by the model
  Scenario: X18 JSON update switching off
    Given "Dev" has a website session
    When "Dev" sends a JSON update switching off two-factor for "Dev"
    Then the JSON answer is 422 with "Two-factor authentication can only be turned off from your user page, with your password and a current code."
    And "Dev" has two-factor on with the "authenticator" method

  # X19 — Error case: the admin console cannot switch someone's two-factor off
  Scenario: X19 Admin console switching off
    Given "Anita" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Anita" is signed in on the website with their code
    When I untick two-factor for "Dev" in the admin console
    Then I should see "Two-factor authentication can only be turned off from your user page, with your password and a current code."
    And "Dev" has two-factor on with the "authenticator" method

  # X20 — Error case: a company admin's HTML update unticking an employee's two-factor is refused
  Scenario: X20 Company admin HTML update switching off
    Given the people "Dev" exist
    And "Neha" has a website session
    When "Neha" submits the edit form switching off two-factor for "Dev"
    Then the edit form is shown again with "Two-factor authentication can only be turned off from your user page, with your password and a current code."
    And "Dev" has two-factor on with the "authenticator" method

  # X21 — Error case: a bearer token cannot turn two-factor off
  Scenario: X21 Bearer token turn-off
    Given "Dev" has an API token "Dev scripts"
    When the API token "Dev scripts" posts to "disable_two_factor" for "Dev"
    Then the API answers 403 with "Access Denied"
    And "Dev" has two-factor on with the "authenticator" method

  # X22 — Error case: a company admin cannot send a turn-off code for someone else; nothing is sent
  @stub-whatsapp
  Scenario: X22 Send code for someone else
    Given the people "Priya" exist
    And "Rahul" has a website session
    When "Rahul" posts to send a two-factor code for "Priya"
    Then the direct request is refused with "Access Denied"
    And WhatsApp codes were sent 0 times

  # X23 — Error case: a bearer token cannot ask for a turn-off code
  @stub-whatsapp
  Scenario: X23 Send code with a bearer token
    Given "Priya" has an API token "Priya scripts"
    When the API token "Priya scripts" posts to "send_two_factor_code" for "Priya"
    Then the API answers 403 with "Access Denied"
    And WhatsApp codes were sent 0 times

  # X24 — Error case: support acting as the user sees no Turn off and a direct turn-off is refused
  Scenario: X24 Turn-off while acting as the user
    Given "Anita" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Anita" is signed in on the website with their code
    When I use Login as on "Dev"
    And I open the user page of "Dev"
    Then I see no "Turn off 2FA" button
    When I post a turn-off for "Dev" from this browser
    Then I should see "Access Denied"
    And "Dev" has two-factor on with the "authenticator" method

  # X25 — Error case: a stolen company-admin session can neither untick two-factor nor pass the popup without the password
  Scenario: X25 Stolen company-admin session
    Given "Neha" has a website session
    When "Neha" submits the edit form switching off two-factor for "Neha"
    Then the edit form is shown again with "Two-factor authentication can only be turned off from your user page, with your password and a current code."
    When "Neha" posts to turn off two-factor for "Neha" with a guessed password
    Then the direct request is refused with "The password you entered is incorrect."
    And "Neha" has two-factor on with the "authenticator" method
    And "Neha" has 1 failed password attempt recorded
