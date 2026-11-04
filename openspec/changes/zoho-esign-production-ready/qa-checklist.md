# Zoho eSign, production ready — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check · **P** =
pre-release Zoho check

Rows marked **(dev-assisted)** need a developer to simulate something Zoho can't be made to do on
demand (a timeout, a forged update). The developer uses the commands in the operations guide
(`docs/operations/zoho_sign.md`).

---

## Contents

- [Test Setup](#test-setup)
- [Pre-release Zoho Checks](#pre-release-zoho-checks)
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
| Environment | India staging (`staging.in`) with PR 1 and PR 2 deployed; CapHive's platform Zoho account configured, its webhook created with HMAC on and the same secret as the environment's `ZOHO_WEBHOOK_SECRET` |
| Zoho accounts | (1) CapHive platform account (India). (2) A test Zoho Sign account in the **US** region, API plan, for "Arka Capital". (3) A test Zoho Sign account in **Japan** for "Bodhi Partners" (or any second region available) |
| Accounts | Meera — company admin, Arka Capital · Asha — employee who can edit documents, Arka Capital · Kabir — company admin, Bodhi Partners · Ravi — CapHive support · Chola admin — company admin, Chola Ventures |
| Second entity | Bodhi Partners (Zoho, own Japan account) and Chola Ventures (Digio) for isolation and regression |
| Seed data | Arka Capital and Bodhi Partners with eSign provider **Zoho** (Ravi sets it in the admin dashboard); Chola Ventures with **Digio**. A 3-page document "Arka Fund I - Q3 Statement" with signers rohan@example.com and priya@example.com (use mailboxes you can open). A second document "Arka Fund I - Q2 Statement" |
| Background work | Status check: **Document › Signatures › Get eSignatures' updates**. Daily check for all documents: ask a developer to run the daily eSign status check. Live updates: happen when a signer acts in Zoho (wait ~1 minute) |
| Dates | Screen dates follow the user's locale (`dd/mm/yyyy` for English). Note today's date D; "D+1" = tomorrow, "D+400" = 400 days from today |

---

## Pre-release Zoho Checks

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | P1 | Status names Zoho really uses | Arka connected (H2) | 1. Send a document. 2. Open it in Zoho, decline as one signer; send another and recall it in Zoho; let a third expire (1-day expiry). 3. Click Get eSignatures' updates on each | Declined → document "Failed"; recalled → "Cancelled"; expired → "Expired". If any shows unchanged, record the Zoho status shown in the eSign log for a developer | | |
| ☐ | P2 | Canada region address | A Canada Zoho test account, or developer | 1. Connect with region Canada | "Connected". If it fails with an address error, raise a defect (region table) | | |
| ☐ | P3 | Scopes are enough | Grant code generated with `ZohoSign.documents.CREATE,ZohoSign.documents.READ,ZohoSign.documents.UPDATE` | 1. Connect. 2. Send, remind, extend, cancel one document | All succeed; no "scope" error | | |
| ☐ | P4 | Zoho accepts long extensions | A document In progress on a real Zoho account | 1. Extend Expiry to D+400 | "Document's eSignature expiry was extended"; Zoho shows the same date. If Zoho refuses, record its message for a developer (CapHive has no limit of its own) | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Support sees the Zoho panel | Arka not connected | 1. Log in as Ravi. 2. Open Arka Capital's company page | Panel "Zoho eSign" with badge "Using CapHive's" and the connect form | | |
| ☐ | H2 | Connect own account | Self Client created in the US Zoho account; fresh grant code | 1. Region "United States". 2. Paste Client ID, Client Secret, grant code. 3. Click Connect | "Connected — documents sent from now on use Arka's Zoho account (United States)."; Connected on shows today's date and time | | |
| ☐ | H3 | Webhook secret shown once | H2 done | 1. Click Show webhook secret. 2. Copy it. 3. Reload the page | Secret shown once; after reload it is masked and only "Regenerate webhook secret" is offered | | |
| ☐ | H4 | Verify | H2 done | 1. Click Verify connection | "Connection verified"; badge Connected | | |
| ☐ | H5 | Send through Arka's account | H2 done; Q3 has expiry 30 days | 1. As Asha open Q3 › Signatures › Send For eSignatures | "Document was queued for eSignature." then "Document - Arka Fund I - Q3 Statement sent for eSigning"; status Requested; "eSignature Expires On" = D+30; signers receive the email **from Arka's Zoho account** | | |
| ☐ | H6 | Send through CapHive's account | Arka not connected (before H2, or after H16) | 1. Send Q2 | Sent; signer email comes **from CapHive's Zoho account** | | |
| ☐ | H7 | Expiry and reminder settings reach Zoho | Q3: Expires In 30, reminders on, every 7 | 1. Send. 2. Open the request in Arka's Zoho | Zoho shows expiry D+30 and reminders every 7 days | | |
| ☐ | H8 | Live update when a signer signs | H5 done; webhook set up (J3) | 1. Rohan signs from his email. 2. Wait a minute, reload Q3 | Rohan "Signed"; Priya "Requested"; Last update on the company panel is recent | | |
| ☐ | H9 | Manual status check, partly signed | Rohan signed, Priya not | 1. Click Get eSignatures' updates | Rohan "Signed", Priya "Requested", document "In progress" | | |
| ☐ | H10 | Completion | Both signed | 1. Priya signs. 2. Wait a minute, reload | Document "Completed"; one new document "Arka Fund I - Q3 Statement" (Signed) and one "Arka Fund I - Q3 Statement - Signature Certificate" | | |
| ☐ | H11 | Extend expiry | A Zoho document In progress | 1. Extend Expiry. 2. Pick D+40. 3. Extend Expiry | "Document's eSignature expiry was extended"; Expires On shows D+40; Zoho shows the same | | |
| ☐ | H12 | Send reminder | A Zoho document In progress, Priya pending | 1. Send Reminder | "Reminder was sent to pending signer(s)"; Priya receives a reminder email from Zoho | | |
| ☐ | H13 | Cancel | A Zoho document In progress | 1. Cancel eSignatures, confirm | "Document's eSignature(s) was cancelled"; document and signers "Cancelled"; request recalled in Zoho; Resend available | | |
| ☐ | H14 | Reconnect | Arka "Needs reconnect" (X8) | 1. Generate a new grant code. 2. Reconnect with it | "Connected"; Connected on unchanged; Get eSignatures' updates on an Arka document works again | | |
| ☐ | H15 | Signers marked Sent | H5 just sent | 1. Wait a minute after sending, reload | Signers show "Sent" (then "Requested" once they open it) | | |
| ☐ | H16 | Disconnect | No Arka documents out for signature on Arka's account | 1. Disconnect, confirm. 2. Send a new document | Panel back to "Using CapHive's"; the signer email comes from CapHive's account | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No panel for a Digio company | — | 1. Log in as Ravi. 2. Open Chola's company page | No Zoho eSign panel | | |
| ☐ | E2 | Digio documents unchanged | A sent Chola document | 1. Open it › Signatures; open Edit | No Extend Expiry, no Send Reminder, no expiry/reminder fields; Digio send/cancel/updates work as before | | |
| ☐ | E3 | Required fields | Arka not connected | 1. Leave Client Secret and grant code blank. 2. Connect | Both fields marked required; nothing saved | | |
| ☐ | E4 | Region outside the list (dev-assisted) | — | 1. Developer submits a connect request with region "xx" | "Pick a Zoho region"; nothing saved | | |
| ☐ | E5 | Double click Connect | Fresh grant code | 1. Double-click Connect quickly | One connection; panel Connected (no duplicate, no error page) | | |
| ☐ | E6 | Reconnect keeps the secret | Arka connected | 1. Reconnect with Client Secret left blank and a fresh grant code | "Connected"; sending still works | | |
| ☐ | E7 | Old webhook secret stops working | Arka connected, webhook working | 1. Regenerate webhook secret (do not update Zoho). 2. Have a signer sign | Status does not change live; "Last update" does not move. 3. Paste the new secret into Zoho; next signature updates live | | |
| ☐ | E8 | Secrets not in logs (dev-assisted) | H2 done | 1. Developer checks the request log for the connect request | Client secret and grant code shown as [FILTERED] | | |
| ☐ | E9 | Old document keeps syncing on CapHive's account | Q2 sent before connecting, then H2 | 1. Get eSignatures' updates on Q2 | Q2 updates normally (signed signers show Signed) | | |
| ☐ | E10 | Document sent at the connect moment (dev-assisted) | — | 1. Developer confirms a document sent the same second as connecting uses Arka's account | Arka's account used | | |
| ☐ | E11 | Document sent just before connecting | Send Q2, then connect within a minute | 1. Get eSignatures' updates on Q2 | Works on CapHive's account | | |
| ☐ | E12 | New credentials get a new token | Arka reconnected with a new Self Client | 1. Get eSignatures' updates on an Arka document | Works (no "needs reconnect") | | |
| ☐ | E13 | Defaults | Expires In and Reminder Every blank | 1. Send. 2. Check in Zoho | Expiry D+90, reminders every 4 days; screen shows "Every 4 day(s)" | | |
| ☐ | E14 | Expiry limits accepted | — | 1. Save Expires In 99. 2. Save 1 | Both saved | | |
| ☐ | E15 | Expiry limits refused | — | 1. Save Expires In 0. 2. Save 100 | Refused with a message that it must be between 1 and 99; not saved | | |
| ☐ | E16 | Reminder limits | — | 1. Save Reminder Every 30. 2. Save 31 | 30 saved; 31 refused (between 1 and 30) | | |
| ☐ | E17 | 25 signers | Document with 25 signers | 1. Send | Sent | | |
| ☐ | E18 | Signature boxes on every page | 3 pages, Display On Page "All", 2 signers | 1. Send. 2. Open as Rohan in Zoho | A signature box for Rohan on each of the 3 pages; Priya's boxes don't overlap Rohan's | | |
| ☐ | E19 | First page only | Display On Page "First" | 1. Send. 2. Open in Zoho | Boxes only on page 1 | | |
| ☐ | E20 | Forced signing order | "Force eSign order" on | 1. Send | Priya gets her email only after Rohan signs | | |
| ☐ | E21 | Extend to tomorrow | In progress | 1. Extend to D+1 | "Document's eSignature expiry was extended" | | |
| ☐ | E22 | Extend far into the future | In progress | 1. Extend to 31/12 of next year | Extended; Expires On shows exactly that date, not a shorter one | | |
| ☐ | E23 | Extend to a past date (dev-assisted, the date picker blocks it) | In progress | 1. Developer submits D-28 | "Choose a date from <D+1> onward." (date in locale format); expiry unchanged | | |
| ☐ | E24 | Extend to today (dev-assisted) | In progress | 1. Developer submits D | Same message; unchanged | | |
| ☐ | E25 | Expiry follows Zoho | In progress | 1. Extend the request directly in Zoho to D+50. 2. Get eSignatures' updates | Expires On shows D+50 | | |
| ☐ | E26 | No reminder on completed | A Completed Zoho document | 1. Open Signatures | No Send Reminder or Extend Expiry button | | |
| ☐ | E27 | Duplicate update (dev-assisted) | After H8 | 1. Developer resends the same signed update | Nothing changes | | |
| ☐ | E28 | Completion reported twice | Both signed | 1. Immediately after the last signature, click Get eSignatures' updates | Still exactly one signed copy and one certificate | | |
| ☐ | E29 | Forwarded signer | Document In progress | 1. Rohan uses Zoho's "Forward"/reassign to a colleague. 2. Colleague signs | Rohan's row shows "Signed"; document can complete | | |
| ☐ | E30 | Recalled in Zoho | In progress | 1. Recall the request directly in Zoho. 2. Get eSignatures' updates | Document "Cancelled"; Resend available | | |
| ☐ | E31 | Expired | Document with Expires In 1 | 1. Wait past expiry (or developer simulates) | Document and signers "Expired" | | |
| ☐ | E32 | Unknown request (dev-assisted) | — | 1. Developer posts a correctly signed update for an unknown request | Accepted; nothing changes | | |
| ☐ | E33 | Fast acknowledgement | Webhook set up | 1. In Zoho › Webhooks, look at delivery history after H10 | Deliveries succeeded (no failures recorded by Zoho) | | |
| ☐ | E34 | Development leniency | Development machine only | 1. Developer posts an unsigned update without a platform secret configured | Accepted with a warning in the log (development only) | | |
| ☐ | E35 | Viewed | In progress | 1. Priya opens the email without signing | Nothing changes except Priya may show "Requested" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Employee cannot connect | Log in as Asha | 1. Open Arka's company page. 2. Developer posts a connect request as Asha | No panel; request refused; no connection | | |
| ☐ | X2 | Other company's admin | Log in as Kabir | 1. Open Arka's company page URL. 2. Developer posts reconnect/disconnect for Arka as Kabir | No panel; requests refused; Arka unchanged | | |
| ☐ | X3 | Expired grant code | Grant code older than 10 minutes or used once | 1. Connect | "Zoho did not accept the grant code — it may have expired or already been used. Generate a new code in Zoho's API console and try again."; nothing saved | | |
| ☐ | X4 | Wrong region | US account | 1. Connect with region India | "Zoho did not recognise this Client ID in the India region. Check the region matches the address of your Zoho account (sign.zoho.com = United States)."; nothing saved | | |
| ☐ | X5 | Failed reconnect | Arka "Needs reconnect" | 1. Reconnect with an expired code | Expired-code message; still "Needs reconnect" | | |
| ☐ | X6 | Disconnect with documents out | 3 Arka documents In progress on Arka's account | 1. Disconnect, confirm | "3 documents are still out for signature on this account. Wait for them to finish or cancel them first."; still connected | | |
| ☐ | X7 | Verify after revocation | Delete the Self Client in Arka's Zoho | 1. Verify connection | Badge "Needs reconnect"; message says to reconnect | | |
| ☐ | X8 | Revoked during the daily check | Self Client deleted; Arka documents out | 1. Ask a developer to run the daily eSign status check | Panel "Needs reconnect"; Meera (and other Arka company admins) get **one** email; documents keep their statuses | | |
| ☐ | X9 | Zoho slow (dev-assisted) | — | 1. Developer simulates a timeout during the daily check | Status unchanged; check retried later | | |
| ☐ | X10 | Rate limited (dev-assisted) | — | 1. Developer simulates a rate-limit answer | Not marked Failed; retried later | | |
| ☐ | X11 | Sending blocked | Arka "Needs reconnect" | 1. As Asha send a document | "Arka Capital's Zoho account needs to be reconnected. Contact CapHive support to reconnect it."; nothing sent | | |
| ☐ | X12 | 26 signers | Document with 26 signers | 1. Send | "Zoho allows at most 25 signers per document."; nothing sent | | |
| ☐ | X13 | Zoho unreachable on send (dev-assisted) | — | 1. Developer simulates a timeout. 2. Asha sends | Document "Failed"; alert "Error sending Arka Fund I - Q3 Statement for eSigning - <reason>"; Resend works | | |
| ☐ | X14 | Unreadable file | Document whose file is not a valid PDF | 1. Send | Document "Failed"; alert "Error sending <name> for eSigning - <reason>" | | |
| ☐ | X15 | Send fails half-way (dev-assisted) | — | 1. Developer makes the second step fail | Document "Failed"; no leftover draft in Arka's Zoho | | |
| ☐ | X16 | Tampered extension date (dev-assisted) | In progress | 1. Developer submits "not-a-real-date" | "Choose a date from <D+1> onward."; no error page | | |
| ☐ | X17 | Zoho refuses an extension | Request already completed in Zoho but not yet synced | 1. Extend Expiry | "Error extending eSignature expiry"; expiry unchanged | | |
| ☐ | X18 | Unsigned update (dev-assisted) | — | 1. Developer posts an update without a signature to Arka's webhook address | Refused; nothing changes | | |
| ☐ | X19 | Wrong signature on the shared address (dev-assisted) | — | 1. Developer posts with a wrong signature | Refused; nothing changes | | |
| ☐ | X20 | Update for another company (dev-assisted) | Arka document In progress | 1. Developer posts a Bodhi-signed update naming Arka's request to Bodhi's address | Accepted but Arka's document unchanged | | |
| ☐ | X21 | Unknown webhook address (dev-assisted) | — | 1. Developer posts to a made-up address | Not found | | |
| ☐ | X22 | Staging without platform secret (dev-assisted) | Staging with the platform secret temporarily removed | 1. Developer posts an unsigned update to the shared address | Refused | | |
| ☐ | X23 | Unknown Zoho status (dev-assisted) | — | 1. Developer simulates an unknown status | Statuses unchanged; logged | | |
| ☐ | X24 | Signer declines | In progress | 1. Priya declines in Zoho | Priya "Failed"; document "Failed"; Resend available | | |
| ☐ | X25 | Recall refused | Request already completed in Zoho | 1. Cancel eSignatures | "Error cancelling eSignature(s)"; statuses unchanged | | |
| ☐ | X26 | Certificate unavailable (dev-assisted) | — | 1. Developer makes the certificate download fail at completion | Document "Completed" with the signed copy; no certificate; no error shown to users | | |
| ☐ | X27 | Aadhaar signer (dev-assisted) | Developer sets one signer to Aadhaar | 1. Send | "<name> uses Aadhaar eSign, which Zoho does not support yet. Contact CapHive support."; nothing sent | | |
| ☐ | X28 | Stamp papers (dev-assisted) | Developer adds a stamp paper to the document | 1. Send | "<name> uses e-stamping, which Zoho does not support yet. Contact CapHive support."; nothing sent | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Company page › Zoho eSign | Open as Meera (not connected) | (1) badge "Using CapHive's" and an explanation | | |
| ☐ | J1.2 | same | Open the Region list | (2) ten regions: United States, Europe, India, Japan, Australia, Canada, Saudi Arabia, United Kingdom, Singapore, UAE | | |
| ☐ | J1.3 | same | Type into Client Secret | (3) characters masked | | |
| ☐ | J1.4 | same | Click Connect | (4) panel changes in place (no full page reload) to Connected, or shows the error inline | | |
| ☐ | J2.1 | Company page › Zoho eSign (connected) | Look at the panel | Account, Region, Connected on (dd/mm/yyyy hh:mm), Last update, Webhook address with Copy, masked secret | | |
| ☐ | J2.2 | same | Click Copy next to the webhook address | Address copied to clipboard | | |
| ☐ | J2.3 | same | Click Regenerate webhook secret | Confirmation asked; new secret shown once | | |
| ☐ | J2.4 | same | Click Disconnect | Confirmation asked before anything happens | | |
| ☐ | J3.1 | Zoho Sign › Settings › Developer settings › Webhooks | Create webhook with the copied address, HMAC on, the secret, events Sent, Signed by a recipient, Completed by all, Declined, Expires, Recalled | Saved in Zoho | | |
| ☐ | J3.2 | same | Click Test Url | Zoho reports success; CapHive panel "Last update" becomes now | | |
| ☐ | J4.1 | Document › Edit (Zoho company) | Untick Send Automatic Reminders | "eSign Reminder Every (days)" hides; tick again shows it | | |
| ☐ | J4.2 | Document › Signatures › Extend Expiry | Open the dialog | Date picker starts at D+1 with no latest date; "Allowed:" line reads "from <D+1> onward" | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Arka company admin (Meera) | Support (Ravi) | Arka employee (Asha) | Investor / signer | Other company admin (Kabir) |
|---|---|---|---|---|---|---|
| R1 | See Zoho panel on Arka's page | | | | | |
| R2 | Connect / reconnect Arka | | | | | |
| R3 | Verify, show / regenerate secret | | | | | |
| R4 | Disconnect Arka | | | | | |
| R5 | Send / remind / extend / cancel an Arka document | | | | | |

Expected: R1–R4 ✓ for Ravi only, ✗ for Meera, Asha, investors and Kabir. R5 follows existing document
permissions (✓ Meera, Asha with edit access; ✗ investors, Kabir).

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Reconnect email (X8) arrives | To Arka's company admins, copied to support; says to contact CapHive support; subject names Arka and Zoho; link opens the company page; dates shown as `Oct 29, 2026` | | |
| ☐ | C2 | Dates on changed screens | Expires On, Connected on, Last update and the Extend dialog's allowed dates use the locale format (`29/10/2026` for English) | | |
| ☐ | C3 | Narrow / mobile width | Company panel and Extend dialog usable at phone width; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Kabir (Bodhi) cannot see Arka's panel, webhook address or connection details, even with a direct URL; Bodhi's Zoho updates never change Arka documents (X20) | | |
| ☐ | C5 | Regression on modified screens | Document Edit, Document show and Signatures tab work for Digio and Docusign companies exactly as before; Arka documents sent before this release still update | | |
| ☐ | C6 | Empty state | Panel for a Zoho company that never connected explains CapHive's account is used | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
