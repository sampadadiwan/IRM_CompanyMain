@security @rack_test
Feature: Security Events screen, admin alerts, weekly pack and retention (OWASP 2026-11 M11)
  Company admins see their own firm's security events — with filters, cards that count the filtered rows, and a
  spreadsheet by email — and are emailed when someone gets or loses admin or approver power, or CapHive support
  signs in. CapHive's support mailbox gets every region's events each Monday; events older than 13 months are
  removed every night. Every screen element and email explains why it is there and what to do.
  Design: openspec/changes/security-event-trail (business-rules.md §6 — H29–H35, E38–E44, E50, X12).

  Background:
    Given today is "2026-11-09 12:00" for the security trail
    And the security cast "Rahul, Meera, Priya, Karan, Sara"

  # ── The screen ──────────────────────────────────────────────────────────────

  # H29 — Happy path: a company admin sees only her firm's events, newest first, from the last 30 days
  Scenario: H29 Admin list
    Given security events in the trail:
      | when             | firm               | kind              | outcome | account | details              |
      | 2026-11-09 10:13 | Golden Angels Fund | sign_in.failed    | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-09 10:22 | Golden Angels Fund | role.granted      | success | Rahul   | {"role":"approver"}  |
      | 2026-11-09 10:30 | Beta Capital       | sign_in.succeeded | success | Sara    |                      |
      | 2026-09-01 09:00 | Golden Angels Fund | sign_in.succeeded | success | Karan   |                      |
    When "Meera" opens Security Events
    Then "Meera" sees the Security Events list with 2 rows
    And the Security Events list of "Meera" has the events "Role granted: Approver; Sign-in failed"

  # H30 — Happy path: Group = Access keeps only role and support-switch rows, and the cards count the same rows
  Scenario: H30 Filter by group
    Given security events in the trail:
      | when             | kind                   | outcome | account | details              |
      | 2026-11-09 10:13 | sign_in.failed         | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-09 10:22 | role.granted           | success | Rahul   | {"role":"approver"}  |
      | 2026-11-09 10:25 | support_access.enabled | success | Rahul   |                      |
    When "Meera" opens Security Events with "q[category_eq]=access"
    Then the Security Events list of "Meera" has the events "Support access switched on; Role granted: Approver"
    And "Meera" sees the security card "Role changes" at 1
    And "Meera" sees the security card "Failed sign-ins" at 0

  # H31 — Happy path: Download says what happens and emails a spreadsheet of the firm's filtered rows
  Scenario: H31 Download
    Given security events in the trail:
      | when             | firm               | kind              | account |
      | 2026-11-09 10:15 | Golden Angels Fund | sign_in.succeeded | Priya   |
      | 2026-11-09 10:16 | Golden Angels Fund | api_token.created | Priya   |
      | 2026-11-09 10:30 | Beta Capital       | sign_in.succeeded | Sara    |
    When "Meera" downloads the security events with "q[kind_eq]=sign_in.succeeded"
    Then "Meera" sees "Your request is being processed. You will receive an email shortly."
    And "Meera" is emailed a security spreadsheet with 1 event row of "Golden Angels Fund"

  # E38 — Edge case: nothing matches — the empty state says what to try
  Scenario: E38 Empty state
    When "Meera" opens Security Events with "q[kind_eq]=firm.deactivated"
    Then "Meera" sees the help "No security events in this period. Widen the dates or clear the filter."

  # E39 — Edge case: a period longer than 13 months is shortened, and the screen says so
  Scenario: E39 Period over 13 months
    When "Meera" opens Security Events with "from=2025-01-01&to=2026-11-09"
    Then "Meera" sees the help "The period was shortened to the last 13 months"

  # E40 — Edge case: the cards equal the filtered rows — 3 failed sign-ins and 2 role changes
  Scenario: E40 Cards equal the rows
    Given security events in the trail:
      | when             | kind           | outcome | account | details              |
      | 2026-11-09 10:13 | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-09 10:14 | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-09 10:15 | sign_in.failed | failure | Karan   | {"reason":"invalid"} |
      | 2026-11-09 10:22 | role.granted   | success | Rahul   | {"role":"approver"}  |
      | 2026-11-09 11:02 | role.revoked   | success | Rahul   | {"role":"approver"}  |
    When "Meera" opens Security Events
    Then "Meera" sees the Security Events list with 5 rows
    And "Meera" sees the security card "Failed sign-ins" at 3
    And "Meera" sees the security card "Role changes" at 2
    And "Meera" sees the security card "Support access" at 0
    And "Meera" sees the security card "Exports" at 0

  # E52 — Edge case: clicking an Event filters the list to that kind and keeps the other filters; the chip brings every kind back
  Scenario: E52 Click an event to filter by it
    Given security events in the trail:
      | when             | kind              | account |
      | 2026-11-09 10:13 | sign_in.succeeded | Priya   |
      | 2026-11-09 10:20 | api_token.revoked | Priya   |
      | 2026-11-09 10:30 | api_token.revoked | Karan   |
    When "Meera" opens Security Events with "account=Priya"
    And "Meera" clicks the event "API key revoked"
    Then the Security Events list of "Meera" has the events "API key revoked"
    And the Event filter of "Meera" shows "API key revoked" with the account "Priya"
    When "Meera" clears the event filter
    Then the Security Events list of "Meera" has the events "API key revoked; Signed in"

  # U.1 — Edge case: the screen explains itself — why it exists, what each card and column means, what Download does
  Scenario: U1 The screen explains itself
    Given security events in the trail:
      | when             | kind           | outcome | account | details              |
      | 2026-11-09 10:13 | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
    When "Meera" opens Security Events
    Then "Meera" sees no general help line above the cards
    And the What to do popup of the "Sign-in failed" row of "Meera" says "One or two failed sign-ins are usually a typo"
    And the What to do popup of the "Sign-in failed" row of "Meera" says "filter by the IP to see every account it tried"
    And "Meera" sees a tooltip "Click the bulb for this event"
    And "Meera" sees a tooltip "nobody can edit or delete them"
    And "Meera" sees a tooltip "Emails you a spreadsheet of every event the current filter shows"
    And "Meera" sees a tooltip "wrong passwords, refused links and refused tokens"
    And "Meera" sees a tooltip "How the person reached CapHive"
    And "Meera" sees a tooltip "Reason: invalid"
    And the security menu entry is shown to "Meera"
    And the security menu entry is not shown to "Karan"

  # U.1b — Edge case: each row opens a styled popup saying what happened, when it is normal and what to do
  #   (user requests 2026-11-09); a kind with nothing to check says so instead of an action
  Scenario: U1b Each row opens a What to do popup
    Given security events in the trail:
      | when             | kind                 | account |
      | 2026-11-09 10:13 | support.signed_in_as | Priya   |
      | 2026-11-09 10:20 | mobile_device.revoked | Priya   |
    When "Meera" opens Security Events
    Then every row's What to do button of "Meera" opens its own popup
    And the What to do popup of the "Support signed in as" row of "Meera" says "CapHive support visiting your firm's account"
    And the What to do popup of the "Support signed in as" row of "Meera" says "If nobody in your firm asked for help"
    And the What to do popup of the "Phone signed out" row of "Meera" says "No action needed"
    And every security event kind has its own What to do suggestion

  # E44 — Edge case: a value that looks like a formula is kept as text in the spreadsheet
  Scenario: E44 Formula-looking value in the spreadsheet
    Given security events in the trail:
      | when             | kind              | account | browser                          |
      | 2026-11-09 10:15 | sign_in.succeeded | Priya   | =HYPERLINK("http://x.test","y") |
    When "Meera" downloads the security events with "q[kind_eq]=sign_in.succeeded"
    Then "Meera" is emailed a security spreadsheet with 1 event row of "Golden Angels Fund"
    And the spreadsheet's browser cell starts with "'="

  # ── Admin alerts ────────────────────────────────────────────────────────────

  # H32 — Happy path: a self-granted approver role emails and bells every company admin, the granter included
  Scenario: H32 Approver alert
    When "Rahul" saves the roles of "Rahul" as "company_admin, approver"
    Then "Rahul" gets the security alert "Approver role given to Rahul Mehta"
    And "Meera" gets the security alert "Approver role given to Rahul Mehta"
    And the security alert says "Nov 09, 2026"
    And the security alert says "Why you got this:"
    And the security alert says "If you did not,"

  # H33 — Happy path: CapHive support signing in as a user is recorded and shown in the admins' bell, never emailed (decision 2026-11-09)
  Scenario: H33 Support sign-in alert is bell only
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" uses Login as on "Priya"
    Then a security event "support.signed_in_as" is recorded for "Priya"
    And "Meera" gets the bell "CapHive support (Anil Kumar) signed in as Priya Shah" and no email
    And "Rahul" gets the bell "CapHive support (Anil Kumar) signed in as Priya Shah" and no email

  # E41 — Edge case: a role other than admin or approver (here investor) granted by an import alerts nobody
  Scenario: E41 No alert for an ordinary role grant
    When an import run by "Rahul" gives "Karan" the role "investor"
    Then a security event "role.granted" is recorded for "Karan"
    And no security alert is sent

  # E42 — Edge case: a support switch into the firm is recorded and shown once in the bell, never emailed (decision 2026-11-09); the company_admin grant it makes alerts nobody
  Scenario: E42 Firm switch alert is bell only
    Given the security cast "Anil"
    And "Anil" supports the firm "Golden Angels Fund"
    When "Anil" switches into "Golden Angels Fund" and back
    Then a security event "support.firm_switched" is recorded for "Anil"
    And "Meera" gets the bell "CapHive support (Anil Kumar) switched into Golden Angels Fund" and no email
    And "Rahul" gets the bell "CapHive support (Anil Kumar) switched into Golden Angels Fund" and no email

  # E51 — Edge case: the firm's own "Enable support" switch still alerts by email and bell (the support-visit change is bell only)
  Scenario: E51 Enable support switch still emails
    Given "Rahul" has Enable support switched off
    When "Rahul" turns on Enable support on their own profile
    Then "Rahul" gets the security alert "CapHive support access switched on for Rahul Mehta"
    And "Meera" gets the security alert "CapHive support access switched on for Rahul Mehta"
    And the security alert says "Why you got this:"

  # X12 — Error case: a firm with no active admin — the event is saved, no email, no error
  Scenario: X12 Firm with no active admin
    Given "Sara" is no longer an active user
    When an import run by "Sara" gives "Sara" the role "approver"
    Then a security event "role.granted" is recorded for "Sara"
    And no security alert is sent

  # ── Weekly pack and retention ───────────────────────────────────────────────

  # H34 — Happy path: Monday's pack for 02–08 Nov goes to the region's mailbox with five sheets
  Scenario: H34 Weekly pack
    Given the weekly pack goes to "support@caphive.com"
    And security events in the trail:
      | when             | firm               | kind           | outcome | account | details              |
      | 2026-11-02 00:10 | Golden Angels Fund | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-04 10:13 | Golden Angels Fund | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-04 10:14 | Golden Angels Fund | sign_in.failed | failure | Priya   | {"reason":"invalid"} |
      | 2026-11-05 10:22 | Golden Angels Fund | role.granted   | success | Rahul   | {"role":"approver"}  |
      | 2026-11-08 23:50 | Beta Capital       | data.exported  | success | Sara    |                      |
      | 2026-11-09 08:00 | Golden Angels Fund | sign_in.succeeded | success | Karan |                    |
    When the Monday security pack runs for "2026-11-09"
    Then "support@caphive.com" is emailed the pack "[IN] Security events 02 Nov – 08 Nov 2026" with the sheets "All, Failed sign-ins by account, Access, Support, Exports"
    And the pack's "All" sheet has 5 event rows
    And the pack's "Access" sheet has 1 event row
    And the pack's "Exports" sheet has 1 event row
    And the pack's failed sign-ins sheet counts 2 for "Priya" on "04/11/2026"

  # E50 — Edge case: a box without SECURITY_EVENTS_WEEKLY_TO sends nothing and logs a warning (spec "Setting missing")
  Scenario: E50 Weekly pack with no recipient set
    Given the weekly pack has no recipient set
    And the application log is watched for security events
    When the Monday security pack runs for "2026-11-09"
    Then no security pack is emailed
    And the security log says "weekly_pack_skipped"

  # H35 — Happy path: the nightly purge removes events older than 13 months and keeps newer ones
  Scenario: H35 Purge
    Given security events in the trail:
      | when             | kind              | account |
      | 2025-10-08 10:00 | sign_in.succeeded | Karan   |
      | 2025-10-10 10:00 | sign_in.succeeded | Karan   |
    When the nightly security purge runs
    Then the security trail keeps the events of "2025-10-10 10:00" and not "2025-10-08 10:00"

  # E43 — Edge case: exactly 13 months old is kept; one second older is removed
  Scenario: E43 Purge boundary
    Given security events in the trail:
      | when                | kind              | account |
      | 2025-10-09 12:00:00 | sign_in.succeeded | Karan   |
      | 2025-10-09 11:59:59 | sign_in.succeeded | Karan   |
    When the nightly security purge runs
    Then the security trail keeps the events of "2025-10-09 12:00:00" and not "2025-10-09 11:59:59"
