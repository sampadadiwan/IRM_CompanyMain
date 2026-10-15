# Notification email gate reads the wrong investor access — Manual QA Checklist

> **Audience:** Testers running the fix by hand on a deployed build. No code knowledge needed.
> **Companion document:** [Report](report.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the report's Verification table (H/E/X), so a
> failure maps straight to the automated scenario that should have caught it.

**ID legend:** **B** = the original bug, reproduced · **H** = Happy path · **E** = Edge case ·
**X** = Error case · **R** = Regression (from Blast Radius) · **C** = Cross-cutting check ·
**(dev)** = needs a developer or a config change

---

## Contents

- [Test Setup](#test-setup)
- [The Original Bug](#the-original-bug)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging, with a mail catcher you can read (or a real inbox you control) |
| Accounts | **Fund admin** of a test fund **QA Fund**. **Two-folio contact**: one login, e.g. `qa.twofolio@…`, whose phone is WhatsApp-enabled |
| Seed data | In QA Fund create investors **Folio A** and **Folio B**, each with a commitment in fund **QA Fund I**. Add the two-folio contact to **Folio A first**, then to **Folio B**. The order matters: Folio A's access must be the older one. Also create **Folio C**, without the contact on it. Turn on WhatsApp for the fund (dev, if not already on). |
| Background work | Emails go out after the fund's random email delay (up to 5 min). Wait, or ask a developer to drain the queue. |
| Developer-assisted rows | E2 (fund-level document with no folio), X2 (deleted investor), X3 (log line) |

Set switches on the investor's **Access** tab (edit the contact's row: *Email enabled*, *WhatsApp enabled*).

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | A contact on two folios gets document emails for the folio that has email on | 1. Folio A access: Email **off**, WhatsApp **on**. 2. Folio B access: Email **on**. 3. Upload a statement to Folio B's commitment and **Send** it. 4. Open *Notifications*, filter by the contact's email. | Contact **receives the email** for the Folio B statement. The notification row shows *Email sent = Yes*. (Before the fix: *No*, with WhatsApp only.) | | Production case: Artha, asrikanth@bridgemonte.com |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Own folio's switch is used for a document | A: email off · B: email on | Send a document on Folio B's commitment | Email arrives | | Same as B1 |
| ☐ | H2 | Capital call notice still follows its own folio | A: email off · B: email on | Issue a capital call that includes Folio A; send the Folio A notice | **No** email for Folio A's notice (unchanged behaviour) | | |
| ☐ | H3 | A folio's opt-out is respected | A: email **on** · B: email **off** | Send a document on Folio B's commitment | **No** email. Row shows *Email sent = No*. (Before the fix: email was sent.) | | Production case: Artha, dhairavs@gmail.com |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Older notification shape (no folio recorded) still resolves | A: off · B: on | **(dev)** Trigger a document notification for Folio B's commitment document without a folio recorded | Email arrives | | Covered mainly by the automated scenario |
| ☐ | E2 | Fund-wide document with no folio | A: off · B: on, then both off | **(dev)** Send a document attached to the fund itself to the contact | Email arrives when either access has email on; no email when both are off | | |
| ☐ | E3 | WhatsApp follows the same folio as email | A: WhatsApp on, email off · B: WhatsApp off, email on | Send a document on Folio B's commitment | **Email** arrives, **no WhatsApp** | | Before the fix: WhatsApp only |
| ☐ | E4 | Document attached directly to an investor | A: off · B: on | Upload a document on **Folio B's own documents tab** and send it | Email arrives | | |
| ☐ | E5 | Single-folio contacts unchanged | A different contact on Folio B only, email on | Send a document on Folio B's commitment | Email arrives, as before | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No leak through another folio | A and B both email on; contact not on Folio C | Send a document on Folio C's commitment | Contact gets **nothing** (not on the recipient list) and no error appears for the admin | | |
| ☐ | X2 | Deleted folio doesn't break sending | **(dev)** a notification naming a deleted investor | Developer delivers it | No error; decision falls back to the document's own folio | | |
| ☐ | X3 | Skipped email is traceable | H3 setup | **(dev)** after H3, developer checks the app log | One line naming the notification, Folio B and its access | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | KYC emails to an advisor switched into another fund | Follow the existing KYC-notification QA (advisor with fund access, update the KYC) | Advisor still gets the KYC email | | |
| ☐ | R2 | Fund staff get notifications | Send a document; a fund employee is on the recipient list | Employee gets the email regardless of investor-access switches | | |
| ☐ | R3 | WhatsApp for a normal single-folio contact | Contact with WhatsApp on; send a capital call | WhatsApp arrives | | |
| ☐ | R4 | CC on document emails | Folio B access has a CC address; send a Folio B document | CC recipient is copied | | |
| ☐ | R5 | Capital remittance payment, distribution, commitment notices | Trigger one of each for Folio A (email on) | Each email arrives | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | N/A: no screen changes | | |
| ☐ | C2 | Dates in any email the fix touched | N/A: email content unchanged, only whether it is sent | | |
| ☐ | C3 | Narrow / mobile width | N/A: no screen changes | | |
| ☐ | C4 | Tenant isolation | The two-folio contact never receives a notification for a folio or fund they have no access on (X1) | | |
| ☐ | C5 | Screens the fix touched | *Notifications* list still shows Email sent / WhatsApp sent correctly for every row tested above | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
