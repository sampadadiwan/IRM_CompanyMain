# CapHive LP Mobile App — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

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
| Environment | Staging India region and staging US region; app from TestFlight (iOS) and Play internal testing (Android), "staging" build |
| Phones | One iPhone (Face ID) and one Android phone (fingerprint). A second iPhone or simulator for the two-phone rows |
| Accounts | rahul@sharmafo.in (LP, authenticator two-factor) · anil@advisors.in (investor advisor to Sharma Family Office, no two-factor) · meera@arkacapital.in (Arka Capital fund manager employee) · vikram@kapoor.in (LP of Kapoor Holdings) · jane@us-lp.com (US region, US English) · an SMS two-factor LP for E3 |
| Second entity | Kapoor Holdings (another investor in the same fund) and Beta Partners (a second fund manager, for E29) |
| Seed data | Ask a developer to run `mobile:seed_e2e` on staging. It creates Arka Growth Fund I with Calls 1–3, Distribution 1 and the documents named in the [design shared setup](design.md#worked-examples) |
| Background work | Push is sent when Meera issues a call or sends a notification on the website. Push receipts are checked about 15 minutes later automatically, or ask a developer to run the receipts job now |
| Expo failures (X10, X11, X20) | Need a developer to switch the staging push stub or credential. Mark "Dev-assisted" in Notes |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Sign in with authenticator code | Rahul, fresh install | 1. Region › India 2. Enter email and password › Sign in 3. Enter the authenticator code | Code screen after step 2; Home after step 3 | | |
| ☐ | H2 | Sign in without two-factor | Anil, fresh install | 1. Region › India 2. Email and password › Sign in | Home opens directly, no code screen | | |
| ☐ | H3 | Session survives an hour | Rahul signed in | 1. Leave the app 70 minutes 2. Reopen, unlock | Data loads; no sign-in screen | | |
| ☐ | H4 | Home figures and To do | Seed data | 1. Open Home | Arka Growth Fund I card: Committed ₹5.00 Cr, Called ₹2.00 Cr (bar at 40%), Due ₹75.00 L, Distributed ₹30.00 L. To do: Capital Call 3 ₹75,00,000 due 30/10, Side letter — sign, Subscription Addendum — sign | | |
| ☐ | H5 | Fund calls list | — | 1. Home › tap the Arka card 2. Calls segment | Capital Call 3 ₹75,00,000 Pending · Capital Call 2 ₹50,00,000 Paid · Capital Call 1 ₹75,00,000 Paid | | |
| ☐ | H6 | Capital call with notice | Notice generated and approved for Call 3 | 1. Tap Capital Call 3 2. Tap View call notice | Status Pending, Call amount ₹75,00,000, Received ₹0, Due by 30/10/2026; PDF opens | | |
| ☐ | H7 | Opening a document is recorded | — | 1. Documents › Q2 2026 Statement 2. On the website as Meera, open the document's "Viewed by" | Rahul is listed with today's date | | |
| ☐ | H8 | Advisor switches investor | Anil signed in | 1. Home › tap the investor name 2. Pick Sharma Family Office | Home shows only Sharma Family Office's fund | | |
| ☐ | H9 | Read state shared with website | An unread alert | 1. Alerts › tap the alert 2. On the website as Rahul, check the bell | The bell count dropped by one | | |
| ☐ | H10 | Allow notifications | Fresh sign-in | 1. Tap Allow on the prompt 2. Profile › Notifications | "Push notifications on this phone" is on | | |
| ☐ | H11 | Capital call push to both phones | Rahul signed in on 2 phones | 1. As Meera, issue a new capital call for Arka Growth Fund I | Both phones show a banner titled "Arka Capital" with the call subject | | |
| ☐ | H12 | Custom subject in push | Meera set a custom subject "Arka Growth I — Call 3 notice" | 1. Issue the call | Push body reads "Arka Growth I — Call 3 notice" | | |
| ☐ | H13 | Approval opens on the website | Approval sent to Sharma FO | 1. Alerts › tap the approval | Website approval page opens inside the app, already signed in | | |
| ☐ | H14 | Sign out a phone from the website | Rahul on 2 phones | 1. Website › Profile › Devices 2. Sign out "iPhone 15" › confirm 3. Use the iPhone | Row shows Signed out; iPhone returns to sign-in (push behaviour is checked in E27) | | |
| ☐ | H15 | Category saved | — | 1. Profile › Notifications › turn off Distributions 2. Sign out and in again | Distributions still off | | |
| ☐ | H16 | First run end to end | Fresh install | Follow J1 | As J1 | | |
| ☐ | H17 | Tap push opens the call | H11 done | 1. Tap the banner | Face ID, then the Capital call screen for that call; the alert is read | | |
| ☐ | H18 | Sign with Digio | Side letter pending | 1. Document › Sign 2. Complete Digio signing 3. Return | Document shows "Signed ✓" | | |
| ☐ | H19 | Notification settings persist | — | 1. Toggle Distributions off 2. Force-quit and reopen | Still off | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Wrong code then right | Rahul | 1. Enter a wrong code 2. Enter the right one | "Code is incorrect or expired — try again", then Home | | |
| ☐ | E2 | Code screen times out | Rahul | 1. Reach the code screen 2. Wait 11 minutes 3. Enter a valid code | Asked to sign in again | | |
| ☐ | E3 | SMS resend cooldown | SMS two-factor LP | 1. Tap Resend code twice quickly | Second tap shows the wait message; one SMS arrives | | |
| ☐ | E4 | Two-factor not finished | LP with two-factor turned on but no method chosen | 1. Sign in | "Finish setting up two-factor on the website" | | |
| ☐ | E5 | Eleventh phone | Dev-assisted: 10 phones exist for Rahul | 1. Sign in on another phone 2. Website › Devices | The oldest-used phone shows Signed out; 10 active | | |
| ☐ | E6 | Same phone signs in again | iPhone 15 signed out | 1. Sign in again on the iPhone 15 2. Website › Devices | Still one "iPhone 15" row, now active | | |
| ☐ | E7 | Shared phone | Rahul signed in on the Pixel | 1. Sign out, then Vikram signs in on the Pixel and allows notifications 2. Send Rahul a notification | The Pixel does not get Rahul's push | | |
| ☐ | E8 | 90-day expiry | Dev-assisted: last used set to 91 days ago | 1. Open the app | Sign-in screen | | |
| ☐ | E9 | Email off means no push | Meera turns off Email enabled for Rahul's access | 1. Issue a call | No push; the alert still appears in Alerts | | |
| ☐ | E10 | Distributions off | E10 setting | 1. Meera pays a distribution | No push; the email arrives | | |
| ☐ | E11 | Fund manager staff not pushed | Meera has the app via an LP access elsewhere | 1. Trigger an internal Arka Capital notification to Meera | No push on Meera's phone | | |
| ☐ | E12 | "Everything else" category | — | 1. Turn Everything else off 2. Send a KYC request | No push | | |
| ☐ | E13 | Advisor not approved for a record | Anil not approved for a document | 1. Send that document's notification | Anil gets neither email nor push | | |
| ☐ | E14 | Long subject | Custom subject of 250 characters | 1. Issue the call | Push body is cut short and ends with "…" | | |
| ☐ | E15 | KYC alert opens website | KYC request | 1. Alerts › tap it | Website KYC page in the app, signed in | | |
| ☐ | E16 | Two folios in one fund | Sharma FO has 2 commitments | 1. Home | Two cards | | |
| ☐ | E17 | Evergreen folio | Evergreen folio seeded | 1. Home | Card shows value, units, NAV per unit with date, gain; same numbers as the website card | | |
| ☐ | E18 | Paid / overdue in To do | Pay Call 3; seed an overdue call | 1. Home | Call 3 gone from To do; overdue call shows Overdue | | |
| ☐ | E19 | Long document list | 30 documents | 1. Documents › scroll to the end | All 30 load as you scroll | | |
| ☐ | E20 | NDA-gated documents hidden | NDA not accepted | 1. Documents | "Data Room Model.xlsx" not listed | | |
| ☐ | E21 | DocuSign document | Subscription Addendum | 1. Open it | Button "Sign in DocuSign email" and the text "Open the email from DocuSign on this phone to sign" | | |
| ☐ | E22 | No notice yet | Call without a notice | 1. Open the call | "The call notice isn't available yet" | | |
| ☐ | E23 | Off-site link blocked | Dev-assisted API call | 1. Request a hand-off to `https://evil.com` | Refused | | |
| ☐ | E24 | US date format | Jane (US) | 1. Open any call | Dates as mm/dd/yyyy | | |
| ☐ | E25 | Mark all read | 3 unread | 1. Alerts › Mark all read | All read; app badge clears | | |
| ☐ | E26 | Phone push off | — | 1. Pixel: Profile › Notifications › push off 2. Issue a call | Only the iPhone gets it | | |
| ☐ | E27 | Signed-out phone not pushed | iPhone signed out (H14) | 1. Issue a call | No push on the iPhone | | |
| ☐ | E28 | All caught up | New LP with no calls | 1. Home | "You're all caught up"; figures ₹0 | | |
| ☐ | E29 | Two fund managers | LP in Arka and Beta funds | 1. Home | Cards grouped under each fund manager | | |
| ☐ | E30 | Offline | Home loaded once | 1. Airplane mode 2. Reopen | Cached cards; "Last updated HH:MM — offline"; Sign greyed out | | |
| ☐ | E31 | Biometric fails | Face ID on | 1. Fail Face ID 3 times | Full sign-in screen | | |
| ☐ | E32 | Auto-lock timing | Face ID on | 1. Background 4 min, reopen 2. Background 6 min, reopen | 1: no prompt. 2: Face ID prompt | | |
| ☐ | E33 | Largest text | Phone text size at max accessibility size | 1. Open Home, Fund, Capital call | Nothing overlaps or is cut off | | |
| ☐ | E34 | Permission off at phone level | Notifications denied in phone Settings | 1. Profile › Notifications | "Off in phone settings" and Open phone settings | | |
| ☐ | E35 | No double push on retry | Dev-assisted: re-run a delivery | 1. Re-run | Phone gets no second banner | | |
| ☐ | E36 | Hand-off to a forbidden page | Dev-assisted: hand-off to Kapoor's call | 1. Open it | Website's standard access-denied page | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Wrong password | — | 1. Sign in with a wrong password | "Incorrect email or password" | | |
| ☐ | X2 | Three wrong codes | Rahul | 1. Enter 3 wrong codes | "Too many failed attempts. Please sign in again." and back to the sign-in screen | | |
| ☐ | X3 | Locked account | Enter a wrong password 6 times | 1. Sign in again with the right password | "Your account is locked. Please try again in 5 minutes." | | |
| ☐ | X22 | Website token endpoint refuses 2FA users | Dev-assisted | 1. POST /users/tokens/sign_in for Rahul (2FA on) | Refused with two_factor_required; no token | | |
| ☐ | X23 | Website refresh refuses a phone token | Dev-assisted | 1. POST /users/tokens/refresh with a phone's refresh token | Refused with use_mobile_refresh; the app keeps working | | |
| ☐ | X4 | Fund manager staff refused | Meera (no investor access) | 1. Sign in | "This app is for investors. Please use the CapHive website." | | |
| ☐ | X5 | Deactivated user | Dev-assisted / admin deactivates Rahul | 1. Pull to refresh | Sign-in screen | | |
| ☐ | X6 | Password change | Rahul on 2 phones | 1. Change password on the website 2. Refresh both phones | Both return to sign-in | | |
| ☐ | X7 | Website API token refused | Dev-assisted | 1. Call the phone service with a website API token | Refused (unauthorised) | | |
| ☐ | X8 | Another investor's call | Dev-assisted: open link to Kapoor's call | 1. Open `caphive://capital-calls/<kapoor id>` | "You no longer have access to this item" | | |
| ☐ | X9 | Old app | Dev-assisted: raise the minimum version | 1. Open the app | Update screen (see X21) | | |
| ☐ | X10 | Reinstalled app | Dev-assisted stub: DeviceNotRegistered | 1. Send a notification 2. Wait for receipts 3. Website › Devices | "Last delivery: failed — device no longer registered"; email still arrived | | |
| ☐ | X11 | Push service down | Dev-assisted stub: 503 | 1. Issue a call | Email arrives as normal; push arrives after the stub is restored (retry) | | |
| ☐ | X12 | Hand-off link reused | Dev-assisted: copy the hand-off URL | 1. Open it a second time in a browser | Website sign-in page | | |
| ☐ | X13 | Hand-off link expired | Dev-assisted | 1. Open it after 6 minutes | Website sign-in page | | |
| ☐ | X14 | Wrong region | Jane (US) | 1. Region India › sign in | "Incorrect email or password" and "Is your account on the US site? Switch region" | | |
| ☐ | X15 | Signed-out phone | H14 | 1. Use the signed-out phone | Sign-in screen | | |
| ☐ | X16 | Website page after sign-out | Phone signed out | 1. Tap an alert that opens a website page | Sign-in screen in the app | | |
| ☐ | X17 | Advisor switch not allowed | Dev-assisted | 1. Switch Anil to Kapoor Holdings | Refused; Home unchanged | | |
| ☐ | X18 | Document outside scope | Dev-assisted link to a Kapoor document | 1. Open it | "You no longer have access to this item" | | |
| ☐ | X19 | Access removed after push | Push received; Meera removes Rahul's access | 1. Tap the push | "You no longer have access to this item" | | |
| ☐ | X20 | Push credential missing | Dev-assisted: remove the staging credential | 1. Issue a call | No push; email arrives | | |
| ☐ | X21 | Update required | Dev-assisted: minimum version above this build | 1. Open the app | "Please update CapHive to continue" with a store button; nothing else usable | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Welcome › Region | Tap India | Sign-in screen showing "Region: India" with Change | | |
| ☐ | J1.2 | Sign in | Enter Rahul's email and password › Sign in | Code screen | | |
| ☐ | J1.3 | Code | Enter the authenticator code | Notification prompt explanation "Get notified when a capital call or document needs you" | | |
| ☐ | J1.4 | System prompt | Allow | Face ID offer "Use Face ID to unlock?" | | |
| ☐ | J1.5 | Face ID offer | Use Face ID | Home, with greeting, To do card and fund card | | |
| ☐ | J2.1 | Lock screen ① | Receive the Call push | Title "Arka Capital", body = call subject | | |
| ☐ | J2.2 | Banner ② | Tap, pass Face ID | Capital call screen opens directly | | |
| ☐ | J2.3 | Capital call ③ | Read status | Status with icon and label (Pending ◌) | | |
| ☐ | J2.4 | Capital call ④ | View call notice | Notice PDF with Share | | |
| ☐ | J3.1 | Website › Profile › Devices | Open | Each phone: name, platform, region, last used, push on/off, last delivery | | |
| ☐ | J3.2 | Devices row | Sign out | Confirmation card explaining that the phone is signed out and its alerts stop | | |
| ☐ | J3.3 | Devices row | Confirm | Row badge "Signed out" (grey) | | |
| ☐ | J4.1 | Documents tab | Type in search; tap "To sign" chip | List filters as you type; only documents awaiting your signature | | |
| ☐ | J4.2 | Alerts tab | Swipe an unread alert | Marked read; tab badge decreases | | |
| ☐ | J4.3 | Profile | Open | Notifications, Face ID, Region, Sign out | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | LP user (Rahul) | Investor advisor (Anil) | Fund manager employee (Meera) | Other-entity LP (Vikram) |
|---|---|---|---|---|---|
| R1 | Sign in to the app | ✓ | ✓ | ✗ "This app is for investors…" | ✓ |
| R2 | See Arka Growth Fund I / Sharma FO card | ✓ | ✓ after switching | ✗ | ✗ (sees only Kapoor's) |
| R3 | Open Capital Call 3 (Sharma FO) | ✓ | ✓ after switching | ✗ | ✗ "You no longer have access…" |
| R4 | Open Q2 2026 Statement (Sharma FO) | ✓ | ✓ if approved | ✗ | ✗ |
| R5 | Receive Call 3 push | ✓ | ✓ if approved for the record | ✗ (internal) | ✗ |
| R6 | Website › Profile › Devices | own phones only | own phones only | own phones only | own phones only |
| R7 | Sign out someone else's phone (direct URL) | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails still sent for every pushed notification | Same email as before this release; dates as `Oct 30, 2026` | | |
| ☐ | C2 | Dates in app and on the Devices page | Locale format: 30/10/2026 (India English), 10/30/2026 (US English) | | |
| ☐ | C3 | Website Devices page at narrow / mobile width | No horizontal scroll; Sign out reachable | | |
| ☐ | C4 | Tenant isolation | Vikram cannot open anything of Sharma FO in the app, even with a direct link | | |
| ☐ | C5 | Regression: website two-factor login (authenticator, SMS, WhatsApp) | Unchanged | | |
| ☐ | C6 | Regression: evergreen LP card on the website | Same figures as before | | |
| ☐ | C7 | Empty states | Documents with none: "No documents yet for this fund"; Alerts with none: "No alerts yet" | | |
| ☐ | C8 | Dark mode | Every screen readable in dark mode; status colours keep their icons | | |
| ☐ | C9 | Screen reader (VoiceOver / TalkBack) | Every button announced with a meaningful label | | |
| ☐ | C10 | App switcher privacy | App content blurred in the app switcher | | |
| ☐ | C11 | India and US independence | Signing in to US shows no India data; a US push never reaches an India-only device | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
