# Investor KYC Journey — Manual QA Checklist

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
| Environment | Staging (IN), en locale |
| Accounts | **Priya** — company admin with KYC approve; **Rahul** — compliance user; **Ken** — employee who can edit KYCs but not approve; **Asha** — investor user of Asha Ventures |
| Second entity | **Bharat Angels** (Angel Fund), admin **Meera**; plus a user of any other company for isolation checks |
| Seed data | Acme Capital (Investment Fund): AML enabled; Settings → individual KYC documents "PAN Card, Address Proof, Photo"; 8 KYC document questions; investor Asha Ventures with Asha as an approved user. Acme is **not** set up for KYC journeys yet |
| Background work | AI validation and AML reports run in the background: wait 1–2 minutes, or ask a developer to run the job. Reminders: ask a developer to run the workflow reminder job. The journey re-checks itself every 15 minutes |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Rollout dry run and execute | Acme not set up | Ask a developer to run `investor_kyc_journeys:rollout` without, then with `EXECUTE=1` | Dry run lists Acme and Bharat Angels with what would be added; nothing changes. After execute, Workflow Templates shows "Investor KYC" with 9 tasks | | |
| ☐ | H2 | New KYC gets the journey | Acme set up | 1. Investors → Asha Ventures → New KYC (Individual) 2. Save | Step bar shows all 9 tasks; ● Send KYC form "The KYC form has not been sent — send it, or fill it in and tick complete" | | |
| ☐ | H3 | Panel sends the form | H2 | Click the panel's "Send KYC Required Notification" | KYC Actions opens, the item runs; bar: ✓ Send KYC form, ● Submit KYC "Waiting for the investor — form sent on <today>" | | |
| ☐ | H4 | Investor submits | H3; Priya's page left open | As Asha (emailed link): upload PAN Card, Address Proof, Photo; click Submit KYC | Priya's page, without reload: ✓ Submit KYC, ✓ Upload required documents, ● Validate documents | | |
| ☐ | H5 | AI full pass | H4, documents that match the questions | Click the panel's "Validate Document Data"; wait | ✓ Validate documents "Validated by AI", no click needed; ● Run AML screening | | |
| ☐ | H6 | AML no match | at Run AML, a name with no match | Click the panel's "Generate AML Report"; wait | ✓ Run AML screening; Clear AML match shows "–" "No AML match"; ● Review KYC | | |
| ☐ | H7 | Review and sign-off | Rahul set as approver on Compliance sign-off; at Review KYC | Priya: Mark reviewed. Rahul: approve the sign-off | ● Verify KYC | | |
| ☐ | H8 | Verify from the panel | at Verify | Priya clicks the panel's "Verify" | Verify runs; journey complete (all ✓ or –) | | |
| ☐ | H9 | Fund fills the KYC in | new KYC, nothing sent | Edit, fill in, tick "I confirm all details provided are complete…", save | Status completed; "Send KYC form" "–" "Filled in by the fund"; ✓ Submit KYC | | |
| ☐ | H10 | Override clears a match | Clear AML match current (potential match) | Rahul overrides AML to No match, reason "Namesake, DOB differs" | ✓ Clear AML match "Overridden by Rahul: Namesake, DOB differs" | | |
| ☐ | H11 | Setup from the menu | Acme not set up | Workflow Templates → Set up journeys → "Set up investor KYC journeys" → confirm | Notice "Investor KYC journeys set up: KYC journey, auto-assignment rule. New KYCs will get a journey."; item now disabled "✓ Investor KYC journeys set up" | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Missing documents | submitted KYC with only "Photo" | Open the KYC | "2 required documents missing: PAN Card, Address Proof"; button opens the Documents tab | | |
| ☐ | E2 | Nothing required | a company with no required document list or required document fields | Open a submitted KYC | Upload required documents "–" "No documents are required" | | |
| ☐ | E3 | AI could not validate | a blurry PAN scan | Run AI validation; then Mark reviewed | "AI could not validate 1 of 8 answers — check them and mark reviewed" with "Open validation" and Mark reviewed; after the click ✓ "Reviewed by Priya" | | |
| ☐ | E4 | No document questions | a company with no KYC document questions | Reach Validate documents | "Check the documents and mark reviewed", only Mark reviewed | | |
| ☐ | E5 | Document replaced after AI pass | H5 done | Replace the PAN Card | ↺ Validate documents "Documents changed after validation"; passes again only after a new AI pass or Mark reviewed | | |
| ☐ | E6 | Imported verified KYC | Acme set up | Import a KYC marked Verified with no documents and no AML | Journey complete; missing tasks "–" "Verified without this step" | | |
| ☐ | E7 | Potential match | AML enabled, a name that matches | Generate AML Report | ● Clear AML match "AML found a potential match — review the report and override it if it is a false positive", button "View AML Reports" | | |
| ☐ | E8 | AML off | a company without AML | Open a KYC | Both AML tasks "–" "AML screening is not enabled" | | |
| ☐ | E9 | No sign-off approver | approver not picked on the template | Reach Compliance sign-off | "–" "No approver set — pick one on this step in the journey template"; Verify KYC current | | |
| ☐ | E10 | Request Updates | at Compliance sign-off, Review KYC confirmed | Request Updates | Amber banner "Moved back to "Submit KYC" — Updates requested by Priya on <date> <time>."; Review KYC and sign-off reset; Rahul emailed | | |
| ☐ | E11 | UnVerify | journey complete | Click UnVerify | ↺ Verify KYC "Unverified by Priya" (or ↺ an earlier unfinished task, e.g. Upload required documents) | | |
| ☐ | E12 | Edit after review | Review KYC confirmed | Edit the address, save | ↺ Review KYC "KYC details changed after review" | | |
| ☐ | E13 | Upload before validation reached | at Submit KYC | Upload a document | No move back, no amber banner | | |
| ☐ | E14 | Documents-first form | form sent; company has the documents-first wizard | As Asha: upload documents first, let the form pre-fill, do not submit | ● Submit KYC unchanged; Validate documents not ticked | | |
| ☐ | E15 | Colleague bulk-verifies | Priya's page open at Verify | Ken/Priya in another window: KYC list → filter → bulk Verify | Priya's page shows ✓ Verify KYC without reload | | |
| ☐ | E16 | Fund unticks complete | completed KYC | Untick "I confirm … complete", save | Status draft; ↺ Submit KYC "Marked incomplete" | | |
| ☐ | E17 | Bulk Unverify | 3 verified KYCs with journeys | KYC list → filter → bulk Unverify | Each status "completed" (not "link sent"); Asha cannot edit; each ↺ Verify KYC | | |
| ☐ | E18 | No journey, no change | a KYC created before setup | Verify it; bulk verify others | Works as before; no step bar | | |
| ☐ | E19 | Re-run keeps edits | approver picked, AML step removed | Run setup again (menu or rake) | No duplicate template or rule; edits kept | | |
| ☐ | E20 | Company already has a KYC rule | a human-only KYC rule exists | Run setup | Template created, no rule; dry run says the entity already has a KYC rule | | |
| ☐ | E21 | Delete with journey | unverified KYC with a journey | Delete | KYC deleted | | |
| ☐ | E22 | Bank warning | bank verification failed | Open the KYC | "Bank account verification failed" shown until verified | | |
| ☐ | E23 | Investor-created KYC reminders | Asha creates her own KYC; a task stalls 2+ days | Ask a developer to run reminders | Asha receives no reminder email | | |
| ☐ | E24 | Call review unchanged | a capital call at Review email | Open the call | "Not confirmed yet", only Mark reviewed, no second button | | |
| ☐ | E25 | Default journey, then one per form type | Acme set up; KYC form types Individual — Default, Individual — Fund IV, Non Individual — Default | 1. Create one KYC of each form type 2. Duplicate "Investor KYC", rename "Investor KYC — Fund IV" 3. New auto-assignment rule for the copy, KYC form type "Individual — Fund IV", priority 50 4. Create one KYC of each form type again | Step 1: all three "Investor KYC". Step 4: only the Fund IV KYC gets "Investor KYC — Fund IV" | | |
| ☐ | E27 | Form type list on the rule form | Acme has 3 KYC form types | New auto-assignment rule, type Investor KYC | "KYC form type" lists exactly Acme's 3 form types (none from other companies); saving keeps the choice when the rule is reopened | | |
| ☐ | E26 | Duplicate a template | "Investor KYC" exists | Click Duplicate; then run setup again | "Copy of Investor KYC" with 9 identical tasks; setup says already set up; copy unchanged | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Investor never sees the journey | Asha logged in; also via emailed link | Open the KYC | No step bar, panel or warnings | | |
| ☐ | X2 | Panel Verify without permission | Ken at Verify | Click the panel's button | No Verify happens (button acts as a plain link to the KYC) | | |
| ☐ | X3 | Non-admin setup | Ken | Open Workflow Templates | No "Set up journeys" menu; a direct request is refused | | |
| ☐ | X4 | Angel Fund setup | Meera (Bharat Angels) | Open Set up journeys | Only "Set up investor KYC journeys" offered | | |
| ☐ | X5 | Other entity | other company's user | Open the KYC's journey URL directly | Access denied | | |
| ☐ | X6 | A check fails | ask a developer to corrupt a test KYC's AI answers | Open the KYC | "Could not check this step — support has been notified" on Validate documents; support alerted | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | KYC page | Open a new KYC | ① header "Investor KYC" with progress, ② the step bar | | |
| ☐ | J2.2 | KYC page | Leave open while the investor submits | Bar moves on without reload | | |
| ☐ | J2.3 | KYC page | Click "Open validation" on Validate documents | Validation tab opens on the same page | | |
| ☐ | J2.4 | KYC page | Click Mark reviewed | Bar moves to Run AML screening | | |
| ☐ | J2.5 | KYC page | Click "Generate AML Report" in the panel | KYC Actions opens, the item flashes and runs | | |
| ☐ | J2.6 | KYC page | Read the warnings | Warnings listed until verified | | |
| ☐ | J2.7 | KYC page | Open the Workflow tab (admin) | The journey's workflow instance; the template list shows KYC templates | | |

---

## Role Sweep

| ID | Screen / action | Priya (admin + approve) | Ken (edit, no approve) | Read-only employee | Asha (investor) | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | See step bar and panel | ✓ | ✓ | ✓ | ✗ | ✗ |
| R2 | Mark reviewed (unverified KYC) | ✓ | ✓ | ✗ | ✗ | ✗ |
| R3 | Verify from the panel | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Set up investor KYC journeys | ✓ | ✗ | ✗ | ✗ | ✗ |
| R5 | Duplicate a workflow template | ✓ | ✗ | ✗ | ✗ | ✗ |
| R6 | Bulk Unverify | ✓ | ✗ | ✗ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails sent by this feature (stall reminder to Priya, sign-off reset to Rahul) | Correct recipient and link; dates shown as `Oct 08, 2026`; nothing sent to investors | | |
| ☐ | C2 | Dates in panel messages ("form sent on …", amber banner) | Locale format, e.g. `08/10/2026` for en | | |
| ☐ | C3 | Narrow / mobile width on the KYC page | Step bar wraps, no horizontal scroll, buttons reachable | | |
| ☐ | C4 | Tenant isolation | Another company's user cannot see or reach the journey, even by URL | | |
| ☐ | C5 | Regression: capital call and distribution pages | Journeys look and behave as before | | |
| ☐ | C6 | Regression: KYC form, documents-first form, AML, AI validation, bulk actions | Work as before, apart from the two agreed fixes | | |
| ☐ | C7 | Regression: a company not set up | KYC pages unchanged | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
