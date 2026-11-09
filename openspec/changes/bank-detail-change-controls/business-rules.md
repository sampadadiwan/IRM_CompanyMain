# Bank Detail Change Controls — Business Rules (H/E/X)

<!-- STYLE: bullets and diagrams, not prose. One idea per bullet; table cells a phrase each —
     longer reasoning goes in bullets under the table. -->

> **Audience:** Product, QA, developers. Every row becomes exactly one Cucumber scenario.
> **Companions:** [Proposal](proposal.md) · [Design](design.md) · [Specs](specs/)

---

## Contents

- [How to read this](#how-to-read-this)
- [Shared setup](#shared-setup)
- [1. Clear on change — Phase 1](#1-clear-on-change--phase-1)
- [2. Protected fields — Phase 1](#2-protected-fields--phase-1)
- [3. Change record and KYC page — Phase 2](#3-change-record-and-kyc-page--phase-2)
- [4. Change emails — Phase 2](#4-change-emails--phase-2)
- [5. Second person — Phase 3](#5-second-person--phase-3)
- [6. Bank check name rule — Phase 4](#6-bank-check-name-rule--phase-4)
- [7. Payout flags and journey warnings — Phase 5](#7-payout-flags-and-journey-warnings--phase-5)
- [8. Payout custom fields (SWIFT / IBAN) — Phase 6](#8-payout-custom-fields-swift--iban--phase-6)
- [Coverage](#coverage)

---

## How to read this

```mermaid
flowchart LR
    subgraph P1["Phase 1"]
        G1["1 Clear on change"]
        G2["2 Protected fields"]
    end
    subgraph P2["Phase 2"]
        G3["3 Change record"]
        G4["4 Change emails"]
    end
    subgraph P3["Phase 3"]
        G5["5 Second person"]
    end
    subgraph P4["Phase 4"]
        G6["6 Name rule"]
    end
    subgraph P5["Phase 5"]
        G7["7 Payout flags"]
    end
    subgraph P6["Phase 6"]
        G8["8 Payout custom fields"]
    end
    G1 --> BC["BC: kyc/bank-detail-<br/>change-controls"]
    G2 --> BC
    G3 --> BC
    G4 --> BC
    G5 --> BC
    G6 --> BC
    G7 --> BC
    G7 --> DJ["DJ: funds/capital-<br/>distribution-journey"]
    G8 --> BC
```

- **ID legend:** **H** = happy path · **E** = edge case · **X** = error (exception) case. IDs run across the
  whole file.
- **Spec scenario** column: `BC: <scenario>` = `kyc/bank-detail-change-controls`; `DJ: <scenario>` =
  `funds/capital-distribution-journey`.
- **Feature** column: the planned Cucumber file. Refusal rows live in `features/security/`.
- Every scenario carries a comment above it: `# E12 — Edge case: …`.
- Dates: screens use the `en` locale (`09/11/2026`); emails use `Nov 09, 2026`. "Today" is 09/11/2026.
- Bank check (penny drop) is always stubbed (`KycVerify#verify_bank`); no real provider call in tests.
- Account numbers: Anil's old account `50100012344821` (ending 4821), new `50100273107310` (ending 7310).

---

## Shared setup

| Record | Name | Key data |
|---|---|---|
| Firm (checks off) | Horizon Capital | Bank verification **off**; KYCs enabled |
| User | Meera Shah | Horizon employee; Investor KYC Update + **Approve**; KYC read |
| User | Ravi Iyer | Horizon **company admin** |
| User | Priya Nair | Horizon employee; Investor KYC Update only (no Approve) |
| Investor | Anil Kumar | Horizon investor |
| Investor contact | anil.kumar@example.in | Approved access, no tags (all topics), created 01/10/2026 |
| Investor contact | sunita.kumar@example.in | Approved access, tag "Distribution" only |
| KYC | Anil Kumar (Individual) | Verified by Ravi 01/10/2026; HDFC Bank, MG Road, Savings, 50100012344821, HDFC0001234; Bank Verified ✓ |
| KYC | Bina Shah (Individual) | Verified; no changes ever |
| KYC | Chetan Rao (Individual) | Submitted, not verified; bank fields **blank** |
| Fund / distribution | Horizon Fund I / Q3 2026 Distribution | Pays Anil Kumar ₹12,50,000 and Bina Shah ₹8,00,000; not yet emailed |
| Firm (checks on) | Kestrel Capital | Bank verification **on**; approvers Dev Menon and Asha Pillai |
| KYCs at Kestrel | A Kumar · Thimmaiah Chengappa · ABC Private Limited · Anil Sharma | Verified; each with an account and IFSC |
| Firm (one approver) | Solo Advisors | Only KYC approver: Kiran Rao (company admin); KYC Leela Menon, verified |
| Other tenant | Northwind Partners | Company admin Omar Sheikh |
| User (Phase 6) | Sam Joseph | CapHive support |
| Custom fields (Phase 6) | Horizon **Individual** KYC form | Text: SWIFT Code (`swift_code`), IBAN (`iban_code`), Intermediary Bank Name (`intermediary_bank_name`); check box: Foreign account? (`foreign_account`). **None marked** at the start |
| Custom fields (Phase 6) | Horizon **Non-Individual** KYC form | Text: SWIFT Code (`swift_code`) — never marked in these rows |
| Investor + KYC (Phase 6) | Farah Ali (Individual), Horizon | Contact farah.ali@example.ae (approved, no tags, created 01/10/2026); KYC verified by Ravi 01/10/2026; account 50100099001122 / HDFC0001234; SWIFT `EBILAEADXXX`; IBAN `AE070331234567890123456` (ending 3456); Bank Verified ✓; in Q3 2026 Distribution (₹5,00,000) |
| KYC (Phase 6) | Gulf Ventures LLC (Non-Individual), Horizon | Verified; SWIFT `NBADAEAAXXX` |
| Custom fields (Phase 6) | Kestrel and Solo Advisors KYC forms | SWIFT Code marked as a bank code (Kestrel "A Kumar" and Solo "Leela Menon" each hold a SWIFT) |

---

## 1. Clear on change — Phase 1

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Account change clears Bank Verified (checks off) | Anil's KYC unverified by Meera | Meera changes account to 50100273107310 and saves | Bank Verified off straight after the save | BC: Cleared immediately with checks off | features/core/bank_detail_change_reset.feature |
| H2 | IFSC change clears Bank Verified | Anil's KYC unverified | Meera changes IFSC to ICIC0004567 | Bank Verified off | BC: Account number changed | features/core/bank_detail_change_reset.feature |
| H3 | Checks on: cleared, then re-checked | Kestrel KYC "A Kumar" unverified; stub returns provider match | Dev changes the account | Off right after save; ✓ again after the (stubbed) check runs | BC: Cleared immediately with checks off | features/core/bank_detail_change_reset.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Form still sends the tick | Anil's KYC unverified, Bank Verified ✓ shown ticked in the form | Ravi changes account, leaves box ticked, saves | Bank Verified off | BC: Cleared even if the form sent the tick | features/core/bank_detail_change_reset.feature |
| E2 | Bank name / branch / type only | Anil's KYC unverified | Meera changes branch "MG Road" → "Indiranagar", type → Current | Bank Verified ✓ unchanged | BC: Branch name only | features/core/bank_detail_change_reset.feature |
| E3 | Same IFSC re-typed | Anil's KYC unverified | Meera saves IFSC "hdfc0001234 " | Bank Verified ✓ unchanged | BC: Same value re-typed | features/core/bank_detail_change_reset.feature |
| E4 | Full name only (checks off) | Anil's KYC unverified | Meera changes full name to "Anil K Kumar" | Bank Verified ✓ unchanged | BC: Branch name only | features/core/bank_detail_change_reset.feature |
| E5 | Document Checks fill-in | Anil's KYC unverified; a check reads 50100273107310 from the cheque | Meera clicks "Use document value" | Bank Verified off | BC: Cleared on a Document Checks fill-in | features/core/bank_detail_change_reset.feature |
| E6 | AI extraction overwrites | Anil's KYC unverified; extractor "always overwrite" with a bank rule | Extraction job writes 50100273107310 | Bank Verified off | BC: Cleared immediately with checks off | features/core/bank_detail_change_reset.feature |
| E7 | JSON API update | Anil's KYC unverified; Ravi's API token | PATCH `/investor_kycs/:id.json` with new account | 200; Bank Verified off | BC: Account number changed | features/core/bank_detail_change_reset.feature |
| E8 | Import Update Only, Verified blank | Anil's KYC unverified | Meera imports a row with the new account | Row "Success"; Bank Verified off | BC: Account number changed | features/core/bank_detail_change_reset.feature |
| E9 | Verified KYC changed through Compare CKYC/KRA save | Anil's KYC **verified** | Meera saves the compare form (id of Anil's KYC) with a new account | KYC no longer verified; Bank Verified off | BC: Import changes a verified KYC | features/core/bank_detail_change_reset.feature |
| E10 | Verified KYC changed by import | Anil's KYC **verified**, journey on | Meera imports Update Only row with IFSC ICIC0004567, Verified blank | KYC unverified; journey Verify task current, note "Bank details changed" | BC: Import changes a verified KYC | features/core/bank_detail_change_reset.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Save fails validation | Anil's KYC unverified | Meera saves new account with a 21-character IFSC | Form error "Ifsc code is too long"; Bank Verified ✓ unchanged; account unchanged | BC: Account number changed | features/core/bank_detail_change_reset.feature |

---

## 2. Protected fields — Phase 1

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H4 | Approver ticks Bank Verified | Anil's KYC unverified, Bank Verified off, no awaiting change | Ravi ticks Bank Verified and saves | Bank Verified ✓ | BC: Second approver ticks after review | features/security/bank_detail_change_fields.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E11 | Update-only employee's tick ignored | Anil's KYC unverified, Bank Verified off | Priya opens Edit | No Bank Verified box; a crafted request with `bank_verified=1` saves other fields, flag stays off | BC: Update-only employee's tick ignored | features/security/bank_detail_change_fields.feature |
| E12 | Update-only employee can't verify via API | Anil's KYC unverified | Priya PATCHes `verified: true` | 200; KYC still unverified | BC: Update-only employee's tick ignored | features/security/bank_detail_change_fields.feature |
| E13 | Approver's plain re-save keeps the tick | Anil's KYC unverified, Bank Verified ✓ | Ravi changes only the address and saves | Bank Verified ✓ | BC: Branch name only | features/security/bank_detail_change_fields.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X2 | Investor forges bank result via magic link | Anil's KYC link_sent; Anil's magic link | Submit form with `bank_verification_status=Verified` and a fake response | Saved; status and response unchanged | BC: Investor sends a forged response | features/security/bank_detail_change_fields.feature |
| X3 | Investor forges via JSON API | Anil signed in (bearer token) | PATCH with `bank_verification_response` | 200; response unchanged | BC: Investor sends a forged response | features/security/bank_detail_change_fields.feature |
| X4 | Employee sends PAN result fields | Anil's KYC unverified | Meera PATCHes `pan_verification_status=Verified` | Unchanged | BC: Investor sends a forged response | features/security/bank_detail_change_fields.feature |

---

## 3. Change record and KYC page — Phase 2

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H5 | Fund user's change recorded | Anil's KYC unverified | Meera changes account + IFSC | Record: maker Meera (firm), source screen, 4821 → 7310, HDFC0001234 → ICIC0004567, awaiting; note "Bank details changed on 09/11/2026 by Meera Shah — account ending 4821 → 7310. Waiting for a second approver to verify." | BC: Note on the KYC page | features/core/bank_detail_change_record.feature |
| H6 | Investor's change recorded | Anil's KYC link_sent | Anil (magic link) changes account and submits | Record: maker Anil Kumar (investor), awaiting | BC: Account number changed | features/core/bank_detail_change_record.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E14 | First fill | Chetan Rao's KYC, bank blank | Chetan's contact fills account and IFSC | No record, no note | BC: First fill is not a change | features/core/bank_detail_change_record.feature |
| E15 | Two changes before verify | H5 done | Meera changes account again to …9902 | First record "replaced"; new one awaiting 7310 → 9902; note shows the new one | BC: Later change replaces an awaiting one | features/core/bank_detail_change_record.feature |
| E16 | Account cleared | Anil's KYC unverified | Meera blanks the account number | Record "ending 4821 → none" | BC: Account number changed | features/core/bank_detail_change_record.feature |
| E17 | Import source | Anil's KYC unverified | Meera imports Update Only with new account | Record: source import, maker Meera | BC: Account number changed | features/core/bank_detail_change_record.feature |
| E18 | No user (job) | Anil's KYC unverified | AI extraction job with no acting user writes a new account | Record maker "System" | BC: Account number changed | features/core/bank_detail_change_record.feature |
| E19 | Investor sees no note | H5 done | Anil opens his KYC (signed in) | No change note; details as today | BC: Investor does not see the note | features/core/bank_detail_change_record.feature |
| E20 | Badge text (checks off) | H5 done | Ravi opens the KYC | Bank Verified badge "Not verified — bank details changed" | BC: Cleared immediately with checks off | features/core/bank_detail_change_record.feature |
| E21 | Audit trail keeps old values | H5 done | Ravi opens KYC Actions › Audit Trail | Old account 50100012344821 and old Bank Verified listed | BC: Note on the KYC page | features/core/bank_detail_change_record.feature |
| E22 | Existing KYCs untouched at release | Bina Shah's KYC verified before release, no records | Ravi opens Bina's KYC | No note; Verified and Bank Verified as before; no email sent | BC: Verified KYCs untouched at release | features/core/bank_detail_change_record.feature |
| E23 | No record stored with full numbers | H5 done | Inspect the stored change record | Only "4821"/"7310" held; no full account number | BC: Note on the KYC page | features/core/bank_detail_change_record.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X5 | Failed save leaves no record | Anil's KYC unverified | Meera saves new account with a 21-char IFSC | Form error; no record; no email | BC: Account number changed | features/core/bank_detail_change_record.feature |

---

## 4. Change emails — Phase 2

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H7 | Investor emailed, masked | Anil's KYC unverified | Meera changes account + IFSC | anil.kumar@example.in gets "Your bank details with Horizon Capital were changed", "Nov 09, 2026", "ending 4821 → ending 7310", both IFSCs, "View KYC"; no full number | BC: Investor emailed with masked account | features/core/bank_detail_change_emails.feature |
| H8 | Approvers emailed, maker not | as H7 | as H7 | Ravi gets "Bank details changed for Anil Kumar — a second approver must verify" + in-app notification, naming anil.kumar@example.in; Meera gets nothing | BC: Approvers told, maker not | features/core/bank_detail_change_emails.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E24 | Contact tagged Distribution only | as H7 | as H7 | sunita.kumar@example.in not emailed | BC: Investor emailed with masked account | features/core/bank_detail_change_emails.feature |
| E25 | Contact added after the change | Change saved 09/11/2026 10:00 | New contact approved 10:01, job runs 10:02 | New contact not emailed | BC: Contact added after the change is not emailed | features/core/bank_detail_change_emails.feature |
| E26 | eSign email in the same save | Anil's KYC unverified | Meera changes account and eSign emails to attacker@example.com | attacker@example.com not emailed | BC: eSign email in the KYC is not used | features/core/bank_detail_change_emails.feature |
| E27 | Investor's own change | H6 | — | Anil also gets the investor email ("If you asked for this, no action is needed") | BC: Investor-made change | features/core/bank_detail_change_emails.feature |
| E28 | Job retried | H7's job already ran | Same job runs again | Each contact still has one email; approvers one each | BC: Sent once on retry | features/core/bank_detail_change_emails.feature |
| E29 | Firm rewords the email | Horizon has a custom notification for "notify_bank_details_changed" | as H7 | Anil's email uses the custom subject/body with masked digits | BC: Investor emailed with masked account | features/core/bank_detail_change_emails.feature |
| E30 | Approver who cannot see the KYC | Horizon user Kabir (Approve, no KYC read, no fund access) | as H7 | Kabir not emailed | BC: Approvers told, maker not | features/core/bank_detail_change_emails.feature |
| E31 | Branch-only edit sends nothing | Anil's KYC unverified | Meera changes branch only | No emails | BC: Branch name only | features/core/bank_detail_change_emails.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X6 | No investor contact | Anil's investor has no approved contact for KYC emails | Meera changes account | No investor email; Ravi's email says "No investor contact could be emailed — confirm the change with the investor by phone." | BC: No investor contact | features/core/bank_detail_change_emails.feature |

---

## 5. Second person — Phase 3

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H9 | Second approver verifies via popup | H5 (Meera's change awaiting) | Ravi clicks Verify, sees cards, clicks "Verify KYC" | "Investor kyc was successfully verified."; note "Confirmed by Ravi Iyer on 10/11/2026" | BC: Second approver verifies | features/core/bank_detail_change_second_person.feature |
| H10 | Investor-made change, any approver | H6 (Anil's change awaiting) | Meera verifies | Verified; confirmed by Meera | BC: Investor-made change | features/core/bank_detail_change_second_person.feature |
| H11 | Only approver | Solo Advisors; Kiran changes Leela's account (after UnVerify) | Kiran clicks Verify | Popup card "You are the only KYC approver at Solo Advisors — this is recorded as confirmed by the person who made the change."; confirm → verified, recorded "Only approver" | BC: One-approver firm | features/core/bank_detail_change_second_person.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E32 | Maker's button greyed | H5 | Meera opens the KYC | Verify greyed; tooltip "You changed this KYC's bank details. Another KYC approver must verify it." | BC: Maker's Verify is greyed out | features/core/bank_detail_change_second_person.feature |
| E33 | Popup cards | H5 | Ravi clicks Verify | Cards "New payout account confirmed" (••••7310, ICIC0004567), "You are the second person" (Meera Shah, 09/11/2026), "Investor already told" (anil.kumar@example.in) | BC: Popup cards | features/core/bank_detail_change_second_person.feature |
| E34 | Popup shows Name needs review | Kestrel; Dev changed "A Kumar"'s account; check status "Name needs review: the bank has 'R KUMAR'" | Asha clicks Verify | Extra card "Bank check: Name needs review" | BC: Popup cards | features/core/bank_detail_change_second_person.feature |
| E35 | No awaiting change → no popup | Bina's KYC unverified, no change | Ravi clicks Verify | Verified directly, as today | BC: No change, no popup | features/core/bank_detail_change_second_person.feature |
| E36 | Maker can still UnVerify | Anil's KYC verified, no change | Meera clicks UnVerify | Unverified as today | BC: Maker can still unverify | features/core/bank_detail_change_second_person.feature |
| E37 | Bulk Verify by maker | H5 + Bina and Chetan unverified (Chetan with full details) | Meera bulk-verifies the three | Bina and Chetan verified; Anil listed "Not verified — you changed the bank details; another approver must verify" | BC: Maker's bulk Verify skips the KYC | features/core/bank_detail_change_second_person.feature |
| E38 | Second approver added later | Kiran's change on Leela awaiting | Solo adds Uma (Approve) before Kiran verifies | Kiran's Verify greyed; Uma can verify | BC: A second approver is added later | features/core/bank_detail_change_second_person.feature |
| E39 | Approver who can't see the KYC doesn't count | Horizon: Meera + Kabir (Approve, cannot see Anil's KYC); Ravi deactivated | Meera changes then clicks Verify | Only-approver card shown; confirm → recorded "Only approver" | BC: One-approver firm | features/core/bank_detail_change_second_person.feature |
| E40 | Import Verified = Yes with a change | Anil's KYC verified | Meera imports Update Only row: new account, Verified Yes | "Success with warnings" — "Bank details changed — the KYC was left unverified for another approver to verify"; KYC unverified; awaiting | BC: Update Only with Verified Yes | features/core/bank_detail_change_second_person.feature |
| E41 | Maker's later import can't verify | E40 done | Meera imports the same row again (no further change), Verified Yes | Same warning; still unverified | BC: Update Only with Verified Yes | features/core/bank_detail_change_second_person.feature |
| E42 | Second person's import confirms | E40 done | Ravi imports the row, Verified Yes | "Success"; verified; confirmed by Ravi | BC: Second approver verifies | features/core/bank_detail_change_second_person.feature |
| E43 | New KYC import unchanged | — | Meera imports a new KYC with account and Verified Yes | Verified; no record; no email | BC: New KYC import unchanged | features/core/bank_detail_change_second_person.feature |
| E44 | Maker can't tick Bank Verified, second approver can | H5 | Meera opens Edit; Ravi opens Edit | Meera: no box; Ravi: box shown and saves ✓ | BC: Second approver ticks after review | features/core/bank_detail_change_second_person.feature |
| E45 | System-made change | E18 | Meera verifies | Verified; confirmed by Meera | BC: Investor-made change | features/core/bank_detail_change_second_person.feature |
| E46 | After confirmation the maker is free | H9 done | Meera UnVerifies then Verifies (no new change) | Both work, no popup | BC: Maker can still unverify | features/core/bank_detail_change_second_person.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X7 | Maker's direct request | H5 | Meera PUTs `/investor_kycs/:id/toggle_verified` | Refused: "You changed this KYC's bank details, so another KYC approver must verify it."; still unverified | BC: Maker's direct request refused | features/security/bank_detail_change_second_person.feature |
| X8 | Maker via JSON API | H5 | Meera PATCHes `verified: true` | Ignored; still unverified | BC: Maker's direct request refused | features/security/bank_detail_change_second_person.feature |
| X9 | Maker crafts Bank Verified tick | H5 | Meera PATCHes `bank_verified: 1` | Ignored; still off | BC: Update-only employee's tick ignored | features/security/bank_detail_change_second_person.feature |
| X10 | Non-approver Verify | H5 | Priya PUTs toggle_verified | Refused (not authorized), as today | BC: Maker's direct request refused | features/security/bank_detail_change_second_person.feature |
| X11 | Other firm | H5 | Omar (Northwind) opens Horizon's KYC page and PUTs toggle_verified | Both refused; no change detail shown | BC: Other firm refused | features/security/bank_detail_change_second_person.feature |
| X12 | Double click Verify | H5 | Ravi submits the popup twice | Verified once; one confirmation; second request finds no awaiting change and makes no new record | BC: Second approver verifies | features/security/bank_detail_change_second_person.feature |

---

## 6. Bank check name rule — Phase 4

> Kestrel Capital (checks on). The stub sets `verified: true`, `beneficiary_name_with_bank` and
> `fuzzy_match_result`; the change is made by Dev Menon.

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H12 | Provider match | Stub: "ANIL SHARMA", fuzzy true | Dev changes "Anil Sharma"'s account | Bank Verified ✓ | BC: Initial accepted | features/core/bank_detail_name_match.feature |
| H13 | Initial matches | Stub: "THIMMAIAH C", fuzzy false | Dev changes "Thimmaiah Chengappa"'s account | ✓ | BC: Initial accepted | features/core/bank_detail_name_match.feature |
| H14 | Company suffixes | Stub: "ABC PVT LTD", fuzzy false | Dev changes "ABC Private Limited"'s account | ✓ | BC: Company suffixes | features/core/bank_detail_name_match.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E47 | Look-alike initial | Stub: "R KUMAR", fuzzy false | Dev changes "A Kumar"'s account | Off; "Name needs review: the bank has 'R KUMAR'" | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |
| E48 | Surname only | Stub: "KUMAR", fuzzy false | Dev changes "A Kumar"'s account | Off; Name needs review | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |
| E49 | Title ignored | Stub: "MR A KUMAR", fuzzy false | Dev changes "A Kumar"'s account | ✓ | BC: Initial accepted | features/core/bank_detail_name_match.feature |
| E50 | Extra middle name | Stub: "ANIL KUMAR SHARMA", fuzzy false | Dev changes "Anil Sharma"'s account | ✓ (every KYC word is in the bank name) | BC: Initial accepted | features/core/bank_detail_name_match.feature |
| E51 | Different first name | Stub: "RAMESH SHARMA", fuzzy false | Dev changes "Anil Sharma"'s account | Name needs review | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |
| E52 | Word order swapped | Stub: "SHARMA ANIL", fuzzy false | Dev changes "Anil Sharma"'s account | ✓ | BC: Initial accepted | features/core/bank_detail_name_match.feature |
| E53 | Stale result discarded | Check for …7310 started; Dev changes to …9902 before it finishes | The first check completes | Its result is not applied; the …9902 check decides | BC: Stale result discarded | features/core/bank_detail_name_match.feature |
| E54 | Checks off: no check runs | Horizon (off) | Meera changes Anil's account | No provider call; Bank Verified stays off | BC: Cleared immediately with checks off | features/core/bank_detail_name_match.feature |
| E55 | Secondary-sale offer keeps today's rule | Kestrel offer with seller "A Kumar"; stub "R KUMAR" | Offer bank check runs | Offer bank verified as today (unchanged legacy path) | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |
| E56 | Second approver accepts a review | E47 done | Asha checks the cheque, ticks Bank Verified | ✓; Dev cannot tick it | BC: Second approver ticks after review | features/core/bank_detail_name_match.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X13 | Account not found | Stub: `verified: false`, error "Invalid account" | Dev changes "A Kumar"'s account | Off; status "Invalid account" (as today) | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |
| X14 | Unreadable provider body | Stub returns non-JSON | Dev changes the account | Off; raw body kept as today; no error page | BC: Look-alike name goes to review | features/core/bank_detail_name_match.feature |

---

## 7. Payout flags and journey warnings — Phase 5

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H15 | Distribution panel warning | H5 (Anil awaiting); Q3 2026 Distribution with journey, not emailed | Ravi opens the distribution | Panel warns "1 KYC has bank details changed and not yet confirmed by a second approver" | DJ: Unconfirmed bank change warning | features/funds/bank_detail_change_payout_flags.feature |
| H16 | Readiness check flags | H5; readiness agent on the distribution | Meera runs it | Bank Details step fails: "1 investor(s) have bank details changed and not yet confirmed. Ask a second approver to verify the KYC before releasing payment." | BC: Readiness check flags it | features/funds/bank_detail_change_payout_flags.feature |
| H17 | Payments download column | H5 | Meera downloads the distribution's payments | Last column "Unconfirmed Bank Change": Anil 09/11/2026, Bina blank | BC: Download column | features/funds/bank_detail_change_payout_flags.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E57 | Cleared after second-person verify | H15–H17, then H9 | Re-open / re-run / re-download | No warning; readiness KYC + bank steps pass; column blank | DJ: Unconfirmed bank change warning | features/funds/bank_detail_change_payout_flags.feature |
| E58 | Panel hidden after investors emailed | H5; distribution already emailed | Ravi opens the distribution | No panel warnings (existing rule); readiness still flags | DJ: Warnings until emailed | features/funds/bank_detail_change_payout_flags.feature |
| E59 | Existing warnings still shown | H5 + one commitment with Skip Doc Gen | Ravi opens the distribution | Both "1 commitment has Skip Doc Gen set and will not be emailed" and the bank-change warning | DJ: Warnings until emailed | features/funds/bank_detail_change_payout_flags.feature |
| E60 | Download columns keep their order | Any distribution | Download | Every existing column in its existing position; new column last | BC: Download column | features/funds/bank_detail_change_payout_flags.feature |
| E61 | KYC journey warning | H5; Anil's KYC has a journey | Ravi opens the KYC | Panel warns "Bank details changed on 09/11/2026 by Meera Shah — a different approver must verify" | BC: Journey warning shown | features/funds/bank_detail_change_payout_flags.feature |
| E62 | Other distribution panels unchanged | No awaiting changes | Open the distribution | Panel and existing journey scenarios unchanged (Panel while notices are partly approved, Panel button runs the real control, Notices not used re-run) | DJ: Unconfirmed bank change warning | features/funds/bank_detail_change_payout_flags.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X15 | Bank check disabled in the agent | H5; agent `check_bank_details` = false | Run readiness | Bank step "Skipped via configuration" (as today); KYC step fails "KYC not verified" | BC: Readiness check flags it | features/funds/bank_detail_change_payout_flags.feature |

---

## 8. Payout custom fields (SWIFT / IBAN) — Phase 6

> Decided by the user on 2026-11-09 (design open question 1): a firm marks custom fields as payout fields; a
> change to a marked field follows **every** rule of §1–§5 and §7. Marks: **bank code** (shown in full, like
> IFSC) or **account identifier** (last 4 only, like the account number). The mark is stored as the key
> `payout_field` in the field's existing `validation_rules` JSON (user decision 2026-11-09 — no new column).
> "Today" is 09/11/2026.

```mermaid
flowchart LR
    R["Ravi marks SWIFT Code<br/>(bank code) and IBAN<br/>(account identifier)"] --> M["Meera changes<br/>Farah's SWIFT"]
    M --> G["Same save: Bank Verified off,<br/>record awaiting, emails"]
    G --> V{"Who verifies?"}
    V -- "Meera" --> N["Refused (greyed)"]
    V -- "Ravi" --> C["Confirmed"]
    U["Intermediary Bank Name<br/>(unmarked) edited"] --> I["Ignored: audit trail only"]
```

### Happy path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H18 | Admin marks SWIFT and IBAN | Horizon Individual KYC form, nothing marked | Ravi opens Farah's KYC › custom fields icon (side panel), sets SWIFT Code → "Bank code" and IBAN → "Account identifier", Save | "Individual KYC fields saved"; both rows show the payout icon; Form Types › Edit shows the same; Farah's KYC unchanged; no email | BC: Firm marks a payout field | features/core/bank_detail_payout_fields.feature |
| H19 | SWIFT change follows the bank-change rules | H18; Farah's KYC unverified by Meera | Meera changes SWIFT Code `EBILAEADXXX` → `NBADAEAAXXX`, Save | Bank Verified off; record awaiting, maker Meera, source screen, "SWIFT Code EBILAEADXXX → NBADAEAAXXX"; note "Bank details changed on 09/11/2026 by Meera Shah — SWIFT Code EBILAEADXXX → NBADAEAAXXX. Waiting for a second approver to verify." | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| H20 | Emails name the field; IBAN masked | H18; Farah's KYC unverified | Meera changes IBAN to `AE460260001015333438901` | farah.ali@example.ae gets "Your bank details with Horizon Capital were changed" with "IBAN ending 3456 → ending 8901", no full IBAN; Ravi gets the approver email; Meera nothing | BC: Marked field shown masked in emails | features/core/bank_detail_payout_fields.feature |
| H21 | Second approver confirms a SWIFT change | H19 | Meera hovers Verify; Ravi clicks Verify and confirms | Meera: greyed, "You changed this KYC's bank details. Another KYC approver must verify it."; Ravi's popup card "New payout account confirmed — SWIFT Code NBADAEAAXXX"; verified; "Confirmed by Ravi Iyer on 10/11/2026" | BC: Second approver verifies | features/core/bank_detail_payout_fields.feature |

### Edge cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E63 | SWIFT change on a **verified** KYC by import | H18; Farah verified | Meera imports an Update Only row: SWIFT Code `NBADAEAAXXX`, Verified = Yes | "Success with warnings" — "Bank details changed — the KYC was left unverified for another approver to verify"; KYC unverified; record source import, awaiting; emails | BC: Marked SWIFT change on a verified KYC | features/core/bank_detail_payout_fields.feature |
| E64 | Unmarked custom field ignored | H18; Farah unverified, Bank Verified ✓ | Meera changes Intermediary Bank Name | Bank Verified ✓ unchanged; no record; no email; Audit Trail lists the edit as today | BC: Unmarked custom field change ignored | features/core/bank_detail_payout_fields.feature |
| E65 | Marking doesn't retro-unverify | SWIFT unmarked; Farah verified, Bank Verified ✓ | Ravi marks SWIFT (as H18) | Farah still verified, Bank Verified ✓; no record; no email | BC: Marking does not change existing KYCs | features/core/bank_detail_payout_fields.feature |
| E66 | A change made before marking is not recorded later | SWIFT unmarked; Meera changed Farah's SWIFT on 08/11/2026 | Ravi marks SWIFT on 09/11/2026, then opens Farah's KYC | No note, no record for the 08/11 edit; Audit Trail shows it | BC: Marking does not change existing KYCs | features/core/bank_detail_payout_fields.feature |
| E67 | A mark applies to its own form only | H18 (Individual form only) | Meera changes Gulf Ventures LLC's (Non-Individual) SWIFT | No record; no email | BC: Unmarked custom field change ignored | features/core/bank_detail_payout_fields.feature |
| E68 | First fill of a marked field | H18; Farah's IBAN blank, Bank Verified ✓ | Farah (magic link) fills IBAN, submits | No record, no email (first fill); Bank Verified **off** — any change of a payout value clears it, as for account/IFSC (§1) | BC: First fill is not a change | features/core/bank_detail_payout_fields.feature |
| E69 | Marked value cleared | H18 | Meera blanks IBAN | Record "IBAN ending 3456 → none"; both emails | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| E70 | Same SWIFT re-typed | H18 | Meera saves SWIFT "ebilaead xxx" | No record; Bank Verified ✓ unchanged | BC: Same value re-typed | features/core/bank_detail_payout_fields.feature |
| E71 | Account and SWIFT in one save | H18; Farah unverified | Meera changes account to …7788 and SWIFT, Save | **One** record listing both; one investor email, one approver email | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| E72 | AI extraction writes a marked field | H18; extractor rule targets `swift_code`, "always overwrite" | Extraction job writes `NBADAEAAXXX` | Record source ai_extraction; Bank Verified off | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| E73 | Document Checks writes a marked field | H18; a check reads the IBAN from a bank letter | Meera clicks "Use document value" | Record source document_checks; Bank Verified off | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| E74 | Checks on: no bank check for a SWIFT-only change | Kestrel (checks on); "A Kumar" unverified, Bank Verified ✓ | Dev changes only SWIFT | Bank Verified off; **no** bank check runs (it checks account/IFSC only); Asha ticks Bank Verified after proof; Dev cannot | BC: Marked field change is a bank change | features/core/bank_detail_payout_fields.feature |
| E75 | Only approver, SWIFT change | Solo Advisors; Kiran changes Leela's SWIFT after UnVerify | Kiran clicks Verify | Only-approver card; confirm → verified, recorded "Only approver"; Leela's contact was emailed | BC: One-approver firm | features/core/bank_detail_payout_fields.feature |
| E76 | Payout flags see a SWIFT change | H19; Q3 2026 Distribution pays Farah, not emailed | Ravi opens the distribution; Meera downloads payments | Panel "1 KYC has bank details changed and not yet confirmed by a second approver"; "Unconfirmed Bank Change" 09/11/2026 on Farah's row | BC: Download column | features/core/bank_detail_payout_fields.feature |
| E77 | Support unmarks | H18 | Sam (support) sets IBAN → "No", Save | Unmarked; a later IBAN change makes no record | BC: Only support unmarks a payout field | features/core/bank_detail_payout_fields.feature |
| E78 | Rollout proposal — dry run | Firm with `swift_code`, `iban_code` text fields and a `swift_code_in_case_of_foreign_bank_account` check box | Support runs `bin/rails bank_detail_changes:propose_payout_fields FIRM_ID=<id>` | Lists SWIFT Code → bank code, IBAN → account identifier, with filled-value counts; check box not listed; nothing saved | BC: Rollout proposal marks nothing without EXECUTE | features/core/bank_detail_payout_fields.feature |
| E79 | Rollout proposal — EXECUTE=1 | E78; firm admin agreed in the support ticket | Same command with `EXECUTE=1` | Listed fields marked; no KYC changed; no email | BC: Rollout proposal marks nothing without EXECUTE | features/core/bank_detail_payout_fields.feature |
| E80 | Editing a marked field's rules keeps the mark | H18 | Ravi sets SWIFT Code's max length to 11 in Form Types › Edit, Save; then Meera changes Farah's SWIFT | SWIFT Code still marked "Bank code" (mark and max-length rule sit side by side in `validation_rules`); Meera's change is recorded | BC: Firm marks a payout field | features/core/bank_detail_payout_fields.feature |

### Error cases

| # | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X16 | Non-admin can't mark | Priya given Form Types access (`enable_form_types`), not company admin | Priya opens Form Custom Fields › Edit for SWIFT Code; then sends `payout_field=code` | No "Payout field" control; field stays unmarked | BC: Firm marks a payout field | features/security/bank_detail_payout_fields.feature |
| X17 | Admin can't unmark | H18 | Ravi sets IBAN → "No" in the side panel, and again in Form Types › Edit | Both refused: "Payout fields can only be unmarked by CapHive support."; IBAN stays marked | BC: Only support unmarks a payout field | features/security/bank_detail_payout_fields.feature |
| X18 | Admin can't delete a marked field | H18 | Ravi looks for ✕ on SWIFT Code in the side panel; sends Form Custom Fields DELETE | No ✕ shown (locked chip "Support"); DELETE refused with the same message; field kept | BC: Only support unmarks a payout field | features/security/bank_detail_payout_fields.feature |
| X19 | Only text fields on KYC forms | H18 | Ravi sends a mark for "Foreign account?" (check box), for a TextArea on the KYC form and for a text field on the Investor form | All refused: "Only text fields on a KYC form can be payout fields"; nothing saved | BC: Only text fields on KYC forms can be marked | features/security/bank_detail_payout_fields.feature |
| X20 | Other firm | — | Omar (Northwind) sends the side panel save and a Form Types update for Horizon's KYC form type | Not found / refused; nothing marked | BC: Other firm refused | features/security/bank_detail_payout_fields.feature |

**Why these rows**
- **H19 vs E64:** the same kind of edit (a custom text field) is a bank change only when the field is marked — the
  mark is the whole switch.
- **E65/E66:** marking is a configuration change, never a data change: no KYC is touched, nothing back-dated.
- **E68:** first fill clears Bank Verified for the same reason as a first account fill — the payout details now hold
  something nobody checked — but it is not a *change*, so no record and no email.
- **E74:** the penny drop proves the Indian account + IFSC only; it must not re-tick Bank Verified after a SWIFT edit.
- **E80:** the mark shares `validation_rules` with real rules; the per-key `vr_*` setters must leave it alone.
- **X17/X18:** unmarking is the loosening direction (after it, one person could change the SWIFT alone), so it is
  CapHive-support-only — the same lock Calculation fields already use.

---

## Coverage

```mermaid
flowchart LR
    S["51 spec scenarios<br/>(BC 50 + DJ new 1)"] --> R["Every scenario named in<br/>≥ 1 Spec scenario cell"]
    R --> F["Every row → 1 Cucumber scenario<br/>with an ID — path comment"]
```

| Group | H | E | X | Total |
|---|---|---|---|---|
| 1 Clear on change | 3 | 10 | 1 | 14 |
| 2 Protected fields | 1 | 3 | 3 | 7 |
| 3 Change record | 2 | 10 | 1 | 13 |
| 4 Change emails | 2 | 8 | 1 | 11 |
| 5 Second person | 3 | 15 | 6 | 24 |
| 6 Name rule | 3 | 10 | 2 | 15 |
| 7 Payout flags | 3 | 6 | 1 | 10 |
| 8 Payout custom fields | 4 | 18 | 5 | 27 |
| **Total** | **21** | **80** | **20** | **121** |

- `features/security/bank_detail_change_fields.feature`, `features/security/bank_detail_change_second_person.feature`
  and `features/security/bank_detail_payout_fields.feature` gather every refusal row (forged fields, maker, non-approver, other firm, direct requests).
- The four unchanged DJ scenarios are proved by the existing distribution-journey features, re-run in the
  phase 5 gate (E62).
- An edge case found during apply gets a new row here **and** a scenario, never a scenario alone.
