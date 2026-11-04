# Embedded eSigning with Digio — Manual QA Checklist

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
| Environment | Staging, which uses Digio's **sandbox**. Use mailboxes you can read for every signer email. |
| Accounts | **Aarav** — CapHive admin (can open `/admin/entities`). **Meera** — company admin at **Orion Capital**. **Priya** — investor user, login email = signer 1 email. **Rahul** — employee at Orion Capital, login email = signer 2 email. **Vikram** — not a CapHive user, signer 3 email only. |
| Second entity | A user in a different entity (**Other Co**) with a similar document and **Enable Embedded Esign** left off; also use this user for the isolation checks. |
| Seed data | An approved document **Subscription Agreement** at Orion Capital with three signatories in this order: 1 Investor Signatory (Priya, Aadhaar), 2 Fund Signatory (Rahul, Aadhaar), 3 Counsel (Vikram, Aadhaar); **force signing order** on. **Do not send it yet.** |
| Background work | Click **Get eSignatures' updates** on the document's Signatures tab to make CapHive check with Digio right now. For Digio error codes that cannot be produced in the sandbox, ask a developer to post the code for the signer, and mark the row "dev-assisted" in Notes. |
| Mailboxes and the bell | Priya's and Rahul's CapHive login emails must be mailboxes you can read. For each notification row, check both the CapHive bell (top bar / Notifications page) and the mailbox. |
| Notification wording | Bell entry: `Your signature is requested: {document name} from {entity name}`. Email subject: `Your signature is requested: {document name}`. Email body: `{entity name} has asked you to sign {document name}.`, a **Sign now** button, then `You have also received a link from Digio by email. Either link works.` (for the seed document: document name **Subscription Agreement**, entity **Orion Capital**). |
| Investor with email off | A second investor user for Orion Capital whose investor access has **email turned off**, signing a different document — used by E34. |
| Switch | Orion Capital's **Enable Embedded Esign** is ticked only at row H1's start (Part A); unticked for the rest of the rows marked "switch off". |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | A matching signer is offered **Sign now** | Document sent for eSignature; switch on; logged in as Priya | 1. Open the Subscription Agreement | A banner reads **Your signature is requested on this document.** with a **Sign now** button | | |
| ☐ | H2 | Signing page shows the signer's context | H1 | 1. Click **Sign now** | Page shows the document name, **Signing as: priya@…**, **Signer 1 of 3 - Investor Signatory**, the signature method, a **Start signing** button and a **Back to document** button | | |
| ☐ | H3 | **Start signing** opens Digio's panel on the same page | H2 | 1. Click **Start signing** | Digio's signing panel appears on the page (not a new window); it asks for verification | | |
| ☐ | H4 | Completing the signature asks CapHive to confirm | H3 | 1. Verify with the one-time code Digio sends 2. Complete the signature | The page reads **Thank you. Your signature has been submitted and is being confirmed.** with **Back to document** | | |
| ☐ | H5 | The signature is confirmed and the turn moves on | H4 | 1. Click **Back to document** 2. If still Requested, click **Get eSignatures' updates** (Signatures tab, as an employee) 3. Log in as Rahul and open the document | Priya shows **Signed**; Rahul sees **Sign now** | | |
| ☐ | H6 | Digio's own notification updates a signer | Vikram not yet signed, Priya and Rahul signed | 1. Vikram signs from the email link 2. Wait a minute, open the document's Signatures tab | Vikram shows **Signed** without clicking anything | | |
| ☐ | H7 | The last signature completes the document | H6 | 1. Open the document's folder or page | The document shows eSign **completed** and a signed copy is created, exactly as before this change | | |
| ☐ | H8 | A rejection is shown on the signer | New document with Vikram as a pending signer; dev-assisted: a developer posts a `doc.sign.rejected` notification for Vikram's email | 1. Open the Signatures tab as Meera | Vikram's row shows **Rejected** in red; the document is still waiting for signatures; support received an alert | | |
| ☐ | H9 | A signer is notified when the document is sent | Document approved and **not yet sent**; force signing order on; switch on; Priya and Rahul are CapHive users, Vikram is not | 1. As Meera click **Send For eSignatures** 2. Log in as Priya and open the bell 3. Open Priya's mailbox 4. Log in as Rahul and open the bell | Priya: bell entry **Your signature is requested: Subscription Agreement from Orion Capital**; an email with subject **Your signature is requested: Subscription Agreement**, body **Orion Capital has asked you to sign Subscription Agreement.**, a **Sign now** button and **You have also received a link from Digio by email. Either link works.** Rahul and Vikram: no CapHive entry or email yet | | |
| ☐ | H11 | The audit trail is filed with the signed copy | Every signer has signed a document that belongs to a fund, commitment or KYC | 1. Wait a minute. 2. Open the owner's Documents | **<Document> - Audit Trail** sits beside the **Signed** copy, tagged **Audit Trail**, locked. It opens as Digio's audit PDF listing each signer | | |
| ☐ | H10 | The next signer is notified when the earlier signature is confirmed | H9 and Priya signs (H1–H5) | 1. Log in as Rahul 2. Open the bell and his mailbox | Rahul has the same bell entry and email as Priya had; Priya did not get a second notification | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Email letter case is ignored | Signer email entered with capital letters (e.g. `Priya@LPFund.com`); Priya logs in as `priya@lpfund.com` | 1. Open the document | **Sign now** is shown | | |
| ☐ | E2 | A non-matching user gets nothing | Log in as a different investor user | 1. Open the document (if you can) | No banner and no **Sign now** | | |
| ☐ | E3 | Switch off hides everything | Untick **Enable Embedded Esign** for Orion Capital (Aarav) | 1. As Priya, open the document | No banner; the page looks as it did before this feature | | |
| ☐ | E4 | The switch is per entity | Switch on for Orion Capital only | 1. As Priya open Orion's document 2. As the Other Co user open Other Co's document | Banner on Orion's only | | |
| ☐ | E5 | Support impersonation cannot sign | Aarav (support) uses **login as** to become Priya | 1. Open the document 2. Open the signing page address directly | No banner; the signing page shows **This signature request is not available for your account.** | | |
| ☐ | E6 | A closed document is not signable | Cancel the document's eSignatures (Meera) | 1. As Priya open the document 2. Open the signing page address | No banner; the signing page reads **This document is no longer waiting for signatures.** | | |
| ☐ | E7 | Employee signers get **Sign now** on their own row | Rahul is next to sign | 1. Log in as Rahul 2. Open the document › **Signatures** tab | **Sign now** on Rahul's row only; none on Priya's or Vikram's rows | | |
| ☐ | E8 | Waiting turn: banner without a button | Priya has not signed | 1. Log in as Rahul 2. Open the document | **Your signature is requested on this document. You can sign after the previous signer has signed.** and no button | | |
| ☐ | E9 | Waiting turn: the signing page refuses to start | As E8 | 1. Open Rahul's signing page address directly | **It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed.** with no **Start signing** | | |
| ☐ | E10 | No signing order: everyone can sign | A document with **force signing order** off | 1. Open it as Priya, then as Rahul | Both see **Sign now** | | |
| ☐ | E11 | A non-signer cannot open the signing page by URL | Logged in as the Other Co user | 1. Paste Priya's signing page address | **This signature request is not available for your account.** and no document name or signer detail | | |
| ☐ | E12 | An already-signed signer cannot sign again | Priya Signed | 1. Open Priya's signing page address | **You have already signed this document.** with **Back to document** only | | |
| ☐ | E13 | The panel cannot load | Block `digio.in` in the browser (dev tools › block request domain) | 1. Open the signing page 2. Click **Start signing** | **We couldn't load the signing panel. Please check your connection and try again, or use the link in the email from Digio.** and a **Try again** button; nothing changed on the document | | |
| ☐ | E14 | Same flow on a phone | Phone, or a 390 px wide browser window | 1. Repeat H1–H4 | The same banner, page and panel start; no separate mobile flow; no horizontal scrolling | | |
| ☐ | E15 | The request to Digio carries no shortcut token | Dev-assisted | 1. Ask a developer to confirm, for a newly sent document, that the saved request log shows no access-token request | No access token requested or stored | | |
| ☐ | E16 | Documents sent before the switch can be signed | Send the document with the switch off, then switch it on | 1. As Priya open the document | **Sign now** is shown without re-sending | | |
| ☐ | E17 | The browser's "done" is not trusted | Dev-assisted: a developer posts a completion for Rahul's request while Rahul has not signed at Digio | 1. Click **Get eSignatures' updates** 2. Open the Signatures tab | Rahul remains **Requested**; no signed copy was created | | |
| ☐ | E18 | Closing the panel | H3 | 1. Close the Digio panel without finishing | **Signing was cancelled. You can start again whenever you are ready.** and **Start signing** is available again | | |
| ☐ | E19 | The sandbox panel is used on staging | Staging | 1. Open the signing page 2. Open the browser's network tab | The panel script is loaded from Digio's **sandbox** site (`ext.digio.in`), not the production site | | |
| ☐ | E20 | Completion is recorded | After H4; dev-assisted | 1. Ask a developer to show the document's eSign log | An entry shows Priya's email, the event name and the time | | |
| ☐ | E21 | Partial signing by notification | Two signers still pending | 1. One signer signs by email link 2. Open the Signatures tab | That signer **Signed**; document still waiting | | |
| ☐ | E22 | A failure notification | Dev-assisted: `doc.sign.failed` for Rahul with an error code | 1. Open the Signatures tab | Rahul **Failed** | | |
| ☐ | E23 | An unknown notification type is harmless | Dev-assisted: a notification with an event name CapHive does not know | 1. Open the Signatures tab | No error; nothing is marked Rejected | | |
| ☐ | E24 | An old-style notification still works | Dev-assisted: a notification with no event name but with signer statuses | 1. Open the Signatures tab | Signer statuses update as before | | |
| ☐ | E25 | A late rejection cannot undo a signature | Priya Signed; dev-assisted: `doc.sign.rejected` for Priya | 1. Open the Signatures tab | Priya stays **Signed** | | |
| ☐ | E26 | Rejection with no signer list | Dev-assisted: the rejection payload exactly as Digio documents it | 1. Open the Signatures tab | No error; the signer is **Rejected** | | |
| ☐ | E27 | Rejection for an email that is not a signer | Dev-assisted: `doc.sign.rejected` naming an unknown email | 1. Check the support inbox | Support received an alert naming the document and email; no signer changed | | |
| ☐ | E28 | A notification for an unknown document | Dev-assisted | 1. Post it 2. Check the response | CapHive answers success; support is told; no data changed | | |
| ☐ | E29 | Unordered document notifies everyone pending at send | A document with **force signing order** off; Priya and Rahul are CapHive users | 1. Send it for eSignature 2. Check both bells and mailboxes | Both Priya and Rahul have the bell entry and the email | | |
| ☐ | E30 | No notification for a non-user, or with the switch off | Vikram has no CapHive account; separately untick **Enable Embedded Esign** and send another document | 1. Send the document 2. Check CapHive for Vikram 3. In the second case check Priya's bell and mailbox | Nothing from CapHive exists for Vikram (he only has Digio's email); with the switch off Priya has no CapHive entry or email | | |
| ☐ | E31 | The notification opens the signing page | H9 | 1. As Priya click the bell entry 2. Later click **Sign now** in the email (log out first) | The bell entry opens Priya's signing page and is marked read; the email button logs her in if needed and opens the same page | | |
| ☐ | E32 | A signer is notified once | H10; dev-assisted: a developer re-sends the same Digio "signed" notification and you click **Get eSignatures' updates** | 1. Check Rahul's bell and mailbox | Rahul has exactly one bell entry and one email for this request | | |
| ☐ | E33 | Re-send notifies again | Priya is Signed and was notified | 1. As Meera use **Re-Send for eSignatures** 2. Check Priya's bell and mailbox | Priya has a new bell entry and a new email for the new request | | |
| ☐ | E34 | Investor with email off gets the bell entry only | The investor user from Test Setup, document sent to them | 1. Send the document 2. Check their bell and mailbox | The bell entry **Your signature is requested: …** exists; no CapHive email arrives | | |
| ☐ | E38 | A document with no owner completes | Document uploaded to a folder with no owner, sent for eSignature | 1. All signers sign. 2. Open the folder | Document shows **Completed**; the **Signed** copy and the audit trail are in the same folder | | |
| ☐ | E40 | Aadhaar signing works in the panel | Digio account with Aadhaar credits; signature type Aadhaar | 1. Log in as the signer. 2. **Sign now** 3. Complete Aadhaar in the panel | The panel completes, the thank-you message shows, the signer becomes **Signed**. Must pass before the switch is turned on for an entity that signs with Aadhaar | | |
| ☐ | E35 | Switching on is not retroactive | Document sent with the switch **off**, then switch on | 1. Aarav ticks **Enable Embedded Esign** 2. Check bells 3. Priya signs and it is confirmed 4. Check Rahul's bell | No notification appears when the switch is ticked; Rahul is notified when Priya's signature is confirmed | | |

## Error Cases

Rows marked "dev-assisted" cannot be produced by hand in the sandbox: a developer posts the code for the signer through the
signing page, or you record the automated run of the same row in Notes.

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | A wrong one-time code | H3 | 1. Type a wrong code in the Digio panel | **Signing didn't go through. Please check your details and try again.** with **Try again**; nobody is alerted. (Dev-assisted for the other retry codes: `AUTHENTICATION_FAILED`, `BIOMETRIC_DATA_MISMATCH`, `BIOMETRIC_LOCKED`, `INCORRECT_AADHAAR_ID`, `INVALID_ELECTRONIC_SIGNATURE`, `SIGNING_TIMED_OUT_ON_ESP`, `SIGNING_CANCELLED_ON_ESP`) | | |
| ☐ | X2 | The signing service is unavailable | H3, dev-assisted: `ERROR_FROM_ESP_UIDAI`, `ESP_UIDAI_DOWN`, `AADHAAR_ESIGN_TEMPORARILY_UNAVAILABLE`, `ESIGN_REQUEST_FAILURE` | 1. Post each code | **The signing service is temporarily unavailable. Please try again in a little while.** with **Try again** | | |
| ☐ | X3 | The signer's Aadhaar cannot be used | H3, dev-assisted: `AADHAAR_HAS_NO_MOBILE`, `AADHAAR_HAS_NO_MOBILE_OR_EMAIL`, `AADHAAR_SUSPENDED`, `AADHAAR_NOT_AUTHENTICABLE`, `AADHAAR_CANCELLED` | 1. Post each code | **Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method.** and no **Try again** | | |
| ☐ | X4 | Already signed / in progress | H3, dev-assisted: `ALREADY_SIGNED`, `DUPLICATE_REQUEST` | 1. Post each code 2. Open the Signatures tab | **You have already signed this document.** / **A signing request is already in progress. Please wait a moment and check the status again.**; CapHive checks with Digio (the status then matches Digio) | | |
| ☐ | X5 | Expired / method changed | H3, dev-assisted: `SIGN_REQUEST_EXPIRED`, `REQUESTED_SIGN_METHOD_DIFFERENT` | 1. Post each code | **This signing request has expired. Please ask the sender to send it again.** / **The signing method for this document has changed. Please ask the sender to send it again.**; no **Try again** | | |
| ☐ | X6 | Document not ready — both spellings | H3, dev-assisted: `DOCUMENT_NOT_READY_FOR_THIS_ACTION`, then `DOCUEMNT_NOT_READY_FOR_THIS_ACTION` | 1. Post each code | The same message both times: **This document isn't ready to be signed yet. Please try again in a few minutes.** | | |
| ☐ | X7 | Not your turn at Digio | H3, dev-assisted: `SIGNING_NOT_ALLOWED` | 1. Post it | **It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed.** | | |
| ☐ | X8 | Problems on our side | H3, dev-assisted: `NOT_SUFFICIENT_ENTITLEMENTS`, `INVALID_SIGNER`, `UNAUTHORIZED_ACCESS`, `SYSTEM_ERROR`, `UNKNOWN_ERROR` | 1. Post each code 2. Check the support inbox | **Something went wrong on our side and the team has been notified. Please try again later or contact support.** — no code shown; support received an alert with the code and document | | |
| ☐ | X9 | A code CapHive does not know | H3, dev-assisted: `SOMETHING_NEW` | 1. Post it | Same as X8 | | |
| ☐ | X10 | Failure is recorded | After X1 | 1. Ask a developer to show the document's eSign log | An entry shows the signer email, the code and the time | | |
| ☐ | X11 | Someone else cannot post a result | Logged in as Rahul | 1. Dev-assisted: post a completion to **Priya's** signature | Refused; nothing recorded; no status check started | | |
| ☐ | X13 | Support hears when the audit trail never arrives | Dev-assisted: a developer makes the audit trail request fail | 1. All signers sign | The document is **Completed** with its signed copy, there is no audit trail, and support gets an error report | | |
| ☐ | X14 | A failed signed-copy download does not complete the document | Dev-assisted: a developer makes the download fail | 1. All signers sign. 2. Restore the download. 3. Click **Get eSignatures' updates** | After step 1 the document is not Completed and support gets an error report; after step 3 it is Completed with its signed copy and audit trail | | |
| ☐ | X12 | A notification problem does not stop sending or Digio's updates | Dev-assisted: a developer makes notification delivery fail | 1. Send a document for eSignature 2. Have Digio send a signed notification 3. Check the document and the support inbox | The document is sent; signer statuses still update; Digio is still acknowledged; support received an alert naming the document | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Document page (Priya) | Open the Subscription Agreement | Banner **Your signature is requested on this document.** above the details, with **Sign now** | | |
| ☐ | J1.2 | Document page › **Sign now** | Click it | A full page load to the signing page (not a pop-up) | | |
| ☐ | J1.3 | Signing page | Look at it | Breadcrumb **Documents > Subscription Agreement > Sign**; document name; **Signing as: priya@…**; **Signer 1 of 3 - Investor Signatory**; **Method: Aadhaar eSign**; **Start signing**; **Back to document** | | |
| ☐ | J1.4 | Signing page › **Start signing** | Click it | The Digio panel opens inside the page; the CapHive header stays visible | | |
| ☐ | J1.5 | Digio panel | Complete verification and sign | Panel closes; the thank-you message appears; **Start signing** is gone | | |
| ☐ | J1.6 | Signing page › **Back to document** | Click it | Back on the document page; the banner is gone once Priya is **Signed** | | |
| ☐ | J2.1 | Document page (Rahul, before Priya signs) | Open the document | Waiting-turn banner and no button | | |
| ☐ | J2.2 | Document page (Rahul, after Priya signs) | Reload | Banner with **Sign now** | | |
| ☐ | J3.1 | Signatures tab (Rahul) | Open the tab | **Sign now** on Rahul's own row only | | |
| ☐ | J3.2 | Signatures tab (Meera) | After a rejection (H8) | A red **Rejected** badge on that signer | | |
| ☐ | J4.1 | Admin › Entities › Orion Capital (Aarav) | Open the entity | A tick-box labelled **Enable Embedded Esign** among the permissions | | |
| ☐ | J4.2 | Admin entity page › **Save** | Tick, save, then reload as Priya | **Sign now** appears | | |
| ☐ | J4.3 | Admin entity page › **Save** | Untick, save, reload as Priya | **Sign now** is gone; an email link still works | | |
| ☐ | J5.1 | Signing page after a retryable error | Cause X1 | **Try again** is shown; clicking it re-opens the panel | | |
| ☐ | J6.1 | Bell (Rahul, after Priya signs) | Open the bell / Notifications page | An unread entry **Your signature is requested: Subscription Agreement from Orion Capital** | | |
| ☐ | J6.2 | Bell entry | Click it | Rahul's signing page opens and the entry becomes read | | |
| ☐ | J6.3 | Email (Rahul) | Open the CapHive email | Subject **Your signature is requested: Subscription Agreement**; **Orion Capital has asked you to sign Subscription Agreement.**; a **Sign now** button; **You have also received a link from Digio by email. Either link works.**; Digio's own email is also in the mailbox | | |
| ☐ | J6.4 | Email › **Sign now** | Click it while logged out | The login page, then Rahul's signing page | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · — = not shown to this role · ! = wrong

| ID | Screen / action | Matching investor signer (Priya) | Matching employee signer (Rahul) | Other employee at Orion (Meera, company admin) | Support impersonating a signer | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | See the signature banner on the document | ✓ | ✓ | ✗ (no banner) | ✗ | ✗ |
| R2 | Open the signing page by address | ✓ | ✓ | ✗ (refusal text) | ✗ | ✗ |
| R3 | **Sign now** on the Signatures tab row | — (no tab) | ✓ own row only | ✗ (no button on any row) | ✗ | — |
| R4 | Complete signing in the panel | ✓ | ✓ | ✗ | ✗ | ✗ |
| R5 | See the **Rejected** badge | — | ✓ | ✓ | as the impersonated user | — |
| R6 | Tick **Enable Embedded Esign** in admin | ✗ | ✗ | ✗ | ✗ (unless CapHive admin) | ✗ |
| R7 | Receive the notification when it is their turn | ✓ (bell; email only if investor access has email on) | ✓ (bell and email) | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Alerts from this feature arrive | After a signature is confirmed, the signer sees the existing toast **Document - … eSign status updated**; the next signer receives the bell entry and email (H9, H10); support receives the alert emails for H8, E27, X8 and X12 with the document and signer named | | |
| ☐ | C2 | Dates on changed screens | N/A — no new dates are displayed | | |
| ☐ | C3 | Narrow / mobile width | The banner, signing page and Digio panel fit; buttons reachable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | A user in a different entity cannot see or reach any of this, even with a direct signing-page address, and the refusal text does not reveal whether the document exists | | |
| ☐ | C5 | Regression on modified screens | **Send For eSignatures**, **Re-Send for eSignatures**, **Cancel eSignatures**, the emailed Digio link, the Signatures tab and signed-copy creation all behave as before; **Re-Send** clears a Rejected signer back to blank | | |
| ☐ | C6 | Empty states | N/A — no new lists | | |
| ☐ | C7 | No blocked resources | With the switch on, the browser console shows no blocked-script or frame errors for `digio.in` on the signing page | | |
| ☐ | C8 | The signing email looks like other CapHive emails | Sender, branding and footer match other CapHive emails for the entity; the subject and body are exactly as in Test Setup; no dates appear; the **Sign now** link points to the platform | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
