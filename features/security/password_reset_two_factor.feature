Feature: Security M3 / L3 - password resets respect two-factor and the current password
  M3: Devise signed a user in straight after a password reset, so for a two-factor user the
  emailed link alone was a full login. Two-factor users are now sent to the sign-in page after a
  reset, where the password login asks for their code.
  L3: the first-login "Reset Password Now" banner set a password without asking for the current
  one, and any signed-in user (or support, while impersonating) could post it. It now works only
  for a system-created user on their first login, never while impersonating; everyone else is
  sent to the change-password page, which asks for the current password.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", M3 and L3

  # M3-H — Happy path: a user without two-factor resets their password and is signed in, as before
  @security @rack_test
  Scenario: M3-H A user without two-factor is signed in after a reset
    Given there is a user "" for an entity "entity_type=Company"
    When the user opens their emailed password reset link
    And I set my new password to "NewPassw0rd!23"
    Then I should see "Your password has been changed successfully. You are now signed in."

  # M3-1 — Edge case: a two-factor user is sent to sign in after a reset, and the next login asks for the code
  @security @rack_test
  Scenario: M3-1 A two-factor user must sign in with their code after a reset
    Given there is a user "" for an entity "entity_type=Company"
    And the user has two-factor authentication enabled and configured
    When the user opens their emailed password reset link
    And I set my new password to "NewPassw0rd!23"
    Then I should be redirected to the login page
    And I should see "Your password has been changed successfully."
    And I should not see "You are now signed in"
    When I sign in with the password "NewPassw0rd!23"
    Then I should be on the 2FA verification page

  # L3-H — Happy path: a system-created user on their first login uses the banner and gets the set-password form
  @security @rack_test
  Scenario: L3-H The first-login banner opens the set-password form
    Given Im logged in as a user "" for an entity "entity_type=Company"
    And the user is a system-created user on their first login
    When I press "Reset Password Now" on the first-login banner
    Then I am on the set-new-password form
    And the user has a password reset token

  # L3-1 — Error case: a user past their first login posting the banner's reset is sent to change-password instead
  @security @rack_test
  Scenario: L3-1 A regular user cannot set a password without the current one
    Given Im logged in as a user "" for an entity "entity_type=Company"
    When I post the first-login password reset
    Then I am sent to the change-password page
    And I should see "Change your password here"
    And the user has no password reset token

  # L3-2 — Error case: support impersonating a first-login user cannot set that user's password
  @security @rack_test
  Scenario: L3-2 Support cannot reset an impersonated user's password
    Given there is a user "" for an entity "entity_type=Company"
    And the user is a system-created user on their first login
    When a support user impersonating the user posts the first-login password reset
    Then the impersonated request is sent to the change-password page
    And the user has no password reset token
