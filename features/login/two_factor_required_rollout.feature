@rack_test
Feature: Required two-factor roll-out — banner, Set up now, Login as and the ops tasks
  Support and super users without a verified method see a banner from the moment ops sets the
  region's date (amber during the notice, red once it is reached), with a Set up now button that
  signs them out into the set-up flow. Login as needs the support user's own verified method once
  the date is reached. Ops measures progress with a counts-only report and, on the date, ends the
  remember-me cookies and website-made tokens of anyone still unverified.
  Design: openspec/changes/require-2fa-privileged-roles (business-rules.md §2, H4–H8, E21–E29).

  Background:
    Given the required 2FA date is "2026-12-01"

  # ── Happy path ────────────────────────────────────────────────────────────────

  # H4 — Happy path: during the notice period a support user sees the amber banner with the date
  Scenario: H4 Notice banner
    Given it is "2026-11-20 10:00" in India
    And "Ravi" is signed in on the website
    When I open the dashboard
    Then I see the amber required 2FA banner "Two-factor authentication becomes required for your role (Support) on 01/12/2026."
    And the required 2FA banner explains why and how

  # H5 — Happy path: Set up now switches the flag on, signs out, and the next sign-in is the set-up
  Scenario: H5 Set up now
    Given it is "2026-11-20 10:00" in India
    And "Ravi" is signed in on the website
    When I open the dashboard
    And I press "Set up now" on the required 2FA banner
    Then I should see "Sign in again to set up two-factor authentication."
    And "Ravi" has two-factor on with no method
    When "Ravi" signs in with their password
    Then I should be on the 2FA mode selection page
    When I select the Authenticator mode
    And I enter a valid TOTP code and confirm
    Then I should see "Two-factor authentication is now enabled."
    And "Ravi" has two-factor on with the "authenticator" method

  # H6 — Happy path: a verified support user uses Login as after the date; the client's code is not asked
  Scenario: H6 Verified support uses Login as
    Given it is "2026-12-02 10:00" in India
    And "Anita" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Anita" is signed in on the website with their code
    When I use Login as on "Dev"
    Then I am acting as "Dev"

  # H7 — Happy path: the report prints counts per required role, and nothing that names a person
  Scenario: H7 Report shows counts only
    Given it is "2026-11-20 10:00" in India
    And the people "Ravi, Anita, Vikram, Sam, Meera" exist
    When ops runs "two_factor_required:report"
    Then the task prints "Stage: notice"
    And the task prints "Enforcement date: 2026-12-01"
    And the task prints "support: 3 active, 1 with a verified method, 2 without"
    And the task prints "super: 1 active, 0 with a verified method, 1 without"
    And the task prints "Distinct people without a verified method: 3"
    And the task prints "company_admin: not required"
    And the task prints no names or emails

  # H8 — Happy path: on the date, ops ends the remember-me cookies and website tokens of unverified users only
  Scenario: H8 Ending access for unverified users
    Given it is "2026-11-28 10:00" in India
    And the people "Ravi, Anita, Vikram, Sam" exist
    And "Ravi" has a remember-me cookie
    And "Ravi" has an API token "Ravi scripts"
    And "Anita" has a remember-me cookie
    And "Anita" has an API token "Anita reports"
    And it is "2026-12-01 09:00" in India
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

  # E21 — Edge case: a session that began before the date shows the red banner once the date is reached
  Scenario: E21 Required banner for an older session
    Given it is "2026-11-30 23:40" in India
    And "Ravi" is signed in on the website
    And it is "2026-12-01 00:20" in India
    When I open the dashboard
    Then I see the red required 2FA banner "Two-factor authentication is now required for your role. Set it up to keep using CapHive. Login as is unavailable until you do."
    And I see the red required 2FA banner "Required since 01/12/2026."
    And the required 2FA banner explains why and how

  # E22 — Edge case: no banner once the support user has a verified method
  Scenario: E22 Banner gone once verified
    Given it is "2026-11-20 10:00" in India
    And "Ravi" has set up the authenticator app
    And "Ravi" is signed in on the website with their code
    When I open the dashboard
    Then I see no required 2FA banner

  # E23 — Edge case: no banner while a support user acts as a client
  Scenario: E23 Banner hidden while acting as a client
    Given it is "2026-11-20 10:00" in India
    And "Ravi" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Ravi" is signed in on the website
    When I use Login as on "Dev"
    Then I am acting as "Dev"
    When I open the dashboard
    Then I see no required 2FA banner

  # E24 — Edge case: a company admin without two-factor never sees the banner
  Scenario: E24 No banner for a company admin
    Given it is "2026-12-02 10:00" in India
    And "Meera" is signed in on the website
    When I open the dashboard
    Then I see no required 2FA banner

  # E25 — Edge case: no date configured — no banner
  Scenario: E25 No banner with no date
    Given the required 2FA date is not set
    And it is "2026-11-20 10:00" in India
    And "Sam" is signed in on the website
    When I open the dashboard
    Then I see no required 2FA banner

  # E26 — Edge case: before the date Login as works for a support user without a method, as today
  Scenario: E26 Login as before the date
    Given it is "2026-11-20 10:00" in India
    And "Ravi" may Login as users of "Sahyadri Capital"
    And the people "Dev" exist
    And "Ravi" is signed in on the website
    When I use Login as on "Dev"
    Then I am acting as "Dev"

  # E27 — Edge case: the dry run only counts — the cookie and the token still work
  Scenario: E27 Ending access dry run
    Given it is "2026-11-28 10:00" in India
    And the people "Ravi, Vikram, Sam" exist
    And "Ravi" has a remember-me cookie
    And "Ravi" has an API token "Ravi scripts"
    And it is "2026-12-01 09:00" in India
    When ops runs "two_factor_required:end_unverified_access"
    Then the task prints "Would end access for 3 users"
    When "Ravi" comes back with only the remember-me cookie
    Then they are signed in from the cookie
    When the API token "Ravi scripts" reads "/funds.json"
    Then the API answers 200

  # E28 — Edge case: before the date the task refuses to change anything, even with EXECUTE=1
  Scenario: E28 Ending access before the date
    Given it is "2026-11-20 10:00" in India
    And the people "Ravi" exist
    And "Ravi" has an API token "Ravi scripts"
    When ops runs "two_factor_required:end_unverified_access" with EXECUTE=1
    Then the task prints "Enforcement date 2026-12-01 not reached — nothing changed"
    When the API token "Ravi scripts" reads "/funds.json"
    Then the API answers 200

  # E29 — Edge case: when everyone is set up the report shows zeros
  Scenario: E29 Report when everyone is set up
    Given it is "2026-11-20 10:00" in India
    And the people "Ravi, Anita, Vikram, Sam" exist
    And "Ravi" has set up the authenticator app
    And "Vikram" has set up the authenticator app
    And "Sam" has set up the authenticator app
    When ops runs "two_factor_required:report"
    Then the task prints "support: 3 active, 3 with a verified method, 0 without"
    And the task prints "super: 1 active, 1 with a verified method, 0 without"
    And the task prints "Distinct people without a verified method: 0"
