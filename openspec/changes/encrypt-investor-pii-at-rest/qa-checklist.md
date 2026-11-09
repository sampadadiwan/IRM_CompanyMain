# Encrypt investor PII at rest — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the
> design's UI journey (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J1.3 = journey 1, step 3) · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | staging.in (52.66.163.132) after deploy 1; repeat the J and C rows after deploy 2 |
| Accounts | Meera Iyer (company admin, Kestrel Capital), Rohan Shah (employee with KYC rights), Anil Mehta (investor), a CapHive super admin |
| Second entity | Banyan Partners with user Kabir, holding its own KYC for Anil Mehta with PAN `ABCPM1234K` |
| Seed data | Exactly the [shared setup](business-rules.md#shared-setup): KYCs 1-5, KGF-001, Q3 2026 payout, the secondary sale with Anil's offer and Banyan Buyers' interest, Ledger Advisors fee, Anil's CKYC lookup and AML report, "Quarterly statement" notification, "LP bank list" saved report |
| Background work | Rows that say "Ask CapHive ops to run" need an ops engineer on the staging box (`bundle exec rake pii_encryption:<task>[staging.in]`, add `EXECUTE=1` where the row says so). "Read the stored (raw) value" means a developer runs a read-only SQL `SELECT` on the column and tells you whether the typed value appears in it |
| Search index | Ask ops to rebuild the KYC and Offer search indexes after the conversion, before the search-box rows (H21–H23, E38–E42, X6) |
| Region wording | Rows written with `[test]` use `[staging.in]` on staging |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | KYC values stored encrypted, shown plain | Rohan signed in | 1. He saves KYC 1 2. Ask a developer to read the stored (raw) value | Raw PAN and bank contain neither `ABCPM1234K` nor `50100234567812`; KYC page shows both | | |
| ☐ | H2 | KYC spreadsheet shows plain values | KYC 1 saved | 1. Rohan downloads KYCs › Individual xlsx | Row shows `ABCPM1234K`, `50100234567812`, `HDFC0001234` | | |
| ☐ | H3 | Template and PDF password use plain PAN | KYC 1 on KGF-001; "Quarterly statement" protects PDFs | 1. A statement is generated and emailed | Document prints `ABCPM1234K`; the PDF opens with `ABCPM1234K` | | |
| ☐ | H4 | Every in-scope table stores ciphertext | Offer, interest, fee, CKYC lookup, AML report created | 1. Raw columns read 2. Ask a developer to read the stored (raw) value | No raw PAN / bank / IFSC / reply column holds its plain value | | |
| ☐ | H5 | Same PAN same raw, same bank different raw | KYC 1 and KYC 5 saved | 1. Raw values compared 2. Ask a developer to read the stored (raw) value | Raw PANs equal; raw bank values differ | | |
| ☐ | H6 | Dry run | KYC 1, 2, 4 plain (written without encryption) | 1. Ask CapHive ops to run: `pii_encryption:encrypt[test]` without EXECUTE 2. Ask a developer to read the stored (raw) value | Reports `investor_kycs: PAN 3, bank 2…`; raw values unchanged | | |
| ☐ | H7 | Conversion | Same | 1. Run with EXECUTE=1 2. Ask a developer to read the stored (raw) value | Raw values encrypted; KYC 2 lowercase PAN upper-cased; `updated_at` unchanged; 0 new audits; 0 emails | | |
| ☐ | H8 | Verify | After H7 | 1. Ask CapHive ops to run: `pii_encryption:verify[test]` | `0 plain values left` | | |
| ☐ | H9 | Reverse | After H7 | 1. Ask CapHive ops to run: `pii_encryption:decrypt[test]` EXECUTE=1, then verify 2. Ask a developer to read the stored (raw) value | Raw values plain again; verify `0 encrypted values` | | |
| ☐ | H10 | New bank change hidden in history | KYC 1 | 1. Rohan changes bank to `60200987654331` and bank name to ICICI Bank 2. Ask a developer to read the stored (raw) value | History: Rohan, time, "Bank Account Number changed (value hidden)", "Bank Name HDFC Bank → ICICI Bank"; raw audit row has neither number | | |
| ☐ | H11 | Old entries rewritten | Audit row on KYC 1: PAN `ABCPM1234K` → `ABCPM1234L` (written before encryption) | 1. Ask CapHive ops to run: `pii_encryption:scrub_audits[test]` EXECUTE=1 | Row keeps user and time; neither PAN in the row | | |
| ☐ | H12 | Import updates by PAN typed differently | KYC 1 encrypted | 1. KYC import row "Pan/Tax Id" `abcpm1234k `, "Update Only" Yes, address changed | KYC 1 updated; KYC count unchanged | | |
| ☐ | H13 | KYC document import matches PAN | KYC 1 | 1. Document import row "PAN/Tax ID" `ABCPM1234K` | Document attached to KYC 1 | | |
| ☐ | H14 | Filter PAN equals | KYC 1, 2 | 1. KYC list "PAN equals ABCPM1234K" | KYC 1 and KYC 5 listed, KYC 2 not | | |
| ☐ | H15 | Filter through related KYC | KGF-001 on KYC 1 | 1. Commitments "Investor Kyc PAN equals ABCPM1234K" | KGF-001 listed | | |
| ☐ | H16 | CKYC comparison uses lookup | CKYC lookup for Anil | 1. Rohan opens CKYC/KRA comparison on KYC 1 | The lookup's name and address shown | | |
| ☐ | H17 | AML report reused | AML report for Anil | 1. AML screening runs again on KYC 1 | Same report updated; count unchanged | | |
| ☐ | H18 | PAN contains refused | Meera on KYCs | 1. Filter "PAN contains ABCPM" | PAN message shown; all 5 KYCs listed | | |
| ☐ | H19 | Bank equals refused | Meera on KYCs | 1. "Bank Account Number equals 50100234567812" | Bank message; filter not applied | | |
| ☐ | H20 | Picker offers supported conditions | Meera opens Filter | 1. Picks PAN, then Bank Account Number | PAN: equals, not equals, is blank, is present; Bank: is blank, is present | | |
| ☐ | H21 | Full PAN, lowercase | Index rebuilt | 1. Search `abcpm1234k` | KYC 1 and KYC 5 | | |
| ☐ | H22 | Full bank account | Index rebuilt | 1. Search `50100234567812` | KYC 1 and KYC 5 | | |
| ☐ | H23 | Offer search by full PAN | Offer index rebuilt | 1. Offers › search `ABCPM1234K` | Anil's offer | | |
| ☐ | H24 | Related PAN as Value | Commitments report | 1. Column "Investor Kyc › PAN" as Value | KGF-001 row shows `ABCPM1234K` | | |
| ☐ | H25 | Related bank as Latest | Investors report | 1. "Investor Kycs › Bank Account Number" as Latest | Anil row shows the latest KYC's bank number | | |
| ☐ | H26 | Chatbot count still works | FM support chatbot for Kestrel | 1. Query `SELECT COUNT(*) FROM investor_kycs WHERE verified = 1 AND entity_id IN ({ENTITY_ID})` | Count returned | | |
| ☐ | H27 | Database download readable | Kestrel | 1. Meera generates the database download | KYC table: `ABCPM1234K`, `50100234567812`; offers and fees readable | | |
| ☐ | H28 | Admin search by name | Super admin | 1. /admin offers search `Anil` | Anil's offer | | |
| ☐ | H29 | Pre-flight | Test keys present | 1. Ask CapHive ops to run: `pii_encryption:preflight[test]` | "Keys present, fingerprint …"; counts per table and field; no writes | | |
| ☐ | H30 | Developer scrub | Encrypted rows written with a different ("production") key | 1. Ask CapHive ops to run: `pii_encryption:scrub_dev_copy` EXECUTE=1 in development | KYC 1 page opens with a fake PAN; KYC 1 and KYC 5 share one fake PAN; bank numbers fake | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Lowercase PAN with spaces | Rohan edits KYC 2 | 1. PAN ` aqzpn5521l ` saved | KYC shows `AQZPN5521L` | | |
| ☐ | E2 | Blank bank counts as missing | KYC 4 bank `""` | 1. Q3 2026 payout warnings evaluated | Distribution warning "1 KYC has no bank account number" (KYC 4) | | |
| ☐ | E3 | Foreign tax ID upper-cased | KYC 3 | 1. Saved | Shows `US-84-1234567` | | |
| ☐ | E4 | PAN at the 15-character limit | KYC 2 | 1. PAN `ABCDEFGHIJ12345` saved | Saves; shows the same 15 characters | | |
| ☐ | E5 | Bank account at the 40-character limit | KYC 2 | 1. 40-digit account saved | Saves; shows the same 40 digits | | |
| ☐ | E6 | Verification replies round-trip | Bank verification stubbed: beneficiary "ANIL MEHTA" | 1. Verify bank job runs on KYC 1 2. Ask a developer to read the stored (raw) value | `bank_verified` true; reply hash readable on the page; raw reply holds no "ANIL MEHTA" | | |
| ☐ | E7 | CKYC reply JSON round-trips | CKYC lookup for Anil | 1. Comparison page opened 2. Ask a developer to read the stored (raw) value | Name and address fields from the reply shown; raw response holds no name | | |
| ☐ | E8 | Investor fills KYC by emailed link | Anil opens his KYC link | 1. He saves PAN `abcpm1234k` 2. Ask a developer to read the stored (raw) value | KYC shows `ABCPM1234K`; raw PAN not plain | | |
| ☐ | E9 | IFSC tidied | KYC 2 | 1. IFSC ` icic0000456` saved | Shows `ICIC0000456` | | |
| ☐ | E10 | Blank PAN stays blank | KYC saved with `validate: false` and PAN `""` (WithFolder path) | 1. Raw PAN read 2. Ask a developer to read the stored (raw) value | NULL; KYC saved | | |
| ☐ | E11 | Interrupted run resumes | Batch size 1; run stops after KYC 1 | 1. Run again | KYC 2 and 4 converted, KYC 1 skipped; verify 0 | | |
| ☐ | E12 | Soft-deleted rows converted | KYC 2 soft-deleted, plain | 1. Conversion runs 2. Ask a developer to read the stored (raw) value | KYC 2 raw PAN encrypted | | |
| ☐ | E13 | Lookup finds plain and encrypted rows | Window open; KYC 1 plain, KYC 5 encrypted | 1. "PAN equals ABCPM1234K" | Both listed | | |
| ☐ | E14 | Editing a plain row encrypts it | Window open; KYC 2 plain | 1. Rohan changes KYC 2 address 2. Ask a developer to read the stored (raw) value | Raw PAN now encrypted | | |
| ☐ | E15 | Re-run with nothing to do | After H7 | 1. Conversion again | `0 to encrypt`; no writes | | |
| ☐ | E16 | Restore of pre-conversion data | Window closed; KYC 2 restored plain | 1. Conversion re-run, then KYC 2 opened | Page shows `AQZPN5521L` | | |
| ☐ | E17 | Search index not touched by conversion | After H7 | 1. Index update count read | 0 index updates during the run (reindex is a separate step) | | |
| ☐ | E18 | Clean-up dry run | Same as H11 | 1. Without EXECUTE | Reports `InvestorKyc: 1 entry`; row unchanged | | |
| ☐ | E19 | Other fields kept | Old row also has `bank_name` HDFC → ICICI | 1. Clean-up runs | `bank_name` change kept; bank number hidden | | |
| ☐ | E20 | Clean-up re-run | After H11 | 1. Run again | `0 entries to update` | | |
| ☐ | E21 | Offer and interest history hidden | Anil's offer | 1. Rohan changes its PAN | Offer history: "PAN changed (value hidden)" | | |
| ☐ | E22 | Create entry hidden | — | 1. Rohan creates KYC 2 | Create audit row shows PAN, bank, IFSC as "(value hidden)" | | |
| ☐ | E23 | KYC PAN change updates its CKYC lookups | CKYC lookup for `ABCPM1234K` | 1. KYC update service runs on KYC 1 | Lookup found and refreshed | | |
| ☐ | E24 | Duplicate CKYC lookup | Lookup exists | 1. Second ckyc lookup for KYC 1, PAN `ABCPM1234K` | "should be unique for the same source and KYC" | | |
| ☐ | E25 | PAN is blank | KYC with no PAN exists | 1. "PAN is blank" | Only that KYC listed | | |
| ☐ | E26 | Bank is blank | KYC 4 | 1. "Bank Account Number is blank" | KYC 4 listed only | | |
| ☐ | E27 | IFSC equals in lowercase | KYC 1 | 1. "IFSC Code equals hdfc0001234" | KYC 1 and KYC 5 listed | | |
| ☐ | E28 | PAN not equals | KYC 1, 2, 4 | 1. "PAN not equals ABCPM1234K" | KYC 2, 4 listed (blank-PAN KYCs follow today's not-equals rule) | | |
| ☐ | E29 | Import "Update Only = No" with existing PAN | KYC 1 | 1. Import row PAN `ABCPM1234K`, Update Only No | Row error "Skipping: a KYC already exists for Anil Mehta (Anil Mehta, PAN ABCPM1234K). Set Update Only to Yes to update it" | | |
| ☐ | E30 | Import matches a KYC with blank PAN | KYC for Priya with PAN blank | 1. Import Update Only Yes, "Pan/Tax Id" `AQZPN5521L`, name Priya Nair | That KYC updated with the PAN | | |
| ☐ | E31 | Related condition in a URL | — | 1. GET commitments with `q[investor_kyc_PAN_cont]=ABCPM` | PAN message; KGF-001 listed (condition not applied) | | |
| ☐ | E32 | Saved report link | Saved report URL with `q[PAN_start]=ABC` | 1. Meera opens it | PAN message | | |
| ☐ | E33 | AI report assistant link | Assistant returns a URL with `PAN_cont` (stubbed) | 1. Meera follows it | PAN message | | |
| ☐ | E34 | Sort by PAN | — | 1. GET KYCs with `q[s]=PAN asc` | Default order; 5 KYCs | | |
| ☐ | E35 | Unrelated filters untouched | — | 1. "Investing Entity contains Anil" | KYC 1 and KYC 5 listed, no message | | |
| ☐ | E36 | Mixed conditions | — | 1. "Investing Entity contains Anil" AND "PAN contains ABC" | PAN message; no condition applied (the whole filter is refused) | | |
| ☐ | E37 | Deleted-records list | Company admin on deleted KYCs | 1. "PAN contains ABC" | PAN message | | |
| ☐ | E38 | Part of a PAN | — | 1. Search `ABCPM` | No KYC listed; ⓘ hint on the box | | |
| ☐ | E39 | Name prefix still works | — | 1. Search `Ani` | KYC 1 and KYC 5 | | |
| ☐ | E40 | Index holds no values | Index rebuilt | 1. Index documents read | No `ABCPM1234K`, no `50100234567812` in any document | | |
| ☐ | E41 | PAN edited | KYC 2 PAN changed to `AQZPN5521M` | 1. Search old, then new | Old: none; new: KYC 2 | | |
| ☐ | E42 | PAN with spaces typed | — | 1. Search ` ABCPM1234K ` | KYC 1 and KYC 5 | | |
| ☐ | E43 | Saved report using List | "LP bank list" | 1. Meera opens it | Column shows Value per investor + tooltip; no encrypted text | | |
| ☐ | E44 | Pivot categories | Investors report with related KYCs | 1. Pivot form opened | PAN, bank, IFSC not offered | | |
| ☐ | E45 | Sort by PAN | KYC report | 1. Sort by PAN requested | Default order | | |
| ☐ | E46 | Count | Investors report | 1. Related bank as Count | Anil: 2 (KYC 1, KYC 5) | | |
| ☐ | E47 | Report download | Commitments report with related PAN | 1. Download xlsx | `ABCPM1234K` in the cell | | |
| ☐ | E48 | Root KYC report column | KYC report | 1. PAN column on root rows | `ABCPM1234K` | | |
| ☐ | E49 | Chatbot SELECT * | — | 1. `SELECT * FROM investor_kycs WHERE entity_id IN ({ENTITY_ID}) LIMIT 5` | Rows returned without PAN, bank, IFSC, reply columns | | |
| ☐ | E50 | Download: every encrypted column decrypted | Offer, interest, fee, CKYC, AML rows | 1. Download generated | Every in-scope column plain in the file; soft-deleted rows still left out as today | | |
| ☐ | E51 | Admin search by PAN | Super admin | 1. /admin offers search `ABCPM1234K` | No offer matched on PAN; no error | | |
| ☐ | E52 | Keys missing | Credentials without keys (stubbed) | 1. Pre-flight | "Encryption keys missing for production.in — stop" | | |
| ☐ | E53 | Scrub dry run | As H30 | 1. Without EXECUTE | Reports counts; no change | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | PAN over 15 characters | KYC 2 | 1. PAN of 16 characters saved | "PAN is too long (maximum is 15 characters)" — unchanged message | | |
| ☐ | X2 | Plain value after window closed | Window closed; KYC 2 plain | 1. Rohan opens KYC 2 | Standard error page; error email to the developer list with `ActiveRecord::Encryption::Errors::Decryption` | | |
| ☐ | X3 | Import, Update Only, no match | No KYC with `ZZZPM0000Z` | 1. Import row with that PAN | Row error "Skipping: no KYC found to update for Anil Mehta (…, PAN ZZZPM0000Z)" — unchanged | | |
| ☐ | X4 | JSON request refused | — | 1. GET `/investor_kycs.json?q[PAN_cont]=ABC` | 422 with `{"error": "\"PAN\" is stored encrypted, …"}` | | |
| ☐ | X5 | IFSC greater than | — | 1. "IFSC Code > HDFC" | IFSC message | | |
| ☐ | X6 | Other firm, same PAN | Kabir (Banyan) | 1. Searches `ABCPM1234K` | Only Banyan's KYC; never Kestrel's | | |
| ☐ | X7 | Min requested through a crafted save | Report save posting aggregate `min` for related PAN | 1. Report rendered | Shown as Value with the tooltip; never ciphertext | | |
| ☐ | X8 | Chatbot names PAN | — | 1. `SELECT investor_name, PAN FROM investor_kycs WHERE entity_id IN ({ENTITY_ID})` | Refused: "PAN, bank account number and IFSC code are not available to the assistant — open the KYC page." | | |
| ☐ | X9 | Chatbot filters on bank number | — | 1. `… WHERE bank_account_number = '50100234567812'` | Same refusal | | |
| ☐ | X10 | Same fingerprint as other region | `OTHER_REGION_FP` (from production.us's pre-flight) equals the current fingerprint | 1. Pre-flight for production.in | "Fingerprint matches the value recorded for production.us — stop" | | |
| ☐ | X11 | Wrong region | Running as production.in | 1. Ask CapHive ops to run: `pii_encryption:encrypt[production.us]` | "This machine is production.in, not production.us — refusing"; no writes | | |
| ☐ | X12 | Scrub outside development | RAILS_ENV staging (stubbed) | 1. Scrub | "scrub_dev_copy runs only on a development database — refusing" | | |

---

## UI Journeys

Journey 1 — filtering the KYC list (design [What users see](design.md#what-users-see)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KYCs › Filter | Pick "PAN" in the field list | ② the condition list shows only equals, not equals, is blank, is present | | |
| ☐ | J1.2 | KYCs › Filter | Pick "Bank Account Number" | Only is blank, is present | | |
| ☐ | J1.3 | Browser address bar | Open `/investor_kycs?q[PAN_cont]=ABCPM` | ① `"PAN" is stored encrypted, so it can only be matched exactly. Use "equals" with the full value, or "is blank" / "is present".`; all KYCs listed; the condition is not left in the panel | | |
| ☐ | J1.3a | KYCs › Filter | "Bank Account Number equals 50100234567812" › Search | `"Bank Account Number" is stored encrypted, so it can only be filtered by "is blank" or "is present".` | | |
| ☐ | J1.3b | KYCs › Filter | "IFSC Code contains HDFC" › Search | `"IFSC Code" is stored encrypted, so it can only be matched exactly. Use "equals" with the full value, or "is blank" / "is present".` | | |
| ☐ | J1.4 | KYCs › Filter | "PAN equals ABCPM1234K" › Search | Anil Mehta's two KYCs | | |
| ☐ | J1.5 | KYCs › search box | Hover the ⓘ | ③ `PAN and bank account numbers match only when typed in full.` | | |
| ☐ | J1.6 | Offers › search box | Hover the ⓘ | Same hint | | |
| ☐ | J1.7 | KYC 1 › History | Change bank account, open History | `Bank Account Number changed (value hidden)` with your name and time | | |
| ☐ | J1.8 | Report builder › Investor Kyc › PAN column menu | Open the aggregate options | Value / Latest / Count only; tooltip `Stored encrypted — shown as is; can't be summed, ranged, listed, pivoted or sorted.` | | |
| ☐ | J1.9 | Support chatbot (fund user) | Ask "What is Anil Mehta's PAN?" | `PAN, bank account number and IFSC code are not available to the assistant — open the KYC page.` | | |

---

## Role Sweep

No access rule changes; this sweep confirms nothing widened or narrowed. ✓ = allowed and works,
✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Company admin (Meera) | Employee (Rohan) | Investor (Anil) | Other-entity user (Kabir) | Super admin |
|---|---|---|---|---|---|---|
| R1 | Open KYC 1 and see the PAN | ✓ | ✓ | ✓ (own KYC) | ✗ | ✓ |
| R2 | KYC list filter "PAN equals ABCPM1234K" | ✓ (Kestrel KYCs) | ✓ | n/a | ✓ only Banyan's KYC | ✓ |
| R3 | KYC search `ABCPM1234K` | ✓ Kestrel only | ✓ Kestrel only | n/a | ✓ Banyan only | — |
| R4 | Download KYC spreadsheet | ✓ | ✓ | ✗ | ✗ | — |
| R5 | Generate firm database download | ✓ | per today's rule | ✗ | ✗ | — |
| R6 | /admin offers search | ✗ | ✗ | ✗ | ✗ | ✓ (no PAN match) |
| R7 | History of KYC 1 | ✓ | per today's rule | ✗ | ✗ | ✓ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | No new email; "Quarterly statement" PDF still opens with `ABCPM1234K`; dates in emails as `Nov 09, 2026` | | |
| ☐ | C2 | Dates on changed screens | History timestamps follow the locale format (e.g. `09/11/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Filter message and tooltips readable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Kabir cannot see Kestrel's KYCs by search, filter, report or direct URL | | |
| ☐ | C5 | Regression on modified screens | KYC form, KYC page, KYC spreadsheet, fund spreadsheet, imports, CKYC/KRA screen, AML report page, offers, interests, fees, report builder, history, firm download all behave as before with real values shown | | |
| ☐ | C6 | Empty states | KYC list with a refused filter shows the message, not "No records" | | |
| ☐ | C7 | Looks like the rest of CapHive | Filter message uses the standard flash; tooltips use the standard ⓘ | | |
| ☐ | C8 | No full page reloads for small actions | Refusal inside a turbo-frame list shows a flash without a full reload | | |
| ☐ | C9 | Explains itself | Search ⓘ hint and report-builder tooltip present | | |
| ☐ | C10 | Speed on a large entity | KYC list and KYC spreadsheet for the largest staging entity open as fast as before (within ~2 s for the list) | | |
| ☐ | C11 | After deploy 2 | Repeat J1.1–J1.9 and H1, H12, H14, H21; all still pass | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
