# Security Event Trail — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the
> design's UI journeys (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | staging_in (52.66.163.132); IN region only — there is no staging US |
| Accounts | Rahul Mehta, Meera Iyer (company admins, Golden Angels Fund); Karan Shah (employee); Priya Shah (LP, two-factor by WhatsApp, phone ending 42); Anil Kumar (CapHive support, mapped to Golden Angels with Login as allowed); Divya Rao (super) |
| Second entity | Beta Capital with Sara Khan (company admin) |
| Seed data | An API key "Zapier sync" for Rahul (create in Profile › API tokens); a folder with 2 documents in Golden Angels; Priya's phone signed in to the LP app |
| How to read results | Unless the row says otherwise, open **Settings › Security Events** (as Divya to see every firm, or as Rahul for Golden Angels only) and look for the newest row. Rows appear within a minute (background queue). |
| Background work | Recording, alerts and downloads run in the background within a minute. The weekly pack (Monday 07:00) and the nightly clean-up need a developer to run them now. |
| Rows marked "Ask a developer" | Fault-injection rows; the developer reports the result and the tester records Pass/Fail. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Website sign-in, no 2FA | Karan, no 2FA | 1. correct password 2. Open Settings › Security Events as Divya (super) and find the row | one "Sign-in", door `web_password`, firm 18, IP, UA | | |
| ☐ | H2 | 2FA sign-in is one success | Priya, 2FA | 1. correct password, then correct code 2. Open Settings › Security Events as Divya (super) and find the row | exactly one "Sign-in", door `two_factor`, written after the code | | |
| ☐ | H3 | Email link | Karan has a fresh magic link | 1. opens it 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `magic_link` | | |
| ☐ | H4 | Password reset signs in | Karan, no 2FA, reset link | 1. sets new password 2. Open Settings › Security Events as Divya (super) and find the row | "Password changed" + "Sign-in" door `password_reset` | | |
| ☐ | H5 | Mobile app | Priya on the app | 1. password + code 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `mobile` | | |
| ☐ | H6 | API sign-in | Karan, no 2FA | 1. `POST /users/tokens/sign_in` 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `api` | | |
| ☐ | H7 | Region switch (web) | Rahul with regions IN,US | 1. valid cross-site link 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `cross_region` in the destination region | | |
| ☐ | H8 | App → website hand-off | Priya on the app | 1. valid hand-off link 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `mobile_handoff` | | |
| ☐ | H9 | Outlook add-in | Rahul signed in | 1. connects the add-in 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in", door `mail_addin` | | |
| ☐ | H10 | Plain sign-out records nothing | Karan signed in | 1. he signs out 2. Open Settings › Security Events as Divya (super) and filter by Karan | No "Signed out" row (plain sign-outs are not recorded); his sign-in is there | |
| ☐ | H11 | Wrong code | Priya at the code page | 1. wrong code 2. Open Settings › Security Events as Divya (super) and find the row | "Two-factor code wrong" attempt 1; message unchanged | | |
| ☐ | H12 | Enrol authenticator | Karan with 2FA on, no method | 1. completes enrolment 2. Open Settings › Security Events as Divya (super) and find the row | "Two-factor method set" mode `authenticator` + "Sign-in" door `two_factor` | | |
| ☐ | H13 | Admin resets method | Rahul on Priya's page | 1. Reset two-factor 2. Open Settings › Security Events as Divya (super) and find the row | "Two-factor method reset", actor Rahul, user Priya | | |
| ☐ | H14 | Password changed in profile | Karan | 1. changes password 2. Open Settings › Security Events as Divya (super) and find the row | "Password changed", actor Karan | | |
| ☐ | H15 | Phone changed | Priya | 1. confirms new number ending 77 2. Open Settings › Security Events as Divya (super) and find the row | "Phone changed" details `{from: "**42", to: "**77"}` | | |
| ☐ | H16 | Self-grant approver | Rahul | 1. ticks Approver on himself, Save 2. Open Settings › Security Events as Divya (super) and find the row | "Role granted" role `approver`, user = actor = Rahul | | |
| ☐ | H17 | Revoke approver | Rahul is approver | 1. Meera unticks it 2. Open Settings › Security Events as Divya (super) and find the row | "Role revoked", actor Meera | | |
| ☐ | H18 | Support switch on | `enable_support` off | 1. Rahul turns it on 2. Open Settings › Security Events as Divya (super) and find the row | "Support access enabled" from false to true | | |
| ☐ | H19 | Support Login as | Anil | 1. Login as Priya 2. Open Settings › Security Events as Divya (super) and find the row | "Support signed in as user", actor Anil, user Priya, firm 18 | | |
| ☐ | H20 | Support session ends | H19 | 1. Anil signs out 2. Open Settings › Security Events as Divya (super) and find the row | "Support session ended", firm 18 | | |
| ☐ | H21 | Firm switch and back | Anil | 1. switches into firm A, then reverts 2. Open Settings › Security Events as Divya (super) and find the row | "Support switched into firm" then "Support switched back", firm 18 | | |
| ☐ | H22 | API key created | Rahul | 1. creates "Zapier sync" 2. Open Settings › Security Events as Divya (super) and find the row | "API key created" name "Zapier sync"; the token string appears nowhere in the row | | |
| ☐ | H23 | API key revoked | H22 | 1. revokes it 2. Open Settings › Security Events as Divya (super) and find the row | "API key revoked" | | |
| ☐ | H24 | Mobile device revoked | Priya's phone | 1. she signs it out from the website 2. Open Settings › Security Events as Divya (super) and find the row | "Mobile device revoked" reason `website_sign_out` | | |
| ☐ | H25 | Connected app authorised | Rahul | 1. approves an MCP client on the OAuth screen 2. Open Settings › Security Events as Divya (super) and find the row | "Connected app authorised" app name, scopes | | |
| ☐ | H26 | Spreadsheet download | Rahul | 1. downloads Capital Calls as xlsx 2. Open Settings › Security Events as Divya (super) and find the row | "Data exported" details `capital_calls#index (xlsx)` | | |
| ☐ | H27 | Folder download | Rahul | 1. downloads a folder 2. Open Settings › Security Events as Divya (super) and find the row | "Data exported" details folder name | | |
| ☐ | H28 | Queued write | Sidekiq up | 1. Karan signs in 2. Open Settings › Security Events as Divya (super) and find the row | job enqueued; row appears once with `occurred_at` = sign-in time | | |
| ☐ | H29 | Admin list | firm A and B events | 1. Meera opens Security Events 2. Open Settings › Security Events as Divya (super) and find the row | only firm 18 rows, newest first, last 30 days | | |
| ☐ | H30 | Filter by group | H29 | 1. Group = Access 2. Open Settings › Security Events as Divya (super) and find the row | role + support-switch rows only; cards recount | | |
| ☐ | H31 | Download | H29 | 1. Download 2. Open Settings › Security Events as Divya (super) and find the row | flash "Your request is being processed. You will receive an email shortly."; email with xlsx of firm 18's filtered rows | | |
| ☐ | H32 | Approver alert | H16 | 1. job runs 2. Open Settings › Security Events as Divya (super) and find the row | Rahul and Meera get "Approver role given to Rahul Mehta"; date `Nov 09, 2026` | | |
| ☐ | H33 | Support sign-in alert: bell only (changed 2026-11-09) | H19 | 1. job runs 2. Open Settings › Security Events as Meera and find the row 3. Check Meera's and Rahul's bell and inbox | the "Support signed in as" row is there; the bell shows "CapHive support (Anil Kumar) signed in as Priya Shah"; **no** email arrives | | |
| ☐ | H34 | Weekly pack | events 02–08 Nov | 1. Ask a developer to run the weekly pack job now (or wait for Monday 07:00); open the email | support@caphive.com gets "[IN] Security events…" xlsx with 5 sheets; "Failed sign-ins by account" counts per account per day | | |
| ☐ | H35 | Purge | events on 08 Oct 2025 and 10 Oct 2025 | 1. Ask a developer to create the two dated events and run the clean-up job now | the 08 Oct 2025 row removed; the 10 Oct 2025 row kept | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Wrong password | Karan | 1. wrong password 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" reason `invalid`, user Karan, firm 18; message unchanged | | |
| ☐ | E2 | Unknown email | ghost@example.com | 1. any password 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed", `entity_id` NULL, `user_id` NULL, `identifier_digest` = SHA-256 of the email; email not stored | | |
| ☐ | E3 | Locked account | Karan locked | 1. correct password 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" reason `locked` | | |
| ☐ | E4 | Inactive account | Karan `active=false` | 1. correct password 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" reason `inactive` | | |
| ☐ | E5 | Expired session is not a failure | signed-out browser | 1. `GET /funds` 2. Open Settings › Security Events as Divya (super) and find the row | redirected to sign-in; **no** event | | |
| ☐ | E6 | Password right, code never entered | Priya | 1. correct password, closes the tab 2. Open Settings › Security Events as Divya (super) and find the row | no "Sign-in" | | |
| ☐ | E7 | Expired email link | link older than 10 min | 1. opens it 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" door `magic_link` reason `invalid_link` | | |
| ☐ | E8 | Support delegation refused | Anil not in the mapping's `user_emails` | 1. support magic link 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" reason `delegation_refused`, actor Anil | | |
| ☐ | E9 | Mobile wrong password | Priya | 1. wrong password on the app 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" door `mobile` | | |
| ☐ | E10 | API sign-in by a 2FA user | Priya | 1. `POST /users/tokens/sign_in` 2. Open Settings › Security Events as Divya (super) and find the row | refused as today; "Sign-in failed" door `api` reason `two_factor_required` | | |
| ☐ | E11 | Region switch rejected | expired cross-site link | 1. opens it 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" door `cross_region`, reason from `reject_handoff` | | |
| ☐ | E12 | MCP invalid token | revoked OAuth token | 1. MCP request 2. Open Settings › Security Events as Divya (super) and find the row | 401 as today; "Sign-in failed" door `oauth` reason `invalid` | | |
| ☐ | E13 | MCP missing token | no Authorization header | 1. MCP request 2. Open Settings › Security Events as Divya (super) and find the row | 401 as today; **no** event | | |
| ☐ | E14 | Mail add-in wrong firm | add-in token of firm B user, firm A host | 1. request 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" door `mail_addin` reason `entity_mismatch` | | |
| ☐ | E15 | Third wrong code ends challenge | Priya, 2 misses | 1. third wrong code 2. Open Settings › Security Events as Divya (super) and find the row | "Two-factor code wrong" attempt 3, `challenge_ended: true` | | |
| ☐ | E16 | 10 misses in an hour lock | Priya, 9 misses | 1. 10th miss 2. Open Settings › Security Events as Divya (super) and find the row | "Account locked" reason `too_many_codes` | | |
| ☐ | E17 | 6th wrong password locks | Karan, 5 failures | 1. 6th 2. Open Settings › Security Events as Divya (super) and find the row | "Sign-in failed" + "Account locked" reason `too_many_passwords` | | |
| ☐ | E18 | Lock expires | Karan locked 6 min ago (`unlock_in` 5 min) | 1. correct password 2. Open Settings › Security Events as Divya (super) and find the row | "Account unlocked" actor system + "Sign-in" | | |
| ☐ | E19 | 2FA switched off in admin console | Priya | 1. super unticks two-factor 2. Open Settings › Security Events as Divya (super) and find the row | "Two-factor disabled", door `admin` | | |
| ☐ | E20 | Reset request, unknown email | ghost@example.com | 1. Forgot password 2. Open Settings › Security Events as Divya (super) and find the row | "Password reset requested", no user, digest only; response unchanged | | |
| ☐ | E21 | Deactivate one user | Karan | 1. super sets inactive 2. Open Settings › Security Events as Divya (super) and find the row | "Account deactivated" | | |
| ☐ | E22 | Deactivate a firm | firm B, 4 users | 1. As Divya, deactivate firm B from the admin console; check the list | exactly one "Firm deactivated" for 31, no per-user rows | | |
| ☐ | E23 | Employee by import | user import with role employee | 1. import runs 2. Open Settings › Security Events as Divya (super) and find the row | "Role granted" employee, door `system`, actor = importer; no alert | | |
| ☐ | E24 | Rolled-back grant | grant inside a transaction that raises | 1. Ask a developer to run a role grant inside a transaction that is rolled back, then check the list | no event | | |
| ☐ | E25 | Removing a role not held | Karan not approver | 1. Rahul saves Karan unchanged (`remove_role(:approver)` no-op) 2. Open Settings › Security Events as Divya (super) and find the row | no event | | |
| ☐ | E26 | Investor role via investor access | new investor access | 1. approved 2. Open Settings › Security Events as Divya (super) and find the row | "Role granted" investor; no alert | | |
| ☐ | E27 | Support off for everyone | 3 users with support on | 1. Ask a developer to run 'disable support for all users'; check the list as Divya | exactly one "Support access disabled" door `system`, no firm | | |
| ☐ | E28 | Actions while impersonating | H19 | 1. Anil, as Priya, changes her phone 2. Open Settings › Security Events as Divya (super) and find the row | "Phone changed" with `impersonator_id` = Anil | | |
| ☐ | E29 | Support via magic link | Anil, mapping allows | 1. support `no_password_login` for Priya 2. Open Settings › Security Events as Divya (super) and find the row | "Support signed in as user" | | |
| ☐ | E30 | Refused xlsx | Karan lacks access | 1. requests an xlsx 2. Open Settings › Security Events as Divya (super) and find the row | refused as today; no event | | |
| ☐ | E31 | Firm data dump | super | 1. ad-hoc dump of firm A 2. Open Settings › Security Events as Divya (super) and find the row | "Data exported" details `entity_db_dump` | | |
| ☐ | E32 | Audit download | Rahul | 1. downloads the Audit Trail 2. Open Settings › Security Events as Divya (super) and find the row | "Data exported" details `audits#index (xlsx)` | | |
| ☐ | E33 | Retry is idempotent | job ran once | 1. Ask a developer to re-run the same recording job for one event, then check the list | still one row; one alert at most | | |
| ☐ | E34 | Queue down | enqueue raises | 1. Ask a developer to stop the background queue; sign in as Karan; check the list | signed in normally; row inserted inline | | |
| ☐ | E35 | Unknown kind | a hook passes `"bogus"` | 1. Ask a developer to record an unknown event type; check the action still completes | nothing saved; warn logged; action unaffected | | |
| ☐ | E36 | Detail not allowlisted | "Role granted" with extra `token:` key | 1. Ask a developer to record a role grant with an extra 'token' detail; open the row tooltip | `details` holds `role` only | | |
| ☐ | E37 | Long user agent | 900-char UA | 1. Sign in with a browser extension that sets a 900-character user agent (or ask a developer); open the row | `user_agent` stored at 255 chars | | |
| ☐ | E38 | Empty state | filter matches nothing | 1. apply 2. Open Settings › Security Events as Divya (super) and find the row | "No security events in this period. Widen the dates or clear the filter." | | |
| ☐ | E39 | Period over 13 months | from 01 Jan 2025 | 1. apply 2. Open Settings › Security Events as Divya (super) and find the row | clamped to 13 months; flash says so | | |
| ☐ | E40 | Cards = rows | 3 failed sign-ins, 2 role rows | 1. open 2. Open Settings › Security Events as Divya (super) and find the row | cards 3 and 2 equal the filtered rows | | |
| ☐ | E41 | No alert for employee | E23 | 1. job runs 2. Open Settings › Security Events as Divya (super) and find the row | no email or bell | | |
| ☐ | E42 | Firm switch alert: bell only (changed 2026-11-09) | H21 | 1. job runs 2. Open Settings › Security Events as Divya (super) and find the row 3. Check the firm admins' bell and inbox | one bell "support switched into"; **no** email; the `company_admin` grant to Anil alerts nobody | | |
| ☐ | E51 | "Enable support" switch still alerts | Rahul has support off | 1. Rahul ticks Enable support and saves 2. Check Rahul's and Meera's inbox and bell | both get "Security alert: CapHive support access switched on for Rahul Mehta" with why / what to do | | |
| ☐ | E52 | Click an Event to filter | Meera filtered by account | 1. Click "Signed out" in the Event column 2. Check the Filter panel and the Download link 3. Click the "× Signed out" chip | only that kind's rows, other filters kept, Event selected; the chip shows every kind again; the ⓘ beside an event does not filter | | |
| ☐ | E43 | Purge boundary | rows at exactly 13 months and 13 months + 1 s | 1. Ask a developer to create the two boundary events and run the clean-up job now | exactly-13-months row kept; older removed | | |
| ☐ | E44 | Formula-looking value in xlsx | user agent `=HYPERLINK(...)` | 1. download 2. Open Settings › Security Events as Divya (super) and find the row | cell starts with `'` | | |
| ☐ | E45 | Support and super scope | Anil mapped to A; Divya super | 1. each opens the list 2. Open Settings › Security Events as Divya (super) and find the row | Anil: firm 18 only; Divya: all firms + NULL-firm rows (E2) | | |
| ☐ | E46 | Sign-in messages unchanged | E1, E3 | 1. as there 2. Open Settings › Security Events as Divya (super) and find the row | "Invalid Email or password." / locked message exactly as before | | |
| ☐ | E47 | Role save message unchanged | H16 | 1. as there 2. Open Settings › Security Events as Divya (super) and find the row | "User was successfully updated." | | |
| ☐ | E48 | Login as message unchanged | H19 | 1. as there 2. Open Settings › Security Events as Divya (super) and find the row | "Signed in as Priya Shah" | | |
| ☐ | E49 | Recorder raises in the Warden hook | recorder forced to raise | 1. Ask a developer to force recording to fail; sign in with a wrong password | same failure page and message | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Login as refused | Anil not allowed by `login_as?` | 1. Login as Priya 2. Open Settings › Security Events as Divya (super) and find the row | "You are not authorized to perform this action."; no "Support signed in as user" | | |
| ☐ | X2 | 11th live key refused | Rahul has 10 live keys | 1. creates one more 2. Open Settings › Security Events as Divya (super) and find the row | "You already have 10 live tokens — revoke one first"; no "API key created" | | |
| ☐ | X3 | Everything down | enqueue and insert both raise | 1. Ask a developer to stop the queue and block the event write; sign in as Karan; ask for the log line | signed in normally; one `[security_event]` warn line with kind, user id, IP | | |
| ☐ | X4 | Event edit attempt | a saved event | 1. Ask a developer to try editing a saved event from the console | `ActiveRecord::ReadOnlyRecord`; row unchanged | | |
| ☐ | X5 | Secret never stored | any event from H1–H27 | 1. inspect row 2. Open Settings › Security Events as Divya (super) and find the row | no password, code, token, signed id or session id in any column | | |
| ☐ | X6 | Employee refused | Karan | 1. `GET /security_events` 2. Open Settings › Security Events as Divya (super) and find the row | "You are not authorized to perform this action." | | |
| ☐ | X7 | Investor refused | Priya | 1. `GET /security_events` 2. Open Settings › Security Events as Divya (super) and find the row | same refusal | | |
| ☐ | X8 | Other firm by query | Sara (firm B) | 1. `GET /security_events?q[entity_id_eq]=18` 2. Open Settings › Security Events as Divya (super) and find the row | only firm 31 rows (`entity_id` not ransackable) | | |
| ☐ | X9 | Download re-scoped | Sara crafts download params for firm 18 | 1. download 2. Open Settings › Security Events as Divya (super) and find the row | xlsx holds only firm 31 rows | | |
| ☐ | X10 | Support without support enabled | firm A turns support off | 1. Anil opens list 2. Open Settings › Security Events as Divya (super) and find the row | no firm 18 rows | | |
| ☐ | X11 | No write routes | Rahul | 1. `DELETE /security_events/1`, `PATCH` 2. Open Settings › Security Events as Divya (super) and find the row | 404 routing error; row unchanged | | |
| ☐ | X12 | Firm with no active admin | firm B admin deactivated | 1. role grant in B 2. Open Settings › Security Events as Divya (super) and find the row | row saved; no email; no error | | |

---

## UI Journeys

Journey 1 = an admin reviews (design *What users see*); journey 2 = the admin alert; journey 3 = the weekly pack.

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Settings menu | Open as Meera | "Security Events" entry under "Audit Trail" | | |
| ☐ | J1.2 | Settings › Security Events | Open | ① title with ⓘ tooltip "Sign-ins, two-factor, role and support-access changes, keys and exports in your firm. Kept for 13 months."; ④ four cards; ⑥ table of the last 30 days, newest first | | |
| ☐ | J1.3 | Same | ② Filter → Group = Access → Apply | Only role and support-switch rows; cards recount; no full page reload | | |
| ☐ | J1.4 | Same | Hover the ⓘ next to "Role granted: Approver" | "Role: approver" | | |
| ☐ | J1.5 | Same | Hover the Door column ⓘ | "How the person reached CapHive" | | |
| ☐ | J1.6 | Same | ⑦ Next page | Next 25 rows; cards unchanged | | |
| ☐ | J1.7 | Same | ③ Download | "Your request is being processed. You will receive an email shortly."; email with a spreadsheet | | |
| ☐ | J1.8 | Same | Filter to Karan, a period with no events | "No security events in this period. Widen the dates or clear the filter." | | |
| ☐ | J2.1 | Email | Rahul ticks Approver on himself | Email "Approver role given to Rahul Mehta" to Rahul and Meera | | |
| ☐ | J2.2 | Email | Read body | Done by Rahul Mehta; When `Nov 09, 2026 10:22` style; From IP; button "Open Security Events" | | |
| ☐ | J2.3 | Bell | Open notifications | Same message; click opens Security Events | | |
| ☐ | J3.1 | Email (support@caphive.com) | Developer runs the weekly pack | Subject names the week; spreadsheet attached | | |
| ☐ | J3.2 | Spreadsheet | Open | Sheets: All events, Failed sign-ins by account, Access changes, Support access, Exports | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Company admin (Rahul) | Employee (Karan) | Approver (non-admin) | Investor (Priya) | CapHive support (Anil) | Super (Divya) | Other-entity admin (Sara) |
|---|---|---|---|---|---|---|---|---|
| R1 | See the Settings menu entry | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ (own firm) |
| R2 | Open Security Events | ✓ own firm | ✗ | ✗ | ✗ | ✓ supported firms | ✓ all + no-firm rows | ✓ Beta only |
| R3 | See Golden Angels rows | ✓ | ✗ | ✗ | ✗ | ✓ while support enabled | ✓ | ✗ |
| R4 | See unknown-email failures | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| R5 | Download | ✓ own firm | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ Beta only |
| R6 | Edit or delete an event (any URL) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| R7 | Receive the admin alert | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ (other firm) |
| R8 | Receive the weekly pack | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ (goes to support@caphive.com, not to people) | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails sent by this feature arrive | Admin alert, download and weekly pack: right recipients, subject, link; dates shown as `Nov 09, 2026` | | |
| ☐ | C2 | Dates on the Security Events screen | Follow the viewer's locale (`09/11/2026` for en, `11/09/2026` for en-US) | | |
| ☐ | C3 | Narrow / mobile width | Cards stack; table scrolls inside its card; no page-level horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Sara cannot see Golden Angels rows, even with a hand-typed URL or download | | |
| ☐ | C5 | Regression on modified screens | Sign-in, two-factor, magic link, Login as, user edit, API tokens, mobile devices, folder download, spreadsheet downloads, Audit Trail all behave and word exactly as before | | |
| ☐ | C6 | Empty states | "No security events in this period. Widen the dates or clear the filter." | | |
| ☐ | C7 | Looks like the rest of CapHive | Matches Capital Calls list: header buttons, stats cards, standard table, filter, full width (compare with mocks/security_events_index.html) | | |
| ☐ | C8 | No full page reloads for filter/paging | Only the list area changes | | |
| ☐ | C9 | Explains itself | Title ⓘ, Event ⓘ and Door ⓘ tooltips; empty state says what to do | | |
| ☐ | C10 | Speed | List opens in under ~2 s with a month of events; signing in feels no slower | | |
| ☐ | C11 | Nothing secret on screen or in the spreadsheet | No password, code, token, link or full phone number anywhere | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
