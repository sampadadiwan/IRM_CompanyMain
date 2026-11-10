# Require Two-Factor for Support and Super Users — Manual QA Checklist

> For a tester who knows CapHive's screens. Rows come from [business-rules.md](business-rules.md)
> (same IDs → same Cucumber scenario) and the journeys in [design.md](design.md#what-users-see).
> **Scope:** 2FA is required for **support** and **super** only; company admins are not required;
> turning 2FA off needs password + code for **every** user who has it on.

## Contents

- [Test Setup](#test-setup)
- [ID legend](#id-legend)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging IN (staging_in) with this build; SMS rows (E17, E36) need `SMS_OTP_ENABLED=true` |
| Accounts | Every person in [business-rules › Shared setup](business-rules.md#shared-setup): Ravi, Anita, Sam, Vikram, Isha, Leela (CapHive); Meera, Neha, Omkar, Arjun, Dev, Lena, Tom (Sahyadri Capital); Priya, Rahul, Sunita (Priya Family Office); Tara (Western Ghats Ventures) |
| Second entity | Western Ghats Ventures (Tara) for isolation rows |
| Seed data | Support mappings for Ravi and Anita to Sahyadri with Login as allowed; API tokens "Ravi scripts" and "Anita reports" |
| Phones | An authenticator app on the tester's phone; a WhatsApp number for Priya; Twilio test number for Tom |
| Date control | Ask a developer to set `REQUIRED_2FA_ENFORCE_FROM` and restart. "Before the date" rows: 7 days ahead. "After" rows: yesterday. E1/E2 (exact minute): ask the developer to run the Cucumber scenario |
| Background work | Emails: staging mail catcher. Rake rows (H7, H8, E27–E29): ask a developer to run `bundle exec rake two_factor_required:<task>` with or without `EXECUTE=1` and paste the output |
| Direct requests | Rows marked "ask a developer" need a hand-crafted request sent while signed in as the named user |

## ID legend

- **H** happy path · **E** edge case · **X** error case (same IDs as business-rules.md and the Cucumber comments)
- **J** UI journey step · **R** role sweep row · **C** cross-cutting check

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Support user meets set-up | Ravi, 2FA off | 1. signs in with password | not signed in; "Set Up Two-Factor Authentication" with "Two-factor authentication is required for your role (Support). Choose a method to finish signing in." | | |
| ☐ | H2 | Required set-up completes | H1 | 1. picks Authenticator app, scans, types the current code | signed in; "Two-factor authentication is now enabled."; flag true, mode authenticator; email "Two-factor authentication was turned on for your account" dated Dec 02, 2026 | | |
| ☐ | H3 | Support user with a method | Anita | 1. signs in, types code | code screen, then signed in | | |
| ☐ | H4 | Notice banner | now 20 Nov; Ravi signed in | 1. opens the dashboard | amber banner "Two-factor authentication becomes required for your role (Support) on 01/12/2026." + Set up now | | |
| ☐ | H5 | Set up now | H4 | 1. clicks Set up now, then signs in | flag true; signed out with "Sign in again to set up two-factor authentication."; sign-in → set-up → confirm | | |
| ☐ | H6 | Verified support uses Login as | Anita; Dev has 2FA on | 1. Login as Dev | acting as Dev; Dev's code not asked | | |
| ☐ | H7 | Report shows counts only | setup data | 1. `rake two_factor_required:report` 2. (ask a developer to run the task and paste the output) | support 3 active / 2 without a verified method; super 1 / 1; distinct 3 without; line "company_admin: not required"; no names or emails | | |
| ☐ | H8 | Ending access for unverified users | Ravi has a remember-me cookie and "Ravi scripts"; Anita has both too | 1. `end_unverified_access EXECUTE=1`, then each returns after the session expired and each token is used | "Ended access for 3 users"; Ravi → sign-in page, his token → 401; Anita signed in from cookie, her token → 200 | | |
| ☐ | H9 | Investor turns off with WhatsApp code | Priya, 8 Dec | 1. Turn off 2FA → password → Send code → code → tick → submit | "Two-factor authentication is now off. You will sign in with just your password."; flag false, mode/secret cleared; audit row; emails: Priya "…turned off for your account", Rahul and Sunita "Two-factor was turned off for Priya" | | |
| ☐ | H10 | Company admin turns off voluntary 2FA | Neha (authenticator), 8 Dec | 1. password + app code | off; Neha emailed; Meera and Omkar notified | | |
| ☐ | H11 | Support resets a support user's lost method | Ravi enrolled, then lost phone; 5 Dec | 1. Anita › Users › Ravi › Reset 2FA Method | mode cleared, flag true; reset audited with Anita; Ravi gets the existing reset email; Leela gets "Two-factor method reset for Ravi"; Ravi's next sign-in → set-up | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | One minute before the date | now 30 Nov 23:59 IST | 1. Ravi signs in | signed in with password only | | |
| ☐ | E2 | Exactly on the date | now 1 Dec 00:00 IST | 1. Ravi signs in | set-up screen (as H1) | | |
| ☐ | E3 | No date configured | env unset | 1. Ravi signs in | signed in with password only; no banner | | |
| ☐ | E4 | Unparseable date fails closed | env `2026-13-01`, now 20 Nov | 1. Ravi signs in | set-up screen; log "REQUIRED_2FA_ENFORCE_FROM unparseable — enforcing" | | |
| ☐ | E5 | Support role granted after the date | Kiran grants Isha support on 2 Dec | 1. Isha signs in | set-up screen | | |
| ☐ | E6 | Support role removed before set-up | Ravi's support role removed on 2 Dec | 1. Ravi signs in | signed in with password only | | |
| ☐ | E7 | Company admin not required | Meera, 2FA off | 1. signs in | signed in with password only | | |
| ☐ | E8 | Super user required | Sam (super only), 2FA off | 1. signs in | set-up screen with "…required for your role (Super)…" | | |
| ☐ | E9 | Investor with 2FA unchanged | Priya, WhatsApp | 1. signs in | code screen; WhatsApp code sent, as today | | |
| ☐ | E10 | No phone → authenticator only | Ravi (no phone) at set-up | 1. opens the screen | only "Authenticator app" offered, preselected | | |
| ☐ | E11 | Abandoned set-up | Ravi reached set-up, closed the tab | 1. signs in again later | set-up again; flag still false, mode empty | | |
| ☐ | E12 | Support switched into a client | Ravi switched into Sahyadri (support + company_admin) | 1. signs in | one set-up screen, role label "Support" | | |
| ☐ | E13 | Company admin with flag on, no method | Omkar | 1. signs in | set-up screen as today (his own switch, not the role rule); no "required" banner | | |
| ☐ | E14 | Required user, undeliverable WhatsApp | Anita switched to WhatsApp mode; number later removed | 1. signs in | "We can't send a verification code to your phone right now. Please contact your administrator." (unchanged) | | |
| ☐ | E15 | Magic link → set-up → linked page | Ravi opens a sign-in link with `redirect_to=/users/<Ravi>` | 1. completes set-up | lands on his user page | | |
| ☐ | E16 | Password reset not auto-signed-in | Ravi completes a password reset | 1. submits new password | sign-in page "Your password has been changed successfully."; signing in → set-up | | |
| ☐ | E17 | Required set-up via SMS | Isha (support, textable number), SMS on, Twilio approves | 1. picks Text message, types code | signed in; flag true, mode sms | | |
| ☐ | E18 | Mobile app after web set-up | Vikram enrolled authenticator on the web | 1. app sign-in, then code | challenge, then device session | | |
| ☐ | E19 | Website-made API token still works | "Anita reports" token | 1. `GET /funds.json` with it on 2 Dec | 200 | | |
| ☐ | E20 | Token endpoint before the date | now 20 Nov | 1. Ravi posts correct password to `/users/tokens/sign_in` | 200 + token (unchanged) | | |
| ☐ | E21 | Required banner for an older session | Ravi signed in 30 Nov, session alive on 1 Dec 10:00 | 1. opens a page | red banner "Two-factor authentication is now required for your role. Set it up to keep using CapHive. Login as is unavailable until you do." | | |
| ☐ | E22 | Banner gone once verified | Ravi after H5 | 1. opens a page | no banner | | |
| ☐ | E23 | Banner hidden while acting as a client | now 20 Nov; Ravi acting as Dev | 1. opens a page | no banner | | |
| ☐ | E24 | No banner for a company admin | Meera, 2FA off, 2 Dec | 1. opens a page | no banner | | |
| ☐ | E25 | No banner with no date | env unset | 1. Sam opens a page | no banner | | |
| ☐ | E26 | Login as before the date | now 20 Nov; Ravi, 2FA off | 1. Login as Dev | allowed (unchanged) | | |
| ☐ | E27 | Ending access dry run | Ravi has a cookie and a token | 1. `end_unverified_access` (no EXECUTE) | "Would end access for 3 users"; Ravi's cookie and token still work | | |
| ☐ | E28 | Ending access before the date | now 20 Nov | 1. `end_unverified_access EXECUTE=1` | "Enforcement date 2026-12-01 not reached — nothing changed" | | |
| ☐ | E29 | Report when everyone is set up | Ravi, Vikram, Sam enrolled | 1. `report` | support 3 / 0; super 1 / 0 | | |
| ☐ | E30 | No method → password only | Lena (flag on, no method) | 1. Turn off 2FA → password → submit | no code field shown; off | | |
| ☐ | E31 | Edit form when on | Dev | 1. opens Edit profile | "On — turn it off from your user page" (link), no checkbox | | |
| ☐ | E32 | Edit form turning on unchanged | Arjun, off | 1. ticks Enable, saves | "User was successfully updated."; flag true; next sign-in → choose method | | |
| ☐ | E33 | Sync applies origin turn-off | Priya multi-region; origin sends `two_factor_enabled: false` | 1. `POST /internal/sync/users` (signed) | applied; flag false here | | |
| ☐ | E34 | Wrong code then right | Dev | 1. wrong code, then right | "The code you entered is incorrect. 2 attempt(s) remaining.", then off | | |
| ☐ | E35 | Required user sees no turn-off | Anita, 2 Dec | 1. opens her user page | badge "Required for your role"; no Turn off 2FA | | |
| ☐ | E36 | SMS user turns off | Tom (sms) | 1. Send code → Twilio approves the code | off | | |
| ☐ | E37 | Send code cooldown | Priya pressed Send code | 1. presses again within 60 s | "Please wait a moment before requesting another code."; one send only | | |
| ☐ | E38 | Admin sees Reset; Turn off disabled with the reason | Neha on Dev's page | 1. looks at the Two-Factor row | Reset 2FA Method shown; Turn off 2FA disabled, tooltip "Only the user can turn off their own 2FA. Use Reset 2FA Method if they lost their phone." | | |
| ☐ | E39 | Self reset sends no admin notice | Dev › Change 2FA Method | 1. confirms with password | only Dev emailed (existing) | | |
| ☐ | E40 | No other company admins | Rahul and Sunita deactivated | 1. Priya turns off | only Priya emailed | | |
| ☐ | E41 | Email date format under `ja` | Priya's turn-off processed under `ja` locale | 1. email renders | date `Dec 08, 2026` (not kanji) | | |
| ☐ | E42 | Support user turns off before the date | Anita, now 20 Nov | 1. password + code | off (notice period refuses nothing); banner appears | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Three wrong set-up codes | Ravi at set-up | 1. types 3 wrong codes | sign-in page "Too many failed attempts. Please sign in again."; flag false, mode empty | | |
| ☐ | X2 | One wrong code then right | Ravi at set-up | 1. wrong, then right | "Invalid code. 2 attempt(s) remaining.", then signed in as H2 | | |
| ☐ | X3 | Token endpoint refuses required user | Ravi, 2FA off | 1. correct password to `/users/tokens/sign_in` 2. (ask a developer to send this request on the build) | 403 `two_factor_required`; no token row | | |
| ☐ | X4 | Token endpoint wrong password | Ravi | 1. wrong password | 401 invalid; `failed_attempts` 0 → 1 | | |
| ☐ | X5 | Mobile app refuses required user without a method | Vikram, 2FA off | 1. app sign-in 2. (ask a developer to send this request on the build) | 403 `finish_2fa_setup`; no device | | |
| ☐ | X6 | Unverified support refused Login as | Ravi (no method), session from before the date | 1. clicks Login as on Dev | "Set up two-factor authentication before using Login as."; still Ravi | | |
| ☐ | X7 | Direct Login as request refused | Ravi | 1. `POST /users/<Dev>/login_as` crafted by hand 2. (ask a developer to send this request on the build) | refused; no `support_user_id` in session | | |
| ☐ | X8 | Set up now for someone else | Ravi | 1. `POST /users/<Anita>/start_two_factor_setup` 2. (ask a developer to send this request on the build) | "Access Denied"; Anita unchanged, Ravi still signed in | | |
| ☐ | X9 | Set up now while acting as a client | Anita acting as Dev | 1. `POST /users/<Dev>/start_two_factor_setup` 2. (ask a developer to send this request on the build) | "Access Denied"; Dev's flag unchanged | | |
| ☐ | X10 | Set up now for a non-required role | Meera | 1. `POST /users/<Meera>/start_two_factor_setup` 2. (ask a developer to send this request on the build) | "Access Denied" (company admins use the Edit profile toggle) | | |
| ☐ | X11 | Wrong password | Priya | 1. wrong password, any code | "The password you entered is incorrect."; 2FA on; `failed_attempts` +1 | | |
| ☐ | X12 | Wrong code | Dev | 1. right password, wrong code | "The code you entered is incorrect. 2 attempt(s) remaining."; 2FA on | | |
| ☐ | X13 | Third wrong code | Dev, 2 misses in the last 10 min | 1. third wrong, then a correct code at +2 min | "Too many incorrect codes. Try again in 10 minutes." both times; 2FA on | | |
| ☐ | X14 | Six wrong passwords lock the account | Priya, `failed_attempts` 5 | 1. wrong password | account locked; next page → sign-in "Your account is locked." | | |
| ☐ | X15 | Required user's direct turn-off | Anita, 2 Dec | 1. `POST /users/<Anita>/disable_two_factor` with right password + code 2. (ask a developer to send this request on the build) | "Two-factor authentication is required for your role and cannot be turned off."; 2FA on | | |
| ☐ | X16 | Company admin turns off an employee | Neha | 1. `POST /users/<Dev>/disable_two_factor` 2. (ask a developer to send this request on the build) | "Access Denied"; Dev unchanged | | |
| ☐ | X17 | Other firm's admin | Tara | 1. `POST /users/<Dev>/disable_two_factor` 2. (ask a developer to send this request on the build) | "Access Denied"; Dev unchanged | | |
| ☐ | X18 | JSON update switching off | Dev | 1. `PATCH /users/<Dev>.json` `two_factor_enabled=false` 2. (ask a developer to send this request on the build) | 422 with "Two-factor authentication can only be turned off from your user page, with your password and a current code."; on | | |
| ☐ | X19 | Admin console switching off | Anita in /admin/users › Dev › Edit | 1. unticks Two factor enabled, saves | form error with the same message; on | | |
| ☐ | X20 | Company admin HTML update switching off | Neha | 1. `PATCH /users/<Dev>` `user[two_factor_enabled]=0` 2. (ask a developer to send this request on the build) | edit form re-rendered with the same message; on | | |
| ☐ | X21 | Bearer token turn-off | Dev's API token | 1. `POST /users/<Dev>/disable_two_factor` with `Authorization: Bearer` 2. (ask a developer to send this request on the build) | 403 `Access Denied`; on | | |
| ☐ | X22 | Send code for someone else | Neha | 1. `POST /users/<Dev>/send_two_factor_code` 2. (ask a developer to send this request on the build) | "Access Denied"; nothing sent | | |
| ☐ | X23 | Send code with a bearer token | Dev's API token | 1. `POST /users/<Dev>/send_two_factor_code` 2. (ask a developer to send this request on the build) | 403; nothing sent | | |
| ☐ | X24 | Turn-off while acting as the user | Anita acting as Dev | 1. opens Dev's page; posts turn-off directly | no button; direct post "Access Denied"; on | | |
| ☐ | X25 | Stolen company-admin session | someone holds Neha's signed-in browser, no password | 1. unticks 2FA on Edit profile; then submits the popup with a guessed password | edit refused with the guard message; popup "The password you entered is incorrect."; 2FA on; `failed_attempts` +1 | | |

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Neha (company admin, voluntary 2FA) › her user page | Look at the Two-Factor Authentication row | ✔, badge "Authenticator", buttons **Change 2FA Method** and **Turn off 2FA**; no "Required" badge | | |
| ☐ | J1.2 | Same | Click **Turn off 2FA** | Popup "Turn Off Two-Factor Authentication": Immediate Actions with red, blue, purple, grey cards; **Turn off 2FA** disabled | | |
| ☐ | J1.3 | Popup | Type password | Button still disabled | | |
| ☐ | J1.4 | Popup | Type the app code, tick "I understand sign-in will no longer ask for a code." | **Turn off 2FA** enabled | | |
| ☐ | J1.5 | Popup | Click **Turn off 2FA** | User page; "Two-factor authentication is now off. You will sign in with just your password."; row shows ✘; Meera and Omkar emailed | | |
| ☐ | J2.1 | Priya (WhatsApp) › user page › **Turn off 2FA** | Click **Send code** | "A new code is on its way. It can take a few seconds to arrive."; WhatsApp code arrives | | |
| ☐ | J3.1 | Any page as Ravi (date 7 days ahead) | Open the dashboard | Amber banner "…required for your role (Support) on <date>." and **Set up now** | | |
| ☐ | J3.2 | Banner | Click **Set up now** | Sign-in page; "Sign in again to set up two-factor authentication." | | |
| ☐ | J3.3 | Sign-in | Sign in as Ravi | "Set Up Two-Factor Authentication"; only Authenticator offered (no phone) | | |
| ☐ | J3.4 | Set-up | Choose Authenticator app, Continue, type current code | Dashboard; "Two-factor authentication is now enabled."; banner gone; email "turned on" | | |
| ☐ | J4.1 | Sign-in as Sam (super, date yesterday, no 2FA) | Sign in | Set-up screen with blue "Two-factor authentication is required for your role (Super). Choose a method to finish signing in." | | |
| ☐ | J5.1 | Anita › her user page (date yesterday) | Look at the row | badge "Required for your role" (tooltip names Support); no **Turn off 2FA** | | |
| ☐ | J5.2 | Anita › Edit profile | Look at the 2FA row | "Required for your role (Support)." and no toggle | | |
| ☐ | J6.1 | Meera (company admin, no 2FA, date yesterday) | Sign in, open the dashboard | Signed in with password only; no banner | | |
| ☐ | J7.1 | Anita › Users › Ravi | Click **Reset 2FA Method**, confirm | "Two-factor method reset for Ravi …"; Ravi and Leela emailed | | |

## Role Sweep

| ID | Screen / action | Support (Anita, enrolled) | Support (Ravi, not enrolled, after date) | Super (Sam) | Company admin (Meera off / Neha on) | Employee (Dev, on) | Investor (Priya, on) | Other-entity user (Tara) |
|---|---|---|---|---|---|---|---|---|
| R1 | Sign in after the date | Code screen | Set-up first | Set-up first (if not enrolled) | Meera: password only · Neha: code | Code | Code | Code |
| R2 | Banner (date set, no method) | No | Yes (red) | Yes (if not enrolled) | No | No | No | No |
| R3 | **Turn off 2FA** on own page | No (required) | n/a | No (required) | Neha: yes (password + code) | Yes | Yes | Yes |
| R4 | Turn off another user's 2FA (direct request) | Refused | Refused | Refused | Refused | Refused | Refused | Refused |
| R5 | **Reset 2FA Method** for a colleague | Yes | Yes | No (super only; policy unchanged) | Yes (same firm) | No | No | Same firm only |
| R6 | **Login as** a mapped client | Yes | Refused with message | Mapping rules (unchanged) + own 2FA | No | No | No | No |
| R7 | `/users/tokens/sign_in` with password | 403 | 403 | 403 if not enrolled / 403 enrolled | Meera: token · Neha: 403 | 403 | 403 | 403 |
| R8 | **Set up now** | n/a (verified) | Yes | Yes | Refused | Refused | Refused | Refused |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails sent by this feature (turned on, turned off, admin notice, reset copy) | Right recipient and subject; dates shown as `Dec 08, 2026`; no codes in the email | | |
| ☐ | C2 | Dates on changed screens | Banner date follows locale (`01/12/2026` for en, `12/01/2026` for en-US) | | |
| ☐ | C3 | Narrow / mobile width | Banner wraps, **Set up now** reachable; popup usable at phone width; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Tara cannot turn off, send a code for, or start set-up for any Sahyadri user, even with a direct URL (X17) | | |
| ☐ | C5 | Regression on modified screens | User page, Edit profile, set-up screens, Reset 2FA Method popup, Login as and admin console user edit still do what they did; company admin sign-in unchanged | | |
| ☐ | C6 | Empty states | Report with nobody left shows zeros (E29) | | |
| ☐ | C7 | Looks like the rest of CapHive | Popup matches the Reset Two-Factor Method popup; banner matches "Please change your password at the earliest"; set-up alert matches the reset banner on that screen | | |
| ☐ | C8 | No full page reloads for small actions | **Send code** updates the popup in place | | |
| ☐ | C9 | Explains itself | "Required for your role" badge has a tooltip; popup cards explain every effect | | |
| ☐ | C10 | Speed on a large entity | User page and dashboard of the largest staging firm open as fast as before | | |
| ☐ | C11 | Unset the date (rollback) | Developer unsets the env and restarts: no banner; Ravi (still without 2FA) signs in with password only; turning 2FA off still needs password + code | | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
