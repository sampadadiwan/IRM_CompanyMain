@rack_test
Feature: Two-factor is required for support and super users
  OWASP 2026-11 finding M8. CapHive's own support and super users must use two-factor from the day it
  is deployed, in every region (user decision 2026-11-09: no enforcement date or notice period). A required
  user with no method is sent through the existing "choose a method" set-up inside sign-in; company
  admins, employees and investors keep today's optional two-factor.
  Design: openspec/changes/archive/2026-11-10-require-2fa-privileged-roles (business-rules.md §1, H1–H3, E5–E19, X1–X2; E1–E4 and E20 retired with the date).

  Background:
    Given it is "2026-12-02 10:00" in India

  # ── Happy path ────────────────────────────────────────────────────────────────

  # H1 — Happy path: a support user without two-factor meets the set-up screen at sign-in
  Scenario: H1 Support user meets set-up
    When "Ravi" signs in with their password
    Then I see the required set-up screen for the role "Support"
    And I should see "The authenticator app works without a phone number."
    And "Ravi" has two-factor off with no method

  # H2 — Happy path: confirming a method switches two-factor on and emails the user
  Scenario: H2 Required set-up completes
    When "Ravi" signs in with their password
    And I select the Authenticator mode
    And I enter a valid TOTP code and confirm
    Then I should see "Two-factor authentication is now enabled."
    And "Ravi" has two-factor on with the "authenticator" method
    And "Ravi" is emailed "Two-factor authentication was turned on for your account" dated "Dec 02, 2026"
    And the email "Two-factor authentication was turned on for your account" to "Ravi" says "If you did not set this up"

  # H3 — Happy path: a support user who already has a method gets the code screen, then is signed in
  Scenario: H3 Support user with a method
    When "Anita" signs in with their password
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

  # ── Edge cases ────────────────────────────────────────────────────────────────

  # E5 — Edge case: a support role granted later applies at the next sign-in
  Scenario: E5 Support role granted later
    Given "Isha" is granted the "support" role
    When "Isha" signs in with their password
    Then I see the required set-up screen for the role "Support"

  # E6 — Edge case: a support role removed before set-up stops the rule applying
  Scenario: E6 Support role removed before set-up
    Given "Ravi" loses the "support" role
    When "Ravi" signs in with their password
    Then I am signed in with the password only

  # E7 — Edge case: a company admin is not required
  Scenario: E7 Company admin not required
    When "Meera" signs in with their password
    Then I am signed in with the password only

  # E8 — Edge case: a super user is required too, labelled "Super"
  Scenario: E8 Super user required
    When "Sam" signs in with their password
    Then I see the required set-up screen for the role "Super"

  # E9 — Edge case: an investor's own two-factor works as today (WhatsApp code sent)
  @stub-whatsapp
  Scenario: E9 Investor with 2FA unchanged
    When "Priya" signs in with their password
    Then I should be on the 2FA verification page
    And a WhatsApp code was sent

  # E10 — Edge case: no phone number — only the authenticator app is offered, preselected
  Scenario: E10 No phone means authenticator only
    When "Ravi" signs in with their password
    Then I see the required set-up screen for the role "Support"
    And only the authenticator app is offered, preselected

  # E11 — Edge case: an abandoned set-up stores nothing; the next sign-in meets set-up again
  Scenario: E11 Abandoned set-up
    When "Ravi" signs in with their password
    And I select the Authenticator mode
    Then I should be on the 2FA enrollment page
    When "Ravi" signs in with their password
    Then I see the required set-up screen for the role "Support"
    And "Ravi" has two-factor off with no method

  # E12 — Edge case: a support user switched into a client (support + company_admin) sees one set-up, labelled "Support"
  Scenario: E12 Support switched into a client
    Given "Ravi" is switched into "Sahyadri Capital"
    When "Ravi" signs in with their password
    Then I see the required set-up screen for the role "Support"

  # E13 — Edge case: a company admin who switched two-factor on himself gets set-up as today, without the "required" banner
  Scenario: E13 Company admin with flag on and no method
    When "Omkar" signs in with their password
    Then I see the set-up screen without the required banner

  # E14 — Edge case: a required user whose WhatsApp number is gone is refused as today
  Scenario: E14 Required user with undeliverable WhatsApp
    Given "Anita" is in WhatsApp mode with no phone number
    When "Anita" signs in with their password
    Then I should see "We can't send a verification code to your phone right now. Please contact your administrator."

  # E15 — Edge case: magic link → required set-up → the linked page
  Scenario: E15 Magic link through set-up to the linked page
    When "Ravi" opens a sign-in link back to their user page
    Then I see the required set-up screen for the role "Support"
    When I select the Authenticator mode
    And I enter a valid TOTP code and confirm
    Then I am on my user page

  # E16 — Edge case: a password reset does not sign a required user in; the next sign-in meets set-up
  Scenario: E16 Password reset does not sign a required user in
    Given I am "Ravi"
    When the user opens their emailed password reset link
    And I set my new password to "NewPassw0rd!23"
    Then I should be redirected to the login page
    And I should see "Your password has been changed successfully."
    When I sign in with the password "NewPassw0rd!23"
    Then I see the required set-up screen for the role "Support"

  # E17 — Edge case: required set-up by text message switches two-factor on in sms mode
  @stub-twilio
  Scenario: E17 Required set-up via SMS
    Given "Isha" is granted the "support" role
    When "Isha" signs in with their password
    And I select the SMS mode
    Then I should be on the SMS 2FA enrollment page
    When I enter the texted code to confirm enrollment
    Then I should see "Two-factor authentication via text message is now enabled."
    And "Isha" has two-factor on with the "sms" method

  # E18 — Edge case: a support user who is also an LP, enrolled on the website, gets the normal app challenge
  Scenario: E18 Mobile app after web set-up
    Given "vikram@caphive.test" is a CapHive support user who is also an LP
    And "vikram@caphive.test" has authenticator two-factor
    When "vikram@caphive.test" signs in on the phone "Vikram's iPhone" with password "password"
    Then the phone gets a challenge for "authenticator" two-factor with 3 attempts
    When the phone "Vikram's iPhone" enters the current authenticator code for "vikram@caphive.test"
    Then the phone gets a session

  # E19 — Edge case: an API token made on the website keeps working (until ops ends unverified access)
  Scenario: E19 Website-made API token still works
    Given "Anita" has an API token "Anita reports"
    When the API token "Anita reports" reads "/funds.json"
    Then the API answers 200

  # ── Error cases ───────────────────────────────────────────────────────────────

  # X1 — Error case: three wrong set-up codes end the challenge and store nothing
  Scenario: X1 Three wrong set-up codes
    When "Ravi" signs in with their password
    And I select the Authenticator mode
    And I enter 3 wrong set-up codes
    Then I should see "Too many failed attempts. Please sign in again."
    And "Ravi" has two-factor off with no method

  # X2 — Error case: one wrong code, then the right one
  Scenario: X2 One wrong code then the right one
    When "Ravi" signs in with their password
    And I select the Authenticator mode
    And I enter 1 wrong set-up codes
    Then I should see "Invalid code. 2 attempt(s) remaining."
    When I enter a valid TOTP code and confirm
    Then I should see "Two-factor authentication is now enabled."
    And "Ravi" has two-factor on with the "authenticator" method
