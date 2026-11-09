@rack_test
Feature: Required two-factor roll-out — Set up now, Login as and the ops tasks
  Two-factor is required for support and super users from the day it is deployed (user decision 2026-11-09:
  "there are very few support users and we can force it on day one") — no enforcement date, notice period or
  banner. A support or super user still signed in from before the deploy sees "Set up now" on their own user
  page, and Login as needs their own verified method. Ops measures progress with a counts-only report and, on
  deploy day, ends the remember-me cookies and website-made tokens of anyone still unverified.
  Design: openspec/changes/require-2fa-privileged-roles (business-rules.md §2, H4–H8, E27, E29).

  # ── Happy path ────────────────────────────────────────────────────────────────

  # H4 — Happy path: a support user still signed in from before the deploy sees Set up now on their own page
  Scenario: H4 Set up now offered on the user page
    Given "Ravi" still has a website session from before the deploy
    When I open my user page
    Then I see the "Required for your role" badge with a tooltip naming "Support"
    And I see the "Set up now" button

  # H5 — Happy path: Set up now switches the flag on, signs out, and the next sign-in is the set-up
  Scenario: H5 Set up now
    Given "Ravi" still has a website session from before the deploy
    When I open my user page
    And I press "Set up now" on my user page
    Then I should see "Sign in again to set up two-factor authentication."
    And "Ravi" has two-factor on with no method
    When "Ravi" signs in with their password
    Then I should be on the 2FA mode selection page
    When I select the Authenticator mode
    And I enter a valid TOTP code and confirm
    Then I should see "Two-factor authentication is now enabled."
    And "Ravi" has two-factor on with the "authenticator" method

  # H6 — Happy path: a verified support user uses Login as; the client's code is not asked
  Scenario: H6 Verified support uses Login as
    Given "Anita" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Anita" is signed in on the website with their code
    When I use Login as on "Dev"
    Then I am acting as "Dev"

  # H7 — Happy path: the report prints counts per required role, and nothing that names a person
  Scenario: H7 Report shows counts only
    Given the people "Ravi, Anita, Vikram, Sam, Meera" exist
    When ops runs "two_factor_required:report"
    Then the task prints "two-factor required for: support, super (from the deploy)"
    And the task prints "support: 3 active, 1 with a verified method, 2 without"
    And the task prints "super: 1 active, 0 with a verified method, 1 without"
    And the task prints "Distinct people without a verified method: 3"
    And the task prints "company_admin: not required"
    And the task prints no names or emails

  # H8 — Happy path: on deploy day, ops ends the remember-me cookies and website tokens of unverified users only
  Scenario: H8 Ending access for unverified users
    Given the people "Ravi, Anita, Vikram, Sam" exist
    And "Ravi" has a remember-me cookie
    And "Ravi" has an API token "Ravi scripts"
    And "Anita" has a remember-me cookie
    And "Anita" has an API token "Anita reports"
    And 1 minutes pass
    When ops runs "two_factor_required:end_unverified_access" with EXECUTE=1
    Then the task prints "Ended access for 3 users"
    When "Ravi" comes back with only the remember-me cookie
    Then they are sent to sign in
    When the API token "Ravi scripts" reads "/funds.json"
    Then the API answers 401
    When "Anita" comes back with only the remember-me cookie
    Then they are signed in from the cookie
    When the API token "Anita reports" reads "/funds.json"
    Then the API answers 200

  # ── Edge cases ────────────────────────────────────────────────────────────────

  # E22 — Edge case: no Set up now once the support user has a verified method
  Scenario: E22 No Set up now once verified
    Given "Ravi" has set up the authenticator app
    And "Ravi" is signed in on the website with their code
    When I open my user page
    Then I see no "Set up now" button

  # E24 — Edge case: a company admin without two-factor is not required to set it up
  Scenario: E24 Not required for a company admin
    Given "Meera" is signed in on the website
    When I open my user page
    Then I see no "Set up now" button

  # E27 — Edge case: the dry run only counts — the cookie and the token still work
  Scenario: E27 Ending access dry run
    Given the people "Ravi, Vikram, Sam" exist
    And "Ravi" has a remember-me cookie
    And "Ravi" has an API token "Ravi scripts"
    When ops runs "two_factor_required:end_unverified_access"
    Then the task prints "Would end access for 3 users"
    When "Ravi" comes back with only the remember-me cookie
    Then they are signed in from the cookie
    When the API token "Ravi scripts" reads "/funds.json"
    Then the API answers 200

  # E29 — Edge case: when everyone is set up the report shows zeros
  Scenario: E29 Report when everyone is set up
    Given the people "Ravi, Anita, Vikram, Sam" exist
    And "Ravi" has set up the authenticator app
    And "Vikram" has set up the authenticator app
    And "Sam" has set up the authenticator app
    When ops runs "two_factor_required:report"
    Then the task prints "support: 3 active, 3 with a verified method, 0 without"
    And the task prints "super: 1 active, 1 with a verified method, 0 without"
    And the task prints "Distinct people without a verified method: 0"
