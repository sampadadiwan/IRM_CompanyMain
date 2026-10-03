# Document Checks — Manual QA Checklist

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
| Environment | Staging (IN). The AI provider must be configured (ask a developer to confirm `DOCUMENT_VALIDATION_PROVIDER`) |
| Accounts | **Priya Shah**: fund admin at "Fireside Ventures (QA)". **Ken Mori**: fund employee at Fireside without KYC edit rights. **Asha Rao**: investor user owning a KYC at Fireside |
| Second entity | **Olu Bello**: fund admin at "Northwind Capital (QA)" |
| Entity settings | Fireside: "Doc LLM validation" permission on. Individual KYC documents = "CML, PAN Card, Passport". KYC form (Individual) has custom fields **DP ID** (`dp`) and **Client ID** (`client`) |
| Seed data | Individual KYC **Asha Rao**: full name "Asha Rao", PAN "ABCPK1234F", address "D109, MW", other bank fields empty. Upload a real sample CML PDF, a PAN card image and a passport PDF whose values you know. Second KYC **Rao Holdings** (non-individual). Third KYC **Kiran Iyer** (individual, verified) |
| Prepared files | `pan_card.doc` (a Word file), a CML whose holder is printed as "A. Rao", a CML with PAN "ABCPK1243F" |
| Legacy data | Ask a developer to copy one Doc Questions answer set onto a KYC (or use an entity converted from production data) for E14 |
| Background work | Runs happen in the background and the panel updates by itself within about a minute. If it doesn't, refresh. To simulate an AI outage (X3), ask a developer to point the provider at an invalid key on staging for the duration of the test |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Applying the CML preset | Logged in as Priya; no sets yet | 1. Settings → Document Checks. 2. Add set "Investor KYC — Individual". 3. Add document → CML. 4. Apply preset → CML | 9 checks appear. DP ID → DP ID, Client ID → Client ID, PAN → PAN, First holder name → Full name. Email and Mobile rows show "Pick a field before saving" | | |
| ☐ | H10 | Document list | H1 done | 1. Click Add document | Only PAN Card and Passport are offered | | |
| ☐ | H2 | Full pass run | Set as in the design's shared setup (delete Email/Mobile, add rule "Signed by holder?", PAN Card Name, Passport Name + Expiry date); Asha's documents are good | 1. Open Asha's KYC → Document Checks tab. 2. Click Run Document Checks | "Running…" then, without reload: all groups ✓. DP ID and Client ID show "Filled DP ID" / "Filled Client ID". Address shows "Kept existing value D109, MW". Toast "Document Checks finished for Asha Rao: 11 passed". Edit KYC: DP ID and Client ID filled | | |
| ☐ | H3 | Test run saves nothing | Fresh KYC with empty DP ID | 1. Settings → set → Test on a KYC → pick the KYC | Panel with banner "Test run — nothing was saved to this KYC"; DP ID "Filled DP ID". Open the KYC: DP ID still empty, Document Checks tab says not checked yet, journey unchanged | | |
| ☐ | H4 | Accept a review | Upload the "A. Rao" CML; run | 1. On First holder row click Accept. 2. Reason "Initial matches passport". 3. Confirm | Row "Accepted by Priya Shah — 'Initial matches passport'". Header counts update. If nothing else is open, journey Validate documents shows "Validated by AI" | | |
| ☐ | H5 | Journey completes by itself | Asha's KYC on Validate documents; all good documents | 1. Run Document Checks. 2. Look at the journey bar | Validate documents ✓ "Validated by AI" with no click; next step is current | | |
| ☐ | H6 | Bulk run | Asha (unverified), Rao Holdings (unverified), Kiran Iyer (verified) | 1. KYC list → select all three → Run Document Checks | Asha and Rao Holdings get runs; Kiran gets "Cannot modify verified KYC" | | |
| ☐ | H7 | Results list and re-run | One KYC failed, one error, one passing | 1. KYC menu → Document Check results. 2. Status = Failed, Error. 3. Select both rows → Re-run selected | Only the 2 rows listed; notice "Document Checks queued for 2 KYCs"; both KYCs show new runs | | |
| ☐ | H8 | Conversion report (support) | An entity with Doc Questions (staging copy) | 1. Ask a developer to run the conversion **dry run** for that entity | Report lists each question with its field, or a reason. Settings → Document Checks shows no new checks | | |
| ☐ | H9 | Conversion execute | H8 reviewed | 1. Developer runs with execute, twice | "Investor KYC — All" set has the converted checks, once each | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Individual set wins | Individual and All sets both exist, different checks | Run on Asha | Only the Individual set's checks appear | | |
| ☐ | E2 | Fallback to All | Only an All set | Run on Rao Holdings | All set's checks appear | | |
| ☐ | E3 | Name with prefix/case | Rename Asha's PAN document to "Upload pan card" | Run | PAN Card group has results (not "not uploaded") | | |
| ☐ | E4 | PAN spacing ignored | CML shows PAN with a space/hyphen | Run | PAN ✓ | | |
| ☐ | E5 | Name differs → review | "A. Rao" CML | Run | First holder "? Document A. Rao · KYC Asha Rao" with Accept and Fix | | |
| ☐ | E6 | Keep existing value | Set Asha's Client ID to "86478612" | Run | Client ID ✓ "Kept existing value 86478612"; field unchanged | | |
| ☐ | E7 | Not found | Add an Extract check "Nominee name" to CML (a CML without one) | Run | "? Not found on the document" | | |
| ☐ | E8 | Not uploaded | Delete Asha's passport | Run | Passport group "— not uploaded"; journey Validate documents not done | | |
| ☐ | E9 | Re-upload makes out of date | H5 done | Replace Asha's CML | CML group "⟳ Out of date — document changed after this run"; PAN Card and Passport not; journey back to waiting on Validate documents | | |
| ☐ | E10 | No double run | — | Click Run Document Checks twice quickly (second tab) | "Document Checks are already running for Asha Rao"; one run | | |
| ☐ | E11 | Preset twice | H1 done | Apply CML preset again | Still 9 checks | | |
| ☐ | E12 | Deleted custom field | Delete the DP ID custom field from the KYC form | 1. Open the set. 2. Run on Asha | Row shows "This field no longer exists — pick another"; in the run, DP ID "⚠ Field no longer exists" | | |
| ☐ | E13 | Removed document leaves no stale result | Last run included Passport results; delete passport | Run | Passport shows only "— not uploaded" | | |
| ☐ | E14 | Earlier AI answers | KYC with legacy answers | Open Document Checks tab | Collapsed "Earlier AI answers (before Document Checks)"; expanding shows the old table | | |
| ☐ | E15 | Not checked yet | Set exists, KYC never run | Look at the journey | "Documents not checked yet — run Document Checks or check them and mark reviewed" | | |
| ☐ | E17 | Rule fails | A CML with no signature | Run | "Signed by holder?" ✗ with the AI's reason | | |
| ☐ | E18 | PAN mismatch | Upload the CML with PAN "ABCPK1243F" | Run | PAN ✗ "Document ABCPK1243F · KYC ABCPK1234F" | | |
| ☐ | E19 | Problem count | 1 failed + 1 error | Look at the journey | "Document Checks found 2 problems — check them and mark reviewed" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Word file | Replace PAN card with `pan_card.doc`; CML with PAN mismatch | Run | PAN Card "⚠ Can't read this file type — upload a PDF or image" with Retry; CML and Passport checked; toast (warning) "Document Checks finished for Asha Rao: 9 passed, 1 failed, 1 error" | | |
| ☐ | X2 | AI reply unreadable | Ask a developer to make the AI return text for CML on staging (or use a blank image as CML) | Run | CML "⚠ The AI's reply couldn't be read — try again"; other documents checked | | |
| ☐ | X3 | AI outage | Developer breaks the provider key | Run | Toast (danger) "Document Checks could not run for Asha Rao: the AI service is unavailable. Try again later."; panel header "Last attempt failed …"; earlier results still shown; no KYC field changed | | |
| ☐ | X4 | Field not on list | — | Ask a developer to submit a check with field "verified" (crafted request) | "Choose a field from the list"; not saved | | |
| ☐ | X5 | Hint text is harmless | Set DP ID hint to "$destroy the record" | Run | KYC still exists; DP ID result normal | | |
| ☐ | X6 | Other entity | Logged in as Olu | Paste Fireside's set edit URL and a run URL | Access denied for both | | |
| ☐ | X7 | Investor view | Logged in as Asha | Open her KYC | No Document Checks tab, no results | | |
| ☐ | X8 | Accept without reason | A review row | Click Accept, leave reason empty, confirm | "Give a reason for accepting"; not accepted | | |
| ☐ | X9 | Conversion leftovers | Entity with "Extract to field mobil_contact" | Developer runs dry run | Listed as unconverted "Field mobil_contact not found" | | |
| ☐ | X10 | Duplicate set | Individual set exists | Add set → Investor KYC — Individual | Refused "Investor KYC — Individual already exists" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | KYC → Document Checks tab | Open it | ① the panel for the last run, or "Not checked yet" with the Run button | | |
| ☐ | J1.2 | Same | Click Run Document Checks | ② "Running… started HH:MM", button disabled; panel refreshes in place when done | | |
| ☐ | J1.3 | Same | Read the group headers | ③ ✓ N / M, ✗, ?, ⚠, —, ⟳ per document | | |
| ☐ | J1.4 | Same | Accept a row with a reason | ④ "Accepted by <name> — '<reason>'"; counts update | | |
| ☐ | J1.5 | Same | Click Fix | ⑤ the KYC edit form opens | | |
| ☐ | J1.6 | Same | Click Retry on an error group | ⑥ a new run starts (as J1.2) | | |
| ☐ | J1.7 | Same | Expand Earlier AI answers | ⑦ old answers table, read-only | | |
| ☐ | J2.1 | Document Check results | Open from the KYC menu | Problems for current runs, newest first | | |
| ☐ | J2.2 | Same | Filter Document = CML | Only CML rows | | |
| ☐ | J2.3 | Same | Select 3 rows, Re-run selected | "Document Checks queued for 3 KYCs" | | |
| ☐ | J3.1 | Settings → Document Checks | Change a row's Kind to Rule | Field and Fill hide, Expect appears | | |
| ☐ | J3.2 | Same | Change Kind to Match | Fill hides, Field stays | | |
| ☐ | J3.3 | Same | Save with an Extract row without a field | "Choose a field from the list" on that row | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Fund admin (Priya) | Fund employee, no KYC edit (Ken) | Investor (Asha) | Other-entity user (Olu) |
|---|---|---|---|---|---|
| R1 | Settings → Document Checks (view/edit/test) | ✓ | ✓ if the permission is on for the entity | ✗ | ✗ |
| R2 | Run Document Checks on a KYC | ✓ | ✗ (needs KYC update) | ✗ | ✗ |
| R3 | See the Document Checks tab | ✓ | ✓ if he can view the KYC | ✗ | ✗ |
| R4 | Accept a result | ✓ | ✗ | ✗ | ✗ |
| R5 | Document Check results list | ✓ | ✓ | ✗ | ✗ |
| R6 | Re-run selected | ✓ | ✗ (rows skipped) | ✗ | ✗ |
| R7 | Entity with the permission off: any of the above | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | No emails are sent. Toasts appear for start/finish/failure with the texts above | | |
| ☐ | C2 | Dates on changed screens | "Last run" and the results list dates follow the user's locale (e.g. `02/10/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Panel, settings rows and results list have no horizontal page scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | Olu cannot see or reach any Fireside set, run or result, even by direct URL | | |
| ☐ | C5 | Regression on modified screens | KYC page tabs, KYC bulk actions, journey bar, documents tab all still work; Doc Questions menu item is gone | | |
| ☐ | C6 | Empty states | No sets: "No Document Checks set up yet — Add set". KYC never run: "Not checked yet". Results list with no problems: "No problems found" | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
