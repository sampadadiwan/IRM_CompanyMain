# Reliable India ↔ US Region Switching — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Report](report.md) · [Tasks](tasks.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the report's Verification table (H/E/X) and the UI
> journeys (J), so a failure maps straight to the automated scenario that should have caught it.

**ID legend:** **B** = the original bug, reproduced · **H** = Happy path · **E** = Edge case ·
**X** = Error case · **J** = UI journey step (J2.3 = journey 2, step 3) · **R** = Regression
(from the report's Blast Radius) · **P** = Role/policy sweep · **C** = Cross-cutting check ·
**(dev)** = needs a developer or a config change

---

## Contents

- [Test Setup](#test-setup)
- [The Original Bug](#the-original-bug)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Regression](#regression)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

This feature spans **two** deployed environments. Both must be on the build under test before you
start; a switch between an old and a new build is expected to fail and is not a valid test.

| Item | Detail |
|---|---|
| Environment | The India staging site and the US staging site, both on the same build. Note both URLs and the build/commit on the sign-off table |
| Accounts | **Neha** `neha@siliconroad.com` — regions `IN,US`, belongs to Silicon Road in both regions (India subdomain `srv`, US subdomain `acme`). **Raj** `raj@siliconroad.com` — region `IN` only. **Messy** `messy@siliconroad.com` — regions stored as `" in ,US, us"`. **Jason** `jason@siliconroad.com` — regions stored as `["US","IN"]`. **Sandeep** — regions `IN,SG` where `SG` is not a deployed region |
| Second entity | **Vikram** `vikram@othercapital.com` — a user of a different company, regions `IN,US`, for the isolation checks |
| Seed data | Ask a developer to create the five users above with those exact `regions` values (some are deliberately malformed and cannot be typed through the normal screens), and to confirm Silicon Road has a company site in **both** regions with different subdomains |
| Background work | The trust check runs hourly. To make it run now, ask a developer to trigger `CrossSiteTrustCheckJob`. The regions housekeeping is a manual task a developer runs on request, first in reporting mode then in execute mode |
| Developer-assisted rows | X11, X12, X13, X16, X17 and E9 need a setting changed or a service stopped on a staging box. They are marked **(dev)** and must be run with a developer sitting with you. Do not attempt them on production |
| Timing | Several rows need you to wait, or to leave a page sitting. Have a clock or phone timer to hand |

---

## The Original Bug

The first thing to run, and the one that matters most: reproduce the bug exactly as it was
reported and confirm it is gone. If B1 fails, nothing below it matters.

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | The reported symptom is gone | 1. Sign in as Neha on the India site. 2. Pick `US` from the top-bar region dropdown. 3. Repeat five times | Every attempt lands signed in on the US site. The bare white page reading `Invalid or expired link` never appears | | |
| ☐ | B2 | …and is gone on a slow connection, which is when it used to bite | 1. Turn on the browser's slow-network throttling. 2. Repeat B1 | Still signed in every time. This is the actual bug being fixed, so a failure here is a blocker | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | The region selector appears for a two-region user | Neha signed in on the India site | 1. Sign in as Neha on the India site. 2. Look at the top bar | A region dropdown is visible showing `IN`. Opening it lists exactly `IN` and `US`, with `IN` ticked | | |
| ☐ | H2 | A full India → US switch signs you in on the right company site | Neha signed in on the India site | 1. Open the region dropdown. 2. Choose `US` | Within a few seconds you are signed in on the **US** site, on its home page, with no password prompt. The browser address bar shows the US company subdomain (`acme`), not `app` and not the India subdomain (`srv`). Every address you pass through starts `https://` | | |
| ☐ | H3 | The hand-off survives being passed between the two US steps | Neha signed in on the India site | 1. Choose `US` from the dropdown. 2. Watch the address bar as the page moves, or check the browser's history afterwards | You pass through a US address containing `redirect_to_subdomain` and then one containing `cross_site_login`, and you end up signed in. The switch does **not** fail at the second step | | |
| ☐ | H4 | The two regions agree on their shared trust **(dev)** | Both regions deployed | 1. Ask a developer to open `/health_check/cross_site_trust` on the India site and on the US site. 2. Compare the two fingerprints shown | Both pages report `configured: true` and show the **same** fingerprint string. If they differ, stop — region switching cannot work and this is a release blocker | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | A single-region user gets no selector | Raj exists with region `IN` only | 1. Sign in as Raj on the India site. 2. Look at the top bar | No region dropdown is shown anywhere in the top bar | | |
| ☐ | E2 | Messy stored regions still work | Messy's regions are `" in ,US, us"` | 1. Sign in as Messy on the India site. 2. Open the region dropdown. 3. Choose `US` | The dropdown shows exactly two clean options, `IN` and `US` — no duplicates, no lower-case, no stray spaces. Choosing `US` signs you in on the US site | | |
| ☐ | E3 | A region that is not deployed is not offered | Sandeep's regions are `IN,SG`; `SG` is not deployed | 1. Sign in as Sandeep on the India site. 2. Open the region dropdown | Only `IN` is listed. `SG` does not appear. Ask a developer to confirm Sandeep's stored regions value is still `IN,SG` — nothing was deleted from his profile | | |
| ☐ | E4 | Regions stored in the older list format still work | Jason's regions are stored as `["US","IN"]` | 1. Sign in as Jason on the India site. 2. Open the region dropdown | Exactly `IN` and `US` are listed. There is no option containing a bracket, a quote mark or a comma | | |
| ☐ | E5 | A company with no site in the destination region still lands somewhere sensible | Ask a developer for a user with regions `IN,US` whose company has **no** subdomain configured in the US | 1. Sign in as that user on the India site. 2. Choose `US` | You are signed in on the US site's default address (`app.…`), not an error page | | |
| ☐ | E6 | A few minutes of clock difference does not break the switch **(dev)** | Ask a developer to set one region's server clock about 3 minutes away from the other's, and to put it back straight afterwards | 1. Sign in as Neha on the India site. 2. Choose `US` promptly | The switch still succeeds and you are signed in | | |
| ☐ | E7 | Two simultaneous attempts produce only one session | Neha signed in on the India site | 1. Choose `US`. 2. The instant the failure or success page appears, press the browser's back button and immediately re-submit the same address twice in quick succession (or ask a developer to replay it concurrently) | Exactly one attempt signs you in. The other reports that the link had already been used. You are never signed in twice from one switch | | |
| ☐ | E8 | A used link stays used across both US servers | Neha has just completed a switch to the US | 1. Copy the `cross_site_login` address from the browser history. 2. Paste it into a fresh private window. 3. Repeat several times in a row | Every attempt reports that the link had already been used — there is no attempt that succeeds because it happened to reach a different server | | |
| ☐ | E9 | A region with no shared secret says so plainly **(dev)** | Ask a developer to point a staging region at an empty shared secret | 1. Open that region's `/health_check/cross_site_trust` | The page reports the secret as **not configured** and shows no fingerprint at all. It does not show a fingerprint of an empty value | | |
| ☐ | E10 | The trust page leaks nothing **(dev)** | Both regions deployed | 1. Open `/health_check/cross_site_trust` on each region. 2. Read the whole response | The only long value is a single fixed-length fingerprint. Ask the developer to confirm no part of the actual shared secret appears anywhere in the response | | |
| ☐ | E11 | Housekeeping tidies messy regions | Messy's regions are `" in ,US, us"` | 1. Ask a developer to run the regions housekeeping in **execute** mode. 2. Sign in as Messy and open the region dropdown | Her stored regions value is now `IN,US`. The dropdown still offers the same two regions, and she can still switch to both | | |
| ☐ | E12 | Housekeeping converts the older list format | Jason's regions are `["US","IN"]` | 1. Ask a developer to run the housekeeping in execute mode. 2. Check Jason's stored value | It is now `IN,US`. Jason can still switch to both regions | | |
| ☐ | E13 | Running housekeeping twice changes nothing | Housekeeping has already run once in execute mode | 1. Ask a developer to run it again in execute mode | The run reports that no user was changed | | |
| ☐ | E14 | Housekeeping's reporting mode writes nothing | Messy and Jason are back to their messy values | 1. Ask a developer to run the housekeeping in **reporting** mode. 2. Check both users' stored values | The run lists Messy and Jason as users it *would* change, and neither stored value has actually changed | | |

---

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | An expired link explains itself and offers a way back | Neha signed in on the India site | 1. Choose `US`. 2. As soon as the US page starts loading, stop it. 3. Copy the US address from the browser history. 4. Wait **6 minutes**. 5. Open that address | The **US sign-in screen** appears (not a blank page) with: "We couldn't complete your switch to the US site because the hand-off link had expired. Return to the India site and try again, or sign in below." plus a working **Return to India** link. Ask a developer to confirm one log line records reason `expired`, the region, the server and Neha's email | | |
| ☐ | X2 | A reused link is refused, with a way back | Neha has just completed a switch to the US | 1. Copy the `cross_site_login` address from the browser history. 2. Within 5 minutes, open it in a fresh private window | The US sign-in screen appears with: "We couldn't complete your switch to the US site because that hand-off link had already been used. Return to the India site and try again, or sign in below." plus the **Return to India** link | | |
| ☐ | X3 | A link with no credential at all | none | 1. Open the US site's `/users/cross_site_login` with no extra query on the end | The US sign-in screen appears saying the switch could not be completed. There is **no** "Return to…" link. The email and password form below is fully usable | | |
| ☐ | X4 | A tampered link | Neha signed in on the India site | 1. Choose `US` and stop the load. 2. Copy the US address and change a few characters in the middle of the long token value. 3. Open it | The US sign-in screen appears saying the hand-off link was not valid. You are not signed in. There is no "Return to…" link | | |
| ☐ | X5 | A link aimed at the wrong region | Neha signed in on the **US** site this time | 1. From the US site, choose `IN` and stop the load. 2. Copy the resulting India address. 3. Change its host to the **US** site, keeping the token | The US sign-in screen appears with: "We couldn't complete your switch to the US site because that link was meant for a different region. Return to the India site and try again, or sign in below." You are not signed in | | |
| ☐ | X6 | A link made for something other than region switching | Ask a developer for a signed link created for a different purpose | 1. Open it at the US site's `/users/cross_site_login` | The US sign-in screen appears saying the hand-off link was not valid. You are not signed in | | |
| ☐ | X7 | Mismatched shared secrets do not invite a pointless retry **(dev)** | Ask a developer to set a different shared secret on the US staging region and to trigger the trust check | 1. Sign in as Neha on the India site. 2. Choose `US` | The US sign-in screen appears with: "We couldn't complete your switch to the US site because of a configuration problem on our side. Please sign in below." There is **no** "Return to India" link, because retrying cannot help. Confirm with the developer that an operations alert has fired for the trust check | | |
| ☐ | X8 | No account in the destination region | Ask a developer for a user with regions `IN,US` who exists in India but not in the US | 1. Sign in as that user on the India site. 2. Choose `US` | The US sign-in screen appears with "We couldn't find an account for you on the US site." You are not signed in | | |
| ☐ | X9 | A region that is not deployed is refused before you leave | Sandeep exists with regions `IN,SG` | 1. Sign in as Sandeep on the India site. 2. Ask a developer to submit a switch naming `SG` on his behalf (the dropdown will not offer it) | You stay on the India site, still signed in, with a message that the region is unavailable. The browser never leaves the India site | | |
| ☐ | X10 | You cannot switch to a region you do not have | Raj exists with region `IN` only | 1. Sign in as Raj on the India site. 2. Ask a developer to submit a switch naming `US` on his behalf | The request is refused as not permitted. Raj stays on the India site and is **not** signed in on the US site. Check the US site in a private window to confirm no session was created | | |
| ☐ | X11 | A broken region list stops the app starting **(dev)** | A staging box you can restart | 1. Ask a developer to set the region list setting to something unreadable and restart the app | The app **refuses to start**, with an error naming the region list setting. It does not start and then fail later on a switch. Have the developer restore the setting and confirm it starts again | | |
| ☐ | X12 | An insecure address stops the app starting **(dev)** | A staging box you can restart | 1. Ask a developer to change one region's address in the region list from `https` to `http` and restart | The app refuses to start, with an error naming that region | | |
| ☐ | X13 | A region list that omits this region stops the app starting **(dev)** | A staging box you can restart | 1. Ask a developer to remove this region's own entry from the region list and restart | The app refuses to start, with an error naming both the region list and this region's code | | |
| ☐ | X14 | No technical detail is shown on any failure page | Rows X1 to X8 have been run | 1. Re-read each failure page from X1 to X8, including the page source if you can | No page shows the long hand-off link, a server name or address, or a technical error name. Only plain English | | |
| ☐ | X15 | The hand-off link never reaches a log **(dev)** | Rows H2 and X1 to X8 have been run | 1. Ask a developer to search the application log for the long token values from those runs | No log line contains a hand-off link value. The lines do contain the reason, the region, the server and the user's email | | |
| ☐ | X16 | Deploying to a host without clock synchronisation fails loudly **(dev)** | A staging app host | 1. Ask a developer to stop the clock-synchronisation service on it and run the deploy check | The check reports that host as failing. Have them restart the service and confirm it then passes | | |
| ☐ | X17 | Clock drift is alerted on before it breaks switches **(dev)** | Grafana access | 1. Ask a developer to show you the provisioned alert rules | There is a clock-offset rule for **every** application server in **both** regions, and its threshold is well under 5 minutes. There is also a rule for the synchronisation service being stopped | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | India site, top bar | Sign in as Neha and look at the top bar | ① the region dropdown showing her current region, `IN` | | |
| ☐ | J1.2 | India site, top bar | Open the dropdown | ② `IN` with a tick, ③ `US` below it — and nothing else. Sign in as Sandeep and repeat: his misspelled `SG` is absent | | |
| ☐ | J1.3 | India site, top bar | Choose `US` | The page navigates away straight away. There is no "Are you sure?" step and no separate Go button | | |
| ☐ | J1.4 | US site, home page | Wait for the switch to finish | You are signed in on the US home page for Silicon Road, with no password prompt | | |
| ☐ | J2.1 | US sign-in screen, after a failed switch | Run X1 to reach it | ① a banner naming in plain words which of the five things went wrong | | |
| ☐ | J2.2 | US sign-in screen, after a failed switch | Click the **Return to India** link | ② takes you to the India site, where you are **still signed in**. Open the dropdown and choose `US` again — the switch now works | | |
| ☐ | J2.3 | US sign-in screen, after a failed switch | Run X1 again, then ignore the banner and sign in with Neha's email and password | ③ the ordinary form works normally. The banner never blocks or covers it | | |
| ☐ | J2.4 | US sign-in screen, after a configuration failure | Run X7 to reach it | ① reports a configuration problem, and ② the Return-to link is **absent** | | |
| ☐ | J2.5 | US sign-in screen, after any failed switch | Look for anything to quote to support | Nothing technical is on the page. Confirm with a developer that the detail is in the log against the user's email | | |

---

## Regression

One row per entry in the report's [Blast Radius](report.md#blast-radius) that shares the code
this fix changed. These must behave exactly as they did before.

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Multi-region user sync is unaffected | Ask a developer to run the user-sync fanout for a user with regions `IN,US` | The sync still reaches the other region exactly as before. This fix deliberately did **not** touch `SyncApiClient` | | |
| ☐ | R2 | Every authenticated page still renders | Sign in and visit the dashboard, a fund, an investor and a document page, as a single-region user and as a two-region user | Every page renders, and the top bar is intact in both cases — the region selector's guard changed, and it runs on every page | | |
| ☐ | R3 | The other health checks still answer | Open each existing `/health_check/*` endpoint | Each responds as before; the new trust endpoint did not disturb them | | |
| ☐ | R4 | Sign-in itself is unchanged | Sign in normally with a password, with a magic link, and with two-factor enabled | All three behave exactly as before — the sign-in screen gained a banner partial | | |
| ☐ | R5 | A user's region access is unchanged by the housekeeping | Note a few users' regions before the rake task, and check them after | The same regions are reachable for every user; only spacing, casing and ordering changed | | |

---

## Role Sweep

Mark ✓ = allowed and works · ✗ = correctly blocked · ! = wrong (raise a defect)

| ID | Screen / action | Two-region user (Neha) | Single-region user (Raj) | Support impersonating Neha | Signed-out visitor | Other-company user (Vikram) |
|---|---|---|---|---|---|---|
| P1 | Region dropdown is shown in the top bar | ✓ shown | ✗ hidden | ✓ shown, same regions as Neha | ✗ no top bar | ✓ shown for their own regions |
| P2 | Switch to a region on their own profile | ✓ signs in | — | ✓ signs in, still shown as support acting for Neha | — | ✓ signs in |
| P3 | Switch to a deployed region **not** on their profile (developer-submitted) | — | ✗ refused as not permitted | ✗ refused — impersonation must not widen access | ✗ sent to sign-in | ✗ refused |
| P4 | Open a `cross_site_login` address with no credential | ✗ sign-in screen, no session | ✗ same | ✗ same | ✗ same | ✗ same |
| P5 | Open **Neha's** hand-off address while signed in as Vikram, before she uses it | — | — | — | — | ! must not happen: Vikram must end up signed in as **Neha** only if he holds her unused link, and after this row her own switch must fail as already used. Record exactly what happened |
| P6 | After switching, see only their own company's data on the destination region | ✓ Silicon Road US only | — | ✓ Silicon Road US only | — | ✓ Other Capital US only |
| P7 | Open `/health_check/cross_site_trust` | ✓ fingerprint only | ✓ fingerprint only | ✓ fingerprint only | ✓ fingerprint only, by design | ✓ fingerprint only |

Row P5 is the security row: it confirms the link is single-use rather than a reusable password. Note
that a hand-off link legitimately signs in whoever holds it — that is why it must die on first use and
why it must never be shared. Record the result carefully.

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | **N/A** — this feature sends no email and no in-app notification. Operations alerts are covered by X7 and X17 | | |
| ☐ | C2 | Dates on changed screens | **N/A** — neither the region dropdown nor the sign-in banner shows a date. If you see a date anywhere in this feature, raise it as a defect | | |
| ☐ | C3 | Narrow / mobile width | At phone width, the region dropdown is reachable and usable in the top bar, and the sign-in banner wraps without horizontal scrolling and without pushing the Sign in button off screen | | |
| ☐ | C4 | Tenant isolation | Sign in as Vikram (different company), switch to the US, and try to reach a Silicon Road record by pasting a direct URL. Nothing of Silicon Road's is visible or reachable | | |
| ☐ | C5 | Regression on modified screens | **India and US top bar:** everything else in it still works (search, profile menu, notifications). **Sign-in screen, both regions:** reaching it normally shows no cross-region banner, and the ordinary password sign-in, the magic-link option and the forgot-password link all still work. **Two-factor:** a user with two-factor enabled on the destination region is still prompted as before after a switch | | |
| ☐ | C6 | Empty states | A user with no regions recorded at all sees no dropdown and no empty or broken control in the top bar | | |
| ☐ | C7 | Both directions | Run H2 in reverse: US → India. Then run X1 in reverse and confirm the banner names the **India** site and offers **Return to US**, not the other way round | | |
| ☐ | C8 | Repeat switching | Switch India → US → India → US four times in a row without signing out. Every switch succeeds; none is refused as already used | | |
| ☐ | C9 | Slow connection | Using the browser's network throttling, switch India → US on a slow profile. The switch still succeeds. This is the actual bug being fixed, so a failure here is a blocker | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | India staging: <br> US staging: | | Pass / Pass with defects / Fail | |
