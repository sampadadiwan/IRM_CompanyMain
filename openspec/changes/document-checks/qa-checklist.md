# Document Checks — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X/R) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **R** = Retirement
(after release 2) · **J** = UI journey step · **RS** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Retirement (release 2)](#retirement-release-2)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (IN). The AI provider must be configured (ask a developer to confirm) |
| Accounts | **Priya Shah**: fund admin at "Fireside Ventures (QA)". **Ken Mori**: Fireside fund user who can view but not edit KYCs. **Asha Rao**: investor user owning a KYC at Fireside |
| Second entity | **Olu Bello**: fund admin at "Northwind Capital (QA)" |
| Entity settings | Fireside: "Document checks (AI)" permission on. Individual KYC documents "CML, PAN Card, Passport"; non-individual "PAN Card, Board Resolution". KYC form has custom fields **DP ID** and **Client ID** |
| Seed data | Individual KYC **Asha Rao**: full name "Asha Rao", PAN "ABCPK1234F", address "D109, MW". Upload a real CML PDF, a PAN card image and a passport PDF whose values you know. Non-individual KYC **Rao Holdings** with a PAN card. Verified KYC **Kiran Iyer** |
| Prepared files | `pan_card.doc` (Word), a CML printing the holder as "A. RAO", a CML with PAN "ABCPK1243F", a CML without a signature |
| Legacy data | An entity with Doc Questions and a KYC with earlier AI answers (staging copy of production) |
| Background work | Checks run in the background; the tab updates itself. For X3, ask a developer to break the AI key on staging for the test |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Suggested checks | No checks yet | 1. Settings → Document Checks. 2. On the CML tile click Add N suggested | CML's tile lists what it fills, compares and asks; items with no KYC field are listed as not available on your KYC form (e.g. Email, Mobile) | | |
| ☐ | H2 | Add a check | — | 1. PAN Card tile → Edit. 2. Compare with a KYC field. 3. KYC field = Full name. 4. Save PAN Card | Look for fills "Full name"; the tile says "Compares Full name" | | |
| ☐ | H3 | All OK | Checks as in the design's shared setup; good documents | Asha's KYC → Document checks → Check documents | Progress, then all ✓; "DP ID — filled in: IN303622"; Address "kept your value"; toast "Documents checked for Asha Rao — all OK"; Edit KYC shows DP ID, Client ID filled | | |
| ☐ | H4 | Trial | Fresh KYC with empty DP ID | Settings → Try on a KYC → pick it | Banner "Trial run — nothing on this KYC was changed"; KYC's DP ID still empty; its tab says "These documents haven't been checked yet." | | |
| ☐ | H5 | Use document value | KYC PAN "ABCPK1243F" | Check → PAN card → Use the document's PAN → Proceed | The popup's first card says "PAN becomes ABCPK1234F" (was ABCPK1243F); the row moves to the settled list as "Updated from the document by Priya Shah"; KYC PAN updated; KYC audit shows the change | | |
| ☐ | H6 | Mark as OK | "A. RAO" CML, only mismatch | Keep the KYC's First holder name… → "Initial matches passport" → Mark as OK | The row reads "Marked OK by Priya Shah — Initial matches passport" with Undo; tab count drops; journey "Validated by AI" | | |
| ☐ | H7 | Journey completes | KYC on Validate documents | Check documents with good documents | Validate documents ✓ "Validated by AI" with no click | | |
| ☐ | H8 | Bulk | Asha, Rao Holdings, Kiran Iyer (verified) | KYC list → select all three → Check documents | Two checked; Kiran "Cannot modify verified KYC" | | |
| ☐ | H9 | Attention list | One mismatch KYC, one unreadable, one OK | KYC menu → Documents needing attention → Reason = Doesn't match → tick → Check again (1) | One row; "Checking documents for 1 KYC" | | |
| ☐ | H10 | Conversion report | Legacy entity | Developer runs the dry run | Report lists each question with a field or a reason; no checks appear | | |
| ☐ | H11 | Conversion | H10 reviewed | Developer runs with execute, twice | Checks appear once on that entity's Document Checks page | | |
| ☐ | H12 | Progress | 3 documents | Check documents and watch | "Checking CML (1 of 3)…", "Checking PAN Card (2 of 3)…", … | | |
| ☐ | H13 | AI rules still work | An AI rule that validates a document | Run that rule | It returns an answer as before | | |
| ☐ | H14 | Export | Checks set up | Settings → Document Checks → Export | `doc_checks.xlsx` opens: columns Id, Document, What To Do, Look For, KYC Field, Tip, Replace Existing, Expected Answer; one row per check | | |
| ☐ | H15 | Import round trip | The H14 file | 1. Change one row's Tip. 2. Add a row with no Id (PAN Card · Compare · PAN · PAN). 3. Import → upload the file | Results: every row Success; the tip is changed on the setup page; PAN Card has the new check; no check is duplicated | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Cards | Setup lists | Open setup page | CML, PAN Card, Passport, Board Resolution; PAN Card once | | |
| ☐ | E2 | No documents | Entity with empty lists | Open setup page | "Add the documents you collect in Settings → KYC documents. They'll appear here." | | |
| ☐ | E3 | Same field twice | CML has PAN | Add Compare PAN; Save | Not saved; "Already used on this document" | | |
| ☐ | E4 | Preset twice | CML saved | Use CML preset again | No duplicates | | |
| ☐ | E5 | No preset | — | Look at Board Resolution | No preset button | | |
| ☐ | E6 | Company KYC | Rao Holdings | Check documents | Only PAN Card shown | | |
| ☐ | E7 | Name prefix | Rename PAN doc "Upload pan card" | Check | PAN Card read | | |
| ☐ | E8 | PAN spacing | CML PAN with spaces/hyphen | Check | ✓ matches | | |
| ☐ | E9 | Name order | Passport "RAO ASHA" | Check | ✓ matches | | |
| ☐ | E10 | Keep value | Client ID "86478612" | Check | "kept your value 86478612 (document says 86478611)" | | |
| ☐ | E11 | Not found | Add Fill in "Nominee" (not on the CML) | Check | ⚠ "not found on this document" + Mark as OK | | |
| ☐ | E12 | Not uploaded | Delete passport | Check | ⚠ "Not uploaded yet"; journey not done | | |
| ☐ | E13 | Replaced | H7 done | Replace CML | "⚠ Document changed after this check" + Check again; journey back to waiting | | |
| ☐ | E14 | Double click | — | Check documents twice quickly | "Documents are already being checked for Asha Rao" | | |
| ☐ | E15 | Removed from list | Remove Passport from the individual list | Check | No Passport items | | |
| ☐ | E16 | Deleted field | Delete DP ID custom field | Open settings; check | Banner "1 check uses a field that no longer exists — Show me"; row "This field no longer exists — pick another"; tab ⚠ "this check's KYC field no longer exists" | | |
| ☐ | E17 | Yes-no | CML without signature | Check | ⚠ "answered No" with reason | | |
| ☐ | E18 | Mismatch | KYC PAN "ABCPK1243F" | Check | "Document: ABCPK1234F · KYC: ABCPK1243F" with both buttons | | |
| ☐ | E19 | Undo | H6 done | Undo | Back to ⚠; journey "1 document item needs attention" | | |
| ☐ | E20 | Earlier answers | KYC with legacy answers | Open tab | Collapsed "Earlier AI answers (before Document Checks)" | | |
| ☐ | E21 | Not checked | Never checked | Journey | "Documents not checked yet — check documents or mark reviewed" | | |
| ☐ | E22 | Attention count | 2 items need attention | Journey | "2 document items need attention — resolve them or mark reviewed" | | |
| ☐ | E23 | No checks | Entity with no checks | Journey | "Check the documents and mark reviewed" | | |
| ☐ | E24 | Import duplicate | The H14 file | Clear one row's Id and import it | That row: "Error … Include its Id to update it instead"; nothing duplicated | | |
| ☐ | E25 | Import unknown document | — | Import a row for "Board Resolution" (not on the individual list) | Row error "Document 'Board Resolution' is not on your KYC document list" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Word file | PAN card `.doc`; KYC PAN mismatch | Check | PAN Card "⚠ Couldn't read this file — upload it as a PDF or image" + Check again; others read; warning toast "Documents checked for Asha Rao — 2 need attention" | | |
| ☐ | X2 | Unreadable answer | Developer forces a garbage reply | Check | "⚠ Couldn't read the AI's answer for this document" | | |
| ☐ | X3 | AI down | Developer breaks the key | Check | Error toast "Couldn't check documents for Asha Rao — the AI service is unavailable. Try again later."; banner with Try again; earlier results still shown; KYC unchanged | | |
| ☐ | X4 | Disallowed field | — | Developer submits field "verified" | "Pick a KYC field" | | |
| ☐ | X5 | Tip text | Tip "$destroy the record" | Check | KYC still exists; normal result | | |
| ☐ | X6 | Other entity | Olu | Open Fireside setup URL, a mark_ok URL | Denied | | |
| ☐ | X7 | Investor | Asha | Open her KYC | No Document checks tab | | |
| ☐ | X8 | No reason | Attention row | Mark as OK, empty reason | "Say why this is OK" | | |
| ☐ | X9 | Unconvertible | Legacy hint "Extract to field mobil_contact" | Dry run | "Field mobil_contact not found" | | |
| ☐ | X10 | View-only | Ken | Open Asha's tab | Results visible; no resolve or check buttons | | |
| ☐ | X11 | Import another entity's Id | Olu's export from Northwind | Priya imports it unchanged | Every row "No check found with Id …"; Northwind's checks unchanged | | |
| ☐ | X12 | Import unknown field | — | Import "Passport · Compare · Aadhaar · Aadhaar" | Row error "KYC Field 'Aadhaar' is not on your KYC form"; other rows saved | | |

---

## Retirement (release 2)

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | R1 | Old screens gone | Release 2 deployed | Open `/doc_questions` and `/doc_questions/new`; look at Settings | Page not found for both; Settings shows Document Checks, no Doc Questions | | |
| ☐ | R2 | Old import gone | — | Import uploads → New; open an old DocQuestion import | "DocQuestion" not offered; old import record still opens | | |
| ☐ | R3 | Old KYC action gone | — | Developer posts to the old validate URL | Not found; the KYC button runs Document Checks | | |
| ☐ | R4 | Data gone, history kept | — | Developer confirms no `doc_questions` table / `documents.qna` column; open a KYC with earlier answers | Gone in DB; "Earlier AI answers" still shown | | |
| ☐ | R5 | Guard | Staging copy with an unconverted question | Developer runs the release-2 migration | It stops with "1 Doc Questions are not converted — run doc_checks:convert_doc_questions first" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KYC → Document checks | Open | ① attention documents open, OK collapsed; tab title count | | |
| ☐ | J1.2 | Same | Check documents | ② progress per document; earlier results dimmed | | |
| ☐ | J1.3 | Same | Read headers | ③ "✓ All OK" / "⚠ n needs attention" / "⟳ Document changed after this check" | | |
| ☐ | J1.4 | Same | Use document value | ④ confirm, then "updated from the document by …" | | |
| ☐ | J1.5 | Same | Mark as OK | ⑤ reason box, then "Marked OK by …" + Undo | | |
| ☐ | J1.6 | Same | Check again | ⑥ same as J1.2 | | |
| ☐ | J1.7 | Same | Expand Earlier AI answers | ⑦ old table, read-only | | |
| ☐ | J2.1 | Documents needing attention | Open | Newest first, or "Nothing needs attention." | | |
| ☐ | J2.2 | Same | Reason = Doesn't match | Only mismatch rows | | |
| ☐ | J2.3 | Same | Tick 3 | "Check again (3)" enabled | | |
| ☐ | J2.4 | Same | Check again | "Checking documents for 3 KYCs" | | |
| ☐ | J3.1 | Setup | What to do → Yes-no | Field replaced by Expected; Look for becomes Question | | |
| ☐ | J3.2 | Setup | What to do → Compare | "Replace existing values" hidden | | |
| ☐ | J3.3 | Setup | Pick a field already used on the card | It's greyed out "already used on this document" | | |
| ☐ | J3.4 | Setup | Change a row, try to leave the page | "Unsaved changes" shown; leaving asks for confirmation | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Fund admin (Priya) | View-only fund user (Ken) | Investor (Asha) | Other entity (Olu) |
|---|---|---|---|---|---|
| RS1 | Setup page (view / save / preset / try) | ✓ | ✓ if the permission is on | ✗ | ✗ |
| RS2 | Check documents on a KYC | ✓ | ✗ | ✗ | ✗ |
| RS3 | See the Document checks tab | ✓ | ✓ | ✗ | ✗ |
| RS4 | Use document value / Mark as OK / Undo | ✓ | ✗ | ✗ | ✗ |
| RS5 | Documents needing attention list | ✓ | ✓ | ✗ | ✗ |
| RS6 | Check again (bulk) | ✓ | ✗ (skipped) | ✗ | ✗ |
| RS7 | Any of the above with the permission off | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | No emails sent. Toasts for start / finish / couldn't run use the texts above | | |
| ☐ | C2 | Dates | "Checked …" and list dates follow the user's locale | | |
| ☐ | C3 | Narrow width | No horizontal page scroll on the setup page, tab or list; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Olu can't reach any Fireside check, result or run by URL | | |
| ☐ | C5 | Regression | KYC tabs, bulk actions, journey bar, documents tab, document page all still work | | |
| ☐ | C6 | Empty states | "No document checks are set up — Set up checks"; "These documents haven't been checked yet."; "Nothing needs attention." | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
