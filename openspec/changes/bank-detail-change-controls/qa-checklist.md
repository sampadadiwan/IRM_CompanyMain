# Bank Detail Change Controls — Manual QA Checklist

<!-- STYLE: bullets and diagrams, not prose. One idea per bullet; a diagram per concept (model, lifecycle, flow); table cells a phrase each — longer reasoning goes in bullets under the table. -->

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the design's UI
> journeys (J), so a failure maps straight to the automated test that should have caught it.

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
| Environment | staging_in (52.66.163.132) — the only staging environment |
| Accounts | Horizon Capital: Meera Shah (Investor KYC Update + Approve), Ravi Iyer (company admin), Priya Nair (Investor KYC Update only), Kabir (Approve, no KYC read, no fund access). Kestrel Capital: Dev Menon, Asha Pillai (approvers). Solo Advisors: Kiran Rao (only approver). Investor user anil.kumar@example.in (approved, no tags) and sunita.kumar@example.in (tag Distribution) on investor Anil Kumar |
| Second entity | Northwind Partners — Omar Sheikh (company admin) |
| Seed data | As [business-rules.md › Shared setup](business-rules.md#shared-setup): Anil Kumar KYC verified with HDFC 50100012344821 / HDFC0001234 and Bank Verified ✓; Bina Shah verified; Chetan Rao submitted with blank bank fields; Horizon Fund I with "Q3 2026 Distribution" paying Anil ₹12,50,000 and Bina ₹8,00,000; Kestrel KYCs A Kumar, Thimmaiah Chengappa, ABC Private Limited, Anil Sharma; Solo Advisors KYC Leela Menon |
| Bank verification setting | Horizon and Solo: **off**. Kestrel: **on** (CapHive support sets Entity settings › Bank verification) |
| Bank check responses | Rows H12–H14, E47–E56, X13–X14 need the bank's reply controlled ("R KUMAR", "THIMMAIAH C", …). Ask a developer how staging's Digio access is set up; if replies can't be controlled, check only that a real account shows Verified and mark the rest "covered by automated scenario" |
| Background work | Emails and the bank check run in the background within ~2 minutes. If nothing arrives after 3 minutes, ask a developer to check the Sidekiq default queue. The distribution readiness check runs from Support agents › Distribution readiness › Run |
| Email inbox | Staging mail catcher (letter_opener / mail sink) for anil.kumar@example.in, ravi, meera |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Account change clears Bank Verified (checks off) | Anil's KYC unverified by Meera | 1. Meera changes account to 50100273107310 and saves | Bank Verified off straight after the save | | |
| ☐ | H2 | IFSC change clears Bank Verified | Anil's KYC unverified | 1. Meera changes IFSC to ICIC0004567 | Bank Verified off | | |
| ☐ | H3 | Checks on: cleared, then re-checked | Kestrel KYC "A Kumar" unverified; stub returns provider match | 1. Dev changes the account | Off right after save; ✓ again after the (stubbed) check runs | | |
| ☐ | H4 | Approver ticks Bank Verified | Anil's KYC unverified, Bank Verified off, no awaiting change | 1. Ravi ticks Bank Verified and saves | Bank Verified ✓ | | |
| ☐ | H5 | Fund user's change recorded | Anil's KYC unverified | 1. Meera changes account + IFSC | Record: maker Meera (firm), source screen, 4821 → 7310, HDFC0001234 → ICIC0004567, awaiting; note "Bank details changed on 09/11/2026 by Meera Shah — account ending 4821 → 7310. Waiting for a second approver to verify." | | |
| ☐ | H6 | Investor's change recorded | Anil's KYC link_sent | 1. Anil (magic link) changes account and submits | Record: maker Anil Kumar (investor), awaiting | | |
| ☐ | H7 | Investor emailed, masked | Anil's KYC unverified | 1. Meera changes account + IFSC | anil.kumar@example.in gets "Your bank details with Horizon Capital were changed", "Nov 09, 2026", "ending 4821 → ending 7310", both IFSCs, "View KYC"; no full number | | |
| ☐ | H8 | Approvers emailed, maker not | as H7 | 1. as H7 | Ravi gets "Bank details changed for Anil Kumar — a second approver must verify" + in-app notification, naming anil.kumar@example.in; Meera gets nothing | | |
| ☐ | H9 | Second approver verifies via popup | H5 (Meera's change awaiting) | 1. Ravi clicks Verify, sees cards, clicks "Verify KYC" | "Investor kyc was successfully verified."; note "Confirmed by Ravi Iyer on 10/11/2026" | | |
| ☐ | H10 | Investor-made change, any approver | H6 (Anil's change awaiting) | 1. Meera verifies | Verified; confirmed by Meera | | |
| ☐ | H11 | Only approver | Solo Advisors; Kiran changes Leela's account (after UnVerify) | 1. Kiran clicks Verify | Popup card "You are the only KYC approver at Solo Advisors — this is recorded as confirmed by the person who made the change."; confirm → verified, recorded "Only approver" | | |
| ☐ | H12 | Provider match | Stub: "ANIL SHARMA", fuzzy true | 1. Dev changes "Anil Sharma"'s account | Bank Verified ✓ | | |
| ☐ | H13 | Initial matches | Stub: "THIMMAIAH C", fuzzy false | 1. Dev changes "Thimmaiah Chengappa"'s account | ✓ | | |
| ☐ | H14 | Company suffixes | Stub: "ABC PVT LTD", fuzzy false | 1. Dev changes "ABC Private Limited"'s account | ✓ | | |
| ☐ | H15 | Distribution panel warning | H5 (Anil awaiting); Q3 2026 Distribution with journey, not emailed | 1. Ravi opens the distribution | Panel warns "1 KYC has bank details changed and not yet confirmed by a second approver" | | |
| ☐ | H16 | Readiness check flags | H5; readiness agent on the distribution | 1. Meera runs it | Bank Details step fails: "1 investor(s) have bank details changed and not yet confirmed. Ask a second approver to verify the KYC before releasing payment." | | |
| ☐ | H17 | Payments download column | H5 | 1. Meera downloads the distribution's payments | Last column "Unconfirmed Bank Change": Anil 09/11/2026, Bina blank | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Form still sends the tick | Anil's KYC unverified, Bank Verified ✓ shown ticked in the form | 1. Ravi changes account, leaves box ticked, saves | Bank Verified off | | |
| ☐ | E2 | Bank name / branch / type only | Anil's KYC unverified | 1. Meera changes branch "MG Road" → "Indiranagar", type → Current | Bank Verified ✓ unchanged | | |
| ☐ | E3 | Same IFSC re-typed | Anil's KYC unverified | 1. Meera saves IFSC "hdfc0001234 " | Bank Verified ✓ unchanged | | |
| ☐ | E4 | Full name only (checks off) | Anil's KYC unverified | 1. Meera changes full name to "Anil K Kumar" | Bank Verified ✓ unchanged | | |
| ☐ | E5 | Document Checks fill-in | Anil's KYC unverified; a check reads 50100273107310 from the cheque | 1. Meera clicks "Use document value" | Bank Verified off | | |
| ☐ | E6 | AI extraction overwrites | Anil's KYC unverified; extractor "always overwrite" with a bank rule | 1. Extraction job writes 50100273107310 | Bank Verified off | | |
| ☐ | E7 | JSON API update | Anil's KYC unverified; Ravi's API token | 1. PATCH `/investor_kycs/:id.json` with new account | 200; Bank Verified off | | |
| ☐ | E8 | Import Update Only, Verified blank | Anil's KYC unverified | 1. Meera imports a row with the new account | Row "Success"; Bank Verified off | | |
| ☐ | E9 | Verified KYC changed through Compare CKYC/KRA save | Anil's KYC **verified** | 1. Meera saves the compare form (id of Anil's KYC) with a new account | KYC no longer verified; Bank Verified off | | |
| ☐ | E10 | Verified KYC changed by import | Anil's KYC **verified**, journey on | 1. Meera imports Update Only row with IFSC ICIC0004567, Verified blank | KYC unverified; journey Verify task current, note "Bank details changed" | | |
| ☐ | E11 | Update-only employee's tick ignored | Anil's KYC unverified, Bank Verified off | 1. Priya opens Edit | No Bank Verified box; a crafted request with `bank_verified=1` saves other fields, flag stays off | | |
| ☐ | E12 | Update-only employee can't verify via API | Anil's KYC unverified | 1. Priya PATCHes `verified: true` | 200; KYC still unverified | | |
| ☐ | E13 | Approver's plain re-save keeps the tick | Anil's KYC unverified, Bank Verified ✓ | 1. Ravi changes only the address and saves | Bank Verified ✓ | | |
| ☐ | E14 | First fill | Chetan Rao's KYC, bank blank | 1. Chetan's contact fills account and IFSC | No record, no note | | |
| ☐ | E15 | Two changes before verify | H5 done | 1. Meera changes account again to …9902 | First record "replaced"; new one awaiting 7310 → 9902; note shows the new one | | |
| ☐ | E16 | Account cleared | Anil's KYC unverified | 1. Meera blanks the account number | Record "ending 4821 → none" | | |
| ☐ | E17 | Import source | Anil's KYC unverified | 1. Meera imports Update Only with new account | Record: source import, maker Meera | | |
| ☐ | E18 | No user (job) | Anil's KYC unverified | 1. AI extraction job with no acting user writes a new account | Record maker "System" | | |
| ☐ | E19 | Investor sees no note | H5 done | 1. Anil opens his KYC (signed in) | No change note; details as today | | |
| ☐ | E20 | Badge text (checks off) | H5 done | 1. Ravi opens the KYC | Bank Verified badge "Not verified — bank details changed" | | |
| ☐ | E21 | Audit trail keeps old values | H5 done | 1. Ravi opens KYC Actions › Audit Trail | Old account 50100012344821 and old Bank Verified listed | | |
| ☐ | E22 | Existing KYCs untouched at release | Bina Shah's KYC verified before release, no records | 1. Ravi opens Bina's KYC | No note; Verified and Bank Verified as before; no email sent | | |
| ☐ | E23 | No record stored with full numbers | H5 done | 1. Inspect the stored change record | Only "4821"/"7310" held; no full account number | | |
| ☐ | E24 | Contact tagged Distribution only | as H7 | 1. as H7 | sunita.kumar@example.in not emailed | | |
| ☐ | E25 | Contact added after the change | Change saved 09/11/2026 10:00 | 1. New contact approved 10:01, job runs 10:02 | New contact not emailed | | |
| ☐ | E26 | eSign email in the same save | Anil's KYC unverified | 1. Meera changes account and eSign emails to attacker@example.com | attacker@example.com not emailed | | |
| ☐ | E27 | Investor's own change | H6 | 1. — | Anil also gets the investor email ("If you asked for this, no action is needed") | | |
| ☐ | E28 | Job retried | H7's job already ran | 1. Same job runs again | Each contact still has one email; approvers one each | | |
| ☐ | E29 | Firm rewords the email | Horizon has a custom notification for "notify_bank_details_changed" | 1. as H7 | Anil's email uses the custom subject/body with masked digits | | |
| ☐ | E30 | Approver who cannot see the KYC | Horizon user Kabir (Approve, no KYC read, no fund access) | 1. as H7 | Kabir not emailed | | |
| ☐ | E31 | Branch-only edit sends nothing | Anil's KYC unverified | 1. Meera changes branch only | No emails | | |
| ☐ | E32 | Maker's button greyed | H5 | 1. Meera opens the KYC | Verify greyed; tooltip "You changed this KYC's bank details. Another KYC approver must verify it." | | |
| ☐ | E33 | Popup cards | H5 | 1. Ravi clicks Verify | Cards "New payout account confirmed" (••••7310, ICIC0004567), "You are the second person" (Meera Shah, 09/11/2026), "Investor already told" (anil.kumar@example.in) | | |
| ☐ | E34 | Popup shows Name needs review | Kestrel; Dev changed "A Kumar"'s account; check status "Name needs review: the bank has 'R KUMAR'" | 1. Asha clicks Verify | Extra card "Bank check: Name needs review" | | |
| ☐ | E35 | No awaiting change → no popup | Bina's KYC unverified, no change | 1. Ravi clicks Verify | Verified directly, as today | | |
| ☐ | E36 | Maker can still UnVerify | Anil's KYC verified, no change | 1. Meera clicks UnVerify | Unverified as today | | |
| ☐ | E37 | Bulk Verify by maker | H5 + Bina and Chetan unverified (Chetan with full details) | 1. Meera bulk-verifies the three | Bina and Chetan verified; Anil listed "Not verified — you changed the bank details; another approver must verify" | | |
| ☐ | E38 | Second approver added later | Kiran's change on Leela awaiting | 1. Solo adds Uma (Approve) before Kiran verifies | Kiran's Verify greyed; Uma can verify | | |
| ☐ | E39 | Approver who can't see the KYC doesn't count | Horizon: Meera + Kabir (Approve, cannot see Anil's KYC); Ravi deactivated | 1. Meera changes then clicks Verify | Only-approver card shown; confirm → recorded "Only approver" | | |
| ☐ | E40 | Import Verified = Yes with a change | Anil's KYC verified | 1. Meera imports Update Only row: new account, Verified Yes | "Success with warnings" — "Bank details changed — the KYC was left unverified for another approver to verify"; KYC unverified; awaiting | | |
| ☐ | E41 | Maker's later import can't verify | E40 done | 1. Meera imports the same row again (no further change), Verified Yes | Same warning; still unverified | | |
| ☐ | E42 | Second person's import confirms | E40 done | 1. Ravi imports the row, Verified Yes | "Success"; verified; confirmed by Ravi | | |
| ☐ | E43 | New KYC import unchanged | — | 1. Meera imports a new KYC with account and Verified Yes | Verified; no record; no email | | |
| ☐ | E44 | Maker can't tick Bank Verified, second approver can | H5 | 1. Meera opens Edit; Ravi opens Edit | Meera: no box; Ravi: box shown and saves ✓ | | |
| ☐ | E45 | System-made change | E18 | 1. Meera verifies | Verified; confirmed by Meera | | |
| ☐ | E46 | After confirmation the maker is free | H9 done | 1. Meera UnVerifies then Verifies (no new change) | Both work, no popup | | |
| ☐ | E47 | Look-alike initial | Stub: "R KUMAR", fuzzy false | 1. Dev changes "A Kumar"'s account | Off; "Name needs review: the bank has 'R KUMAR'" | | |
| ☐ | E48 | Surname only | Stub: "KUMAR", fuzzy false | 1. Dev changes "A Kumar"'s account | Off; Name needs review | | |
| ☐ | E49 | Title ignored | Stub: "MR A KUMAR", fuzzy false | 1. Dev changes "A Kumar"'s account | ✓ | | |
| ☐ | E50 | Extra middle name | Stub: "ANIL KUMAR SHARMA", fuzzy false | 1. Dev changes "Anil Sharma"'s account | ✓ (every KYC word is in the bank name) | | |
| ☐ | E51 | Different first name | Stub: "RAMESH SHARMA", fuzzy false | 1. Dev changes "Anil Sharma"'s account | Name needs review | | |
| ☐ | E52 | Word order swapped | Stub: "SHARMA ANIL", fuzzy false | 1. Dev changes "Anil Sharma"'s account | ✓ | | |
| ☐ | E53 | Stale result discarded | Check for …7310 started; Dev changes to …9902 before it finishes | 1. The first check completes | Its result is not applied; the …9902 check decides | | |
| ☐ | E54 | Checks off: no check runs | Horizon (off) | 1. Meera changes Anil's account | No provider call; Bank Verified stays off | | |
| ☐ | E55 | Secondary-sale offer keeps today's rule | Kestrel offer with seller "A Kumar"; stub "R KUMAR" | 1. Offer bank check runs | Offer bank verified as today (unchanged legacy path) | | |
| ☐ | E56 | Second approver accepts a review | E47 done | 1. Asha checks the cheque, ticks Bank Verified | ✓; Dev cannot tick it | | |
| ☐ | E57 | Cleared after second-person verify | H15–H17, then H9 | 1. Re-open / re-run / re-download | No warning; readiness KYC + bank steps pass; column blank | | |
| ☐ | E58 | Panel hidden after investors emailed | H5; distribution already emailed | 1. Ravi opens the distribution | No panel warnings (existing rule); readiness still flags | | |
| ☐ | E59 | Existing warnings still shown | H5 + one commitment with Skip Doc Gen | 1. Ravi opens the distribution | Both "1 commitment has Skip Doc Gen set and will not be emailed" and the bank-change warning | | |
| ☐ | E60 | Download columns keep their order | Any distribution | 1. Download | Every existing column in its existing position; new column last | | |
| ☐ | E61 | KYC journey warning | H5; Anil's KYC has a journey | 1. Ravi opens the KYC | Panel warns "Bank details changed on 09/11/2026 by Meera Shah — a different approver must verify" | | |
| ☐ | E62 | Other distribution panels unchanged | No awaiting changes | 1. Open the distribution | Panel and existing journey scenarios unchanged (Panel while notices are partly approved, Panel button runs the real control, Notices not used re-run) | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Save fails validation | Anil's KYC unverified | 1. Meera saves new account with a 21-character IFSC | Form error "Ifsc code is too long"; Bank Verified ✓ unchanged; account unchanged | | |
| ☐ | X2 | Investor forges bank result via magic link | Anil's KYC link_sent; Anil's magic link | 1. Submit form with `bank_verification_status=Verified` and a fake response | Saved; status and response unchanged | | |
| ☐ | X3 | Investor forges via JSON API | Anil signed in (bearer token) | 1. PATCH with `bank_verification_response` | 200; response unchanged | | |
| ☐ | X4 | Employee sends PAN result fields | Anil's KYC unverified | 1. Meera PATCHes `pan_verification_status=Verified` | Unchanged | | |
| ☐ | X5 | Failed save leaves no record | Anil's KYC unverified | 1. Meera saves new account with a 21-char IFSC | Form error; no record; no email | | |
| ☐ | X6 | No investor contact | Anil's investor has no approved contact for KYC emails | 1. Meera changes account | No investor email; Ravi's email says "No investor contact could be emailed — confirm the change with the investor by phone." | | |
| ☐ | X7 | Maker's direct request | H5 | 1. Meera PUTs `/investor_kycs/:id/toggle_verified` | Refused: "You changed this KYC's bank details, so another KYC approver must verify it."; still unverified | | |
| ☐ | X8 | Maker via JSON API | H5 | 1. Meera PATCHes `verified: true` | Ignored; still unverified | | |
| ☐ | X9 | Maker crafts Bank Verified tick | H5 | 1. Meera PATCHes `bank_verified: 1` | Ignored; still off | | |
| ☐ | X10 | Non-approver Verify | H5 | 1. Priya PUTs toggle_verified | Refused (not authorized), as today | | |
| ☐ | X11 | Other firm | H5 | 1. Omar (Northwind) opens Horizon's KYC page and PUTs toggle_verified | Both refused; no change detail shown | | |
| ☐ | X12 | Double click Verify | H5 | 1. Ravi submits the popup twice | Verified once; one confirmation; second request finds no awaiting change and makes no new record | | |
| ☐ | X13 | Account not found | Stub: `verified: false`, error "Invalid account" | 1. Dev changes "A Kumar"'s account | Off; status "Invalid account" (as today) | | |
| ☐ | X14 | Unreadable provider body | Stub returns non-JSON | 1. Dev changes the account | Off; raw body kept as today; no error page | | |
| ☐ | X15 | Bank check disabled in the agent | H5; agent `check_bank_details` = false | 1. Run readiness | Bank step "Skipped via configuration" (as today); KYC step fails "KYC not verified" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KYC page (Ravi) — Anil Kumar after Meera's change | Open it | ② amber note "Bank details changed on 09/11/2026 by Meera Shah — account ending 4821 → 7310. Waiting for a second approver to verify."; ④ badge "Not verified — bank details changed" | | |
| ☐ | J1.2 | Same | Click ③ "Audit trail" in the note | Audit Trail tab lists the old account 50100012344821 and who changed it | | |
| ☐ | J1.3 | Same | Click ① Verify | Popup "Verify KYC — Anil Kumar" with ▍Immediate Actions and cards ⑤ "New payout account confirmed" (ICICI ••••7310, ICIC0004567), ⑥ "You are the second person" (Meera Shah, 09/11/2026), ⑦ "Investor already told" (anil.kumar@example.in) | | |
| ☐ | J1.4 | Popup | Click ⑧ Verify KYC | Flash "Investor kyc was successfully verified."; note becomes grey "… confirmed by Ravi Iyer on 10/11/2026" | | |
| ☐ | J2.1 | KYC page (Meera, the maker) | Hover Verify | Button greyed; tooltip "You changed this KYC's bank details. Another KYC approver must verify it." | | |
| ☐ | J2.2 | KYC page (Meera) | Click UnVerify on a different verified KYC | Works as before | | |
| ☐ | J3.1 | KYC edit › Bank step (Priya) | Open | No "Bank Verified" box | | |
| ☐ | J3.2 | KYC edit › Bank step (Ravi) | Hover the Bank Verified box | Tooltip "Tick only after checking proof of the current account" | | |
| ☐ | J4.1 | Import › Investor KYC (Meera) | Upload an Update Only row changing Anil's account with Verified = Yes | Results sheet row "Success with warnings" — "Bank details changed — the KYC was left unverified for another approver to verify" | | |
| ☐ | J5.1 | KYC list › Bulk actions › Verify (Meera) | Select Anil, Bina, Chetan; run Verify | Bina and Chetan verified; error list shows Anil "Not verified — you changed the bank details; another approver must verify" | | |
| ☐ | J6.1 | Distribution page — Q3 2026 Distribution | Open | Journey panel warning "1 KYC has bank details changed and not yet confirmed by a second approver" | | |
| ☐ | J6.2 | Distribution › Payments › Download | Download | Last column "Unconfirmed Bank Change": Anil 09/11/2026, Bina blank | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Ravi (company admin) | Meera (Approve) — maker | Meera (Approve) — not maker | Priya (Update only) | Anil (investor) | Omar (other firm) |
|---|---|---|---|---|---|---|---|
| R1 | KYC page: see the bank change note | ✓ | ✓ | ✓ | ✓ (if she can see the KYC) | ✗ (no note) | ✗ (page refused) |
| R2 | Verify a KYC with an awaiting change | ✓ (popup) | ✗ greyed / refused | ✓ (popup) | ✗ | ✗ | ✗ |
| R3 | Verify a KYC with no awaiting change | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| R4 | UnVerify | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| R5 | Tick Bank Verified (edit form) | ✓ unless maker | ✗ (box hidden) | ✓ | ✗ (box hidden) | ✗ | ✗ |
| R6 | Send `verified: true` via API | ✓ unless maker | ✗ ignored | ✓ | ✗ ignored | ✗ ignored | ✗ refused |
| R7 | Send bank/PAN verification status or response | ✗ ignored | ✗ ignored | ✗ ignored | ✗ ignored | ✗ ignored | ✗ refused |
| R8 | Bulk Verify | ✓ | ✗ for own change (listed) | ✓ | ✗ "Not authorized" | ✗ | ✗ |
| R9 | Receive the approver email | ✓ | ✗ (maker) | ✓ | ✗ | ✗ | ✗ |
| R10 | Receive the investor email | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| R11 | Kiran (Solo Advisors, only approver) verifies own change | — | — | — | — | — | — (Kiran: ✓ with only-approver card) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails sent by this feature arrive | Investor email "Your bank details with Horizon Capital were changed" and approver email "Bank details changed for Anil Kumar — a second approver must verify"; dates shown as `Nov 09, 2026`; only last 4 digits; "View KYC" link opens the KYC after sign-in | | |
| ☐ | C2 | Dates on changed screens | Note, journey warning and distribution download follow the locale (e.g. `09/11/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | KYC page note and the Verify popup wrap without horizontal scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Omar (Northwind) cannot open Horizon's KYC, verify it, or see any change note, even with a direct URL | | |
| ☐ | C5 | Regression on modified screens | KYC page, edit form, bulk actions, import, distribution page, readiness agent and payments download do what they did before for KYCs without a bank change | | |
| ☐ | C6 | Empty states | KYCs with no bank change show no note; distributions with none show no new warning; download column blank | | |
| ☐ | C7 | Looks like the rest of CapHive | Note matches the Contact & Banking card style; popup matches Request Updates (Immediate Actions cards, outline buttons) | | |
| ☐ | C8 | No full page reloads for small actions | N/A — Verify is a full-page action today and stays one | | |
| ☐ | C9 | Explains itself | Greyed Verify, badge and Bank Verified box each have a tooltip; popup cards say what will happen | | |
| ☐ | C10 | Speed on a large entity | KYC page and payments download on the largest staging firm open in under ~2 s / the usual download time | | |
| ☐ | C11 | Existing data untouched after deploy | Before any edit, a sample of verified KYCs keep Verified and Bank Verified; no emails were sent at deploy | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging_in | | | |
