@security @rack_test
Feature: Security event trail — sign-in, two-factor, account changes and the recorder (OWASP 2026-11 M11)
  Every sign-in through every door, every refused attempt, two-factor and account changes are recorded as
  append-only security events — who, which firm, which door, from which IP — so a firm and CapHive can see who got
  in. Recording never changes what the person sees, and never fails the sign-in: the event is queued, written
  directly when the queue is down, and only logged when both fail.
  Design: openspec/changes/security-event-trail (business-rules.md §1, §2, §5, §7 — H1–H15, H28, E1–E22,
  E33–E37, E46, E49, X3–X5).

  Background:
    Given the security cast "Rahul, Meera, Priya, Karan"

  # ── §1 Sign-in ──────────────────────────────────────────────────────────────

  # H1 — Happy path: a password-only website sign-in is one sign_in.succeeded, door web_password, with the firm and IP
  Scenario: H1 Website sign-in without two-factor
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then "Karan" ends up signed in
    And a security event "sign_in.succeeded" is recorded for "Karan" with:
      | door       | web_password       |
      | outcome    | success            |
      | firm       | Golden Angels Fund |
      | ip_address | 49.36.12.9         |
      | done by    | Karan              |

  # H2 — Happy path: a two-factor sign-in is exactly one success, door two_factor, written after the code
  Scenario: H2 Two-factor sign-in is one success after the code
    When "Priya" signs in on the website with the password "Gold3n-Angels!42"
    Then no security event "sign_in.succeeded" is recorded
    When "Priya" enters the right two-factor code
    Then exactly 1 security event "sign_in.succeeded" is recorded
    And a security event "sign_in.succeeded" is recorded for "Priya" with:
      | door | two_factor |

  # H3 — Happy path: an email sign-in link signs in through the magic_link door
  Scenario: H3 Email sign-in link
    When "Karan" opens a fresh sign-in link
    Then a security event "sign_in.succeeded" is recorded for "Karan" with:
      | door | magic_link |

  # H4 — Happy path: a password reset that signs the user in records password.changed and a password_reset sign-in
  Scenario: H4 Password reset signs in
    When "Karan" resets the password with a reset link
    Then a security event "password.changed" is recorded for "Karan"
    And a security event "sign_in.succeeded" is recorded for "Karan" with:
      | door | password_reset |

  # H5 — Happy path: the LP mobile app, password then code, records a mobile sign-in
  Scenario: H5 Mobile app sign-in
    Given a mobile investor "asha@sharmafo.in" of "Sharma Family Office" with fund manager "Golden Angels Fund"
    And "asha@sharmafo.in" has authenticator two-factor
    When "asha@sharmafo.in" signs in on the phone "Asha's iPhone" with password "password"
    Then no security event "sign_in.succeeded" is recorded
    When the phone "Asha's iPhone" enters the current authenticator code for "asha@sharmafo.in"
    Then a security event "sign_in.succeeded" is recorded for "asha@sharmafo.in" with:
      | door | mobile |

  # H6 — Happy path: the API token endpoint issuing a token is a sign-in through the api door
  Scenario: H6 API sign-in
    When "Karan" asks the token API for a token with the password "Gold3n-Angels!42"
    Then the request of "Karan" is answered with 200
    And a security event "sign_in.succeeded" is recorded for "Karan" with:
      | door | api |

  # H7 — Happy path: a region switch is recorded in the destination region with door cross_region
  @cross-region-cache @cross-region-login
  Scenario: H7 Region switch on the website
    Given the regions are "IN,US"
    And the current region is "IN"
    When "Rahul" arrives in "US" with a region-switch link
    Then a security event "sign_in.succeeded" is recorded for "Rahul" with:
      | door   | cross_region |
      | region | US           |
      | origin | IN           |

  # H8 — Happy path: the app's hand-off link to the website signs in through the mobile_handoff door
  @cross-region-cache @cross-region-login
  Scenario: H8 App to website hand-off
    When "Priya" opens an app-to-website hand-off link
    Then a security event "sign_in.succeeded" is recorded for "Priya" with:
      | door | mobile_handoff |

  # H9 — Happy path: connecting the Outlook add-in (a token for the add-in) is a mail_addin sign-in
  Scenario: H9 Outlook add-in
    When "Rahul" connects the Outlook add-in
    Then a security event "sign_in.succeeded" is recorded for "Rahul" with:
      | door | mail_addin |

  # H10 — Edge case: a plain sign-out is not recorded (user decision 2026-11-09); only a support visit's end is (H20)
  Scenario: H10 A plain sign-out records nothing
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    And "Karan" signs out of the website
    Then no security event "sign_out" is recorded
    And no security event "support.session_ended" is recorded

  # E1 — Edge case: a wrong password is sign_in.failed reason invalid for the account and its firm; the message is unchanged
  Scenario: E1 Wrong password
    When "Karan" signs in on the website with the password "wrong-password"
    Then "Karan" sees "Invalid email or password."
    And a security event "sign_in.failed" is recorded for "Karan" with:
      | door       | web_password       |
      | outcome    | failure            |
      | reason     | invalid            |
      | firm       | Golden Angels Fund |
      | ip_address | 49.36.12.9         |

  # E2 — Edge case: an unknown email has no account and no firm, only a digest of the typed email
  Scenario: E2 Unknown email
    When ghost@example.com tries to sign in on the website
    Then that "sign_in.failed" event has no account, no firm and only the digest of "ghost@example.com"

  # E3 — Edge case: a locked account with the right password is sign_in.failed reason locked (the page still says only "invalid")
  Scenario: E3 Locked account
    Given "Karan" was locked 1 minutes ago
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then a security event "sign_in.failed" is recorded for "Karan" with:
      | reason | locked |

  # E4 — Edge case: a switched-off account with the right password is sign_in.failed reason inactive
  Scenario: E4 Inactive account
    Given "Karan" is switched off as a user
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then a security event "sign_in.failed" is recorded for "Karan" with:
      | reason | inactive |

  # E5 — Edge case: a signed-out browser opening a page is sent to sign in, which is not a failed sign-in
  Scenario: E5 Expired session is not a failure
    When a signed-out browser opens the funds page
    Then no security event is recorded

  # E6 — Edge case: password right, code never entered — no success is recorded
  Scenario: E6 Password right, code never entered
    When "Priya" signs in on the website with the password "Gold3n-Angels!42"
    Then no security event "sign_in.succeeded" is recorded

  # E7 — Edge case: an expired email link is sign_in.failed, door magic_link, reason invalid_link
  Scenario: E7 Expired email link
    When "Karan" opens a sign-in link that expired
    Then a security event "sign_in.failed" is recorded with:
      | door    | magic_link   |
      | reason  | invalid_link |
      | account | none         |

  # E8 — Edge case: a support user not allowed by the mapping is refused delegation; recorded with the support user as Done by
  Scenario: E8 Support delegation refused
    Given the security cast "Anil"
    When "Anil" signs in on the website with the password "Gold3n-Angels!42"
    And "Anil" opens the sign-in link of "Karan" without a delegation
    Then a security event "sign_in.failed" is recorded for "Karan" with:
      | door    | magic_link         |
      | reason  | delegation_refused |
      | done by | Anil               |

  # E9 — Edge case: a wrong password on the app is sign_in.failed, door mobile
  Scenario: E9 Mobile wrong password
    Given a mobile investor "asha@sharmafo.in" of "Sharma Family Office" with fund manager "Golden Angels Fund"
    When "asha@sharmafo.in" signs in on the phone "Asha's iPhone" with password "wrong-password"
    Then a security event "sign_in.failed" is recorded for "asha@sharmafo.in" with:
      | door   | mobile  |
      | reason | invalid |

  # E10 — Edge case: the API refuses a two-factor user's correct password as today; recorded as reason two_factor_required
  Scenario: E10 API sign-in by a two-factor user
    When "Priya" asks the token API for a token with the password "Gold3n-Angels!42"
    Then the request of "Priya" is answered with 403
    And a security event "sign_in.failed" is recorded for "Priya" with:
      | door   | api                 |
      | reason | two_factor_required |

  # E11 — Edge case: an expired region-switch link is sign_in.failed, door cross_region, with the hand-off's reason
  @cross-region-cache @cross-region-login
  Scenario: E11 Region switch rejected
    Given the regions are "IN,US"
    And the current region is "IN"
    When "Rahul" arrives in "US" with a region-switch link that expired
    Then a security event "sign_in.failed" is recorded with:
      | door   | cross_region |
      | reason | expired      |

  # E12 — Edge case: an MCP request with a revoked token gets 401 as today and records door oauth, reason invalid
  Scenario: E12 MCP invalid token
    When an MCP request comes with a revoked token of "Rahul"
    Then the request of "Rahul" is answered with 401
    And a security event "sign_in.failed" is recorded with:
      | door   | oauth   |
      | reason | invalid |

  # E13 — Edge case: an MCP request with no token at all gets 401 and records nothing (a client not signed in yet)
  Scenario: E13 MCP missing token
    When an MCP request comes with no token
    Then the request of "Karan" is answered with 401
    And no security event is recorded

  # E14 — Edge case: a mail add-in token minted for another firm is refused as today; recorded as entity_mismatch
  Scenario: E14 Mail add-in token of another firm
    When the mail add-in calls with a token of "Rahul" minted for "Beta Capital"
    Then the request of "Rahul" is answered with 403
    And a security event "sign_in.failed" is recorded for "Rahul" with:
      | door   | mail_addin      |
      | reason | entity_mismatch |

  # ── §2 Two-factor and account ───────────────────────────────────────────────

  # H11 — Happy path: a wrong code is two_factor.code_failed attempt 1; the page message is unchanged
  Scenario: H11 Wrong code
    When "Priya" signs in on the website with the password "Gold3n-Angels!42"
    And "Priya" enters a wrong two-factor code
    Then "Priya" sees "Invalid code. 2 attempt(s) remaining."
    And a security event "two_factor.code_failed" is recorded for "Priya" with:
      | attempt         | 1     |
      | challenge_ended | false |
      | outcome         | failure |

  # H12 — Happy path: enrolling the authenticator records the method and the two-factor sign-in
  Scenario: H12 Enrol authenticator
    Given "Karan" has two-factor on with no method yet
    When "Karan" sets up the authenticator app at sign-in
    Then a security event "two_factor.method_set" is recorded for "Karan" with:
      | mode | authenticator |
    And a security event "sign_in.succeeded" is recorded for "Karan" with:
      | door | two_factor |

  # H13 — Happy path: an admin resetting a user's method records two_factor.method_reset, Done by the admin
  Scenario: H13 Admin resets the two-factor method
    When "Rahul" resets the two-factor method of "Priya"
    Then a security event "two_factor.method_reset" is recorded for "Priya" with:
      | done by | Rahul         |
      | from    | authenticator |

  # H14 — Happy path: a password change in the profile records password.changed, Done by the user
  Scenario: H14 Password changed in the profile
    When "Karan" changes their own password in the profile
    Then a security event "password.changed" is recorded for "Karan" with:
      | done by | Karan |

  # H15 — Happy path: a confirmed phone change keeps only the last two digits, before and after
  Scenario: H15 Phone changed
    When "Priya" confirms a new phone number ending "77"
    Then a security event "phone.changed" is recorded for "Priya" with:
      | from | **42 |
      | to   | **77 |

  # E15 — Edge case: the third wrong code ends the challenge — attempt 3, challenge_ended true
  Scenario: E15 Third wrong code ends the challenge
    When "Priya" signs in on the website with the password "Gold3n-Angels!42"
    And "Priya" enters a wrong two-factor code
    And "Priya" enters a wrong two-factor code
    And "Priya" enters a wrong two-factor code
    Then "Priya" sees "Too many failed attempts. Please sign in again."
    And exactly 3 security events "two_factor.code_failed" are recorded
    And a security event "two_factor.code_failed" is recorded for "Priya" with attempt 3 ending the challenge

  # E16 — Edge case: the 10th wrong code in an hour locks the account — account.locked reason too_many_codes
  @cross-region-cache
  Scenario: E16 Ten wrong codes in an hour lock the account
    Given "Priya" has already missed 9 two-factor codes this hour
    When "Priya" signs in on the website with the password "Gold3n-Angels!42"
    And "Priya" enters a wrong two-factor code
    Then a security event "account.locked" is recorded for "Priya" with:
      | reason | too_many_codes |

  # E17 — Edge case: the 6th wrong password locks the account — sign_in.failed and account.locked too_many_passwords
  Scenario: E17 Sixth wrong password locks the account
    Given "Karan" has failed 5 passwords in a row
    When "Karan" signs in on the website with the password "wrong-password"
    Then a security event "sign_in.failed" is recorded for "Karan"
    And a security event "account.locked" is recorded for "Karan" with:
      | reason | too_many_passwords |

  # E18 — Edge case: a lock that has expired is cleared at the next sign-in — account.unlocked by the system, then the sign-in
  Scenario: E18 Lock expires
    Given "Karan" was locked 6 minutes ago
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then a security event "account.unlocked" is recorded for "Karan" with:
      | done by | none |
    And a security event "sign_in.succeeded" is recorded for "Karan"

  # E19 — Edge case: two-factor switched off (since M8 only by the user, with password and code) records two_factor.disabled
  Scenario: E19 Two-factor switched off
    When "Priya" turns their own two-factor off with their password and code
    Then a security event "two_factor.disabled" is recorded for "Priya" with:
      | from    | true  |
      | to      | false |
      | done by | Priya |

  # E20 — Edge case: a reset request for an unknown email keeps only the digest; the answer is unchanged
  Scenario: E20 Reset request for an unknown email
    When a password reset is requested for "ghost@example.com"
    Then "Karan" sees "If your email address exists in our database"
    And that "password.reset_requested" event has no account, no firm and only the digest of "ghost@example.com"

  # E21 — Edge case: CapHive support switching one user off in the admin console records account.deactivated, door admin
  Scenario: E21 Deactivate one user
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" switches "Karan" off in the admin console
    Then a security event "account.deactivated" is recorded for "Karan" with:
      | door    | admin |
      | done by | Anil  |

  # E22 — Edge case: CapHive support deactivating a whole firm records one firm.deactivated, and no per-user rows
  Scenario: E22 Deactivate a firm
    Given the security cast "Anil, Sara"
    When "Anil" deactivates the firm "Beta Capital"
    Then a security event "firm.deactivated" is recorded with:
      | firm    | Beta Capital |
      | done by | Anil         |
    And no security event "account.deactivated" is recorded

  # ── §5 Recorder and writer ──────────────────────────────────────────────────

  # H28 — Happy path: the event is queued and written once, with occurred_at the moment of the sign-in
  Scenario: H28 Queued write
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then exactly 1 security event "sign_in.succeeded" is recorded
    And that "sign_in.succeeded" event happened just now

  # E33 — Edge case: the same write job run again (a Sidekiq retry) leaves one row
  Scenario: E33 Retry is idempotent
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    And the write job for that "sign_in.succeeded" event runs again
    Then exactly 1 security event "sign_in.succeeded" is recorded

  # E34 — Edge case: the queue is down — the user is signed in normally and the event is written directly
  Scenario: E34 Queue down at sign-in
    Given the security event queue is down
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then "Karan" ends up signed in
    And a security event "sign_in.succeeded" is recorded for "Karan"

  # E35 — Edge case: an unknown kind saves nothing and is logged; the caller is not affected
  Scenario: E35 Unknown kind
    Given the application log is watched for security events
    When a hook records the unknown kind "bogus"
    Then the recorder returned nothing and logged "record_failed"
    And no security event is recorded

  # E36 — Edge case: a detail key not on the kind's allowlist is dropped
  Scenario: E36 Detail not on the allowlist
    When a role grant to "Karan" is recorded with an extra token detail
    Then that "role.granted" event holds only the detail "role"

  # E37 — Edge case: a 900-character browser name is stored at 255 characters
  Scenario: E37 Long user agent
    When "Karan" signs in on the website with a 900-character browser name
    Then that "sign_in.succeeded" event stores a 255-character browser name

  # X3 — Error case: queue and table both down — the user is signed in, and one log line keeps the event
  Scenario: X3 Everything down
    Given the application log is watched for security events
    And the security event queue is down
    And the security event table cannot be written
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    Then "Karan" ends up signed in
    And one security log line names "sign_in.succeeded" and the user "Karan" and the IP

  # X4 — Error case: a saved event cannot be edited
  Scenario: X4 Event edit attempt
    When "Karan" signs in on the website with the password "Gold3n-Angels!42"
    And "Karan" signs out of the website
    And someone tries to change that "sign_in.succeeded" event
    Then the security event is refused as read-only

  # X5 — Error case: no password, reset token, bearer token, cookie or link is ever stored in an event
  Scenario: X5 Secrets are never stored
    When "Karan" signs in on the website with the password "wrong-password"
    And "Karan" signs in on the website with the password "Gold3n-Angels!42"
    And "Karan" resets the password with a reset link
    And an MCP request comes with a revoked token of "Rahul"
    And "Karan" opens a fresh sign-in link
    Then no security event holds a secret

  # ── §7 Never affects the user ───────────────────────────────────────────────

  # E46 — Edge case: the wrong-password and locked messages are exactly as before
  Scenario: E46 Sign-in messages unchanged
    Given "Meera" was locked 1 minutes ago
    When "Karan" signs in on the website with the password "wrong-password"
    And "Meera" signs in on the website with the password "Gold3n-Angels!42"
    Then "Karan" sees "Invalid email or password."
    And "Meera" sees "Invalid email or password."

  # E49 — Edge case: the recorder raising inside the Warden hook changes nothing for the user
  Scenario: E49 Recorder raises in the Warden hook
    Given the security event recorder is broken
    When "Karan" signs in on the website with the password "wrong-password"
    Then "Karan" sees "Invalid email or password."
    And no security event is recorded
