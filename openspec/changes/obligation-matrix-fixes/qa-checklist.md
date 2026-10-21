# Obligation Matrix Fixes — Manual QA Checklist

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
| Environment | Staging (deploy branch `feature/obligation-matrix-fixes` first) |
| Account – Admin | A fund manager user with access to Support Agents and Portfolio Investments (e.g. `fm1@ian.com`) |
| Account – Counsel | A user with obligation review permissions |
| Second entity | A user belonging to a different entity, for isolation checks |
| Seed data | Entity with CP/CS agent enabled; at least 3 portfolio investments: one with SHA-tagged doc, one with SPA-tagged doc, one with no tagged docs |
| Agent config | CP/CS agent `investment_doc_tag` set to "SHA,SPA" |
| Background work | Agent extraction runs in Sidekiq automatically after clicking "Run". No manual job triggering needed. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Single PI extraction finds both SHA and SPA documents | PI has one SHA doc and one SPA doc; agent configured with "SHA,SPA" | 1. Go to the PI show page 2. Click "Run CP/CS Agent" 3. Wait for progress to complete | Progress panel shows "Locate Document" step finding both docs. "Extract Obligations" shows total count from both docs. Obligations created as "Pending review". | | |
| ☐ | H2 | Batch extraction processes multiple PIs | At least 3 PIs with mixed tags | 1. Go to CP/CS Agent page 2. Click "Run Batch" 3. Wait for completion | Report shows PIs with matching docs processed; PI with no matching docs skipped. | | |
| ☐ | H3 | Run from PI show page shows progress | CP/CS agent enabled | 1. Go to any PI show page with matching doc 2. Click "Run CP/CS Agent" | Progress panel appears with steps: Initialize, Locate Document, Extract Obligations, Save For Review, Generate Report. Each step shows ✓ on completion. | | |
| ☐ | H4 | CP/CS matrix shows only CP and CS obligations | Some CP and CS obligations exist | 1. Open the obligation matrix with context=cp_cs (from agent results or direct URL) | Title is "CP/CS Obligation Matrix". Only CP and CS obligations shown. Legal category column visible with CP/CS values. SLO obligations not visible. | | |
| ☐ | H5 | Edit CP obligation — change legal category | CP obligation exists | 1. Open CP/CS matrix 2. Click Edit on a CP obligation 3. Change legal category to "Condition subsequent" 4. Click Save | Obligation saves successfully. No error. Legal category updated to CS. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Single tag (no comma) works | Change agent config to "SHA" only | 1. Run batch extraction | Only SHA-tagged documents found. SPA-tagged docs ignored. | | |
| ☐ | E2 | Tags with whitespace trimmed | Change agent config to "SHA , SPA" (spaces around comma) | 1. Run batch extraction | Both SHA and SPA documents found (spaces trimmed). | | |
| ☐ | E3 | Zero targets — tag mismatch | Change agent config to "XYZ" (no matching docs) | 1. Run from a PI page | Agent completes with empty report. No crash. Progress shows "no document" or similar. | | |
| ☐ | E4 | PI with no matching documents skipped in batch | One PI has no docs matching any configured tag | 1. Run batch | That PI skipped in progress ("no document"). Other PIs processed normally. | | |
| ☐ | E5 | Dedup across docs on same PI | PI has both SHA and SPA docs that mention the same clause | 1. Run agent on that PI | Obligation created only once (not duplicated). | | |
| ☐ | E6 | Side letter matrix hides legal category column | SLO obligations exist | 1. Open matrix with context=side_letter | Title is "Side Letter Obligation Matrix". Legal category column NOT visible. All shown obligations are SLO. | | |
| ☐ | E7 | Context preserved across filter | Viewing CP/CS matrix | 1. Select a filter (e.g. Type = "Reporting") 2. Click Filter | Results filtered AND still scoped to CP/CS only. URL still has context=cp_cs. | | |
| ☐ | E8 | Navigate away and return — no duplicate panels | Agent was run on a PI page | 1. Run agent on a PI page 2. Navigate to another page (e.g. Home) 3. Press Back to return to the PI page | Only ONE progress panel visible. Not duplicated. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Entity fallback on zero targets | Agent tag set to something that matches no documents | 1. Run agent from PI page | Agent completes without crash. Progress panel shows completion with "no documents found" or empty results. No 500 error. | | |
| ☐ | X2 | LLM failure handled gracefully | A valid document exists but LLM service is unavailable (ask developer to simulate) | 1. Run agent on a PI with a valid document | Extract step shows "failed" on the progress panel. Other steps still complete. No 500 error to the user. | | |
| ☐ | X3 | Legal category edit — verify old bug is fixed | A CP obligation exists | 1. Open the obligation's edit form 2. Change legal category dropdown 3. Click Save | Saves successfully. Previously this would show "ArgumentError: '0' is not a valid legal_category". | | |

---

## UI Journeys

### Journey 1: Run CP/CS Agent from PI Page

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | PI show page | Look for the CP/CS Agent section | "Run CP/CS Agent" button visible (if agent is enabled) | | |
| ☐ | J1.2 | PI show page | Click "Run CP/CS Agent" | Modal or direct run starts. Progress panel appears below the button. | | |
| ☐ | J1.3 | PI show page — progress | Watch the progress panel | Steps advance one by one: Initialize ✓, Locate Document ✓ (shows doc name), Extract ✓ (shows count), Save ✓, Report ✓ | | |
| ☐ | J1.4 | PI show page — re-run | Click "Run CP/CS Agent" again | Previous progress panel replaced by new one. Not duplicated. | | |

### Journey 2: Review Obligations in CP/CS Matrix

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | CP/CS matrix page | Open matrix with context=cp_cs | Title: "CP/CS Obligation Matrix". Info banner mentions CP/CS. | | |
| ☐ | J2.2 | CP/CS matrix page | Check filter bar | Legal category filter shows only "Condition Precedent" and "Condition Subsequent" — no "Side Letter Obligation" | | |
| ☐ | J2.3 | CP/CS matrix page | Click a column header | Table rows sort by that column (client-side, no page reload) | | |
| ☐ | J2.4 | CP/CS matrix page | Click Edit on a CP obligation | Edit form appears with: legal category showing only CP/CS options, MFN checkbox NOT visible | | |
| ☐ | J2.5 | CP/CS matrix page — breadcrumb | Click the breadcrumb | Returns to the matrix page with context=cp_cs preserved. No "Side Letters" link in breadcrumb. | | |

### Journey 3: Side Letter Matrix Context

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | SLO matrix page | Open matrix with context=side_letter | Title: "Side Letter Obligation Matrix". Legal category column hidden. | | |
| ☐ | J3.2 | SLO matrix page | Edit an SLO obligation | Form shows all legal category options. MFN checkbox visible. | | |

### Journey 4: Default Matrix (No Context)

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J4.1 | Default matrix page | Open matrix without context param | Title: "LP Obligation Matrix". All columns visible. All filter options available. | | |
| ☐ | J4.2 | Default matrix page | Filter by legal category "Condition Precedent" | Only CP obligations shown. Filter works correctly. | | |

---

## Role Sweep

| ID | Screen / action | Fund manager (admin) | Counsel | Regular employee | Other-entity user |
|---|---|---|---|---|---|
| R1 | View obligation matrix | ✓ Sees own entity's obligations | ✓ Sees own entity's obligations | ✓ or ✗ per policy | ✗ No obligations from this entity visible |
| R2 | Run CP/CS Agent from PI page | ✓ Can trigger extraction | ✓ Can trigger extraction | ✗ or ✓ per policy | ✗ Cannot see the PI page |
| R3 | Edit obligation | ✓ Can edit | ✓ Can edit | ✗ per policy | ✗ Cannot access |
| R4 | Approve/reject obligation | ✓ or ✗ per policy | ✓ Can approve/reject | ✗ per policy | ✗ Cannot access |
| R5 | View CP/CS matrix via direct URL | ✓ Sees only own entity | ✓ Sees only own entity | ✓ or ✗ per policy | ✗ Empty or redirected |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | No new emails or alerts are introduced by this change. Existing enforcement alerts unchanged. | | |
| ☐ | C2 | Dates on changed screens | Due dates on the matrix follow the user's locale format. Estimated closing date input uses date picker. | | |
| ☐ | C3 | Narrow / mobile width | Obligation matrix table scrolls horizontally on mobile. No content overflow. Run button accessible. | | |
| ☐ | C4 | Tenant isolation | Log in as a user from a different entity. Navigate to the obligation matrix URL with context=cp_cs. No obligations from the first entity visible. Attempt to access a PI page from the first entity directly — should be blocked. | | |
| ☐ | C5 | Regression on modified screens | PI show page still loads correctly for PIs without the CP/CS agent. Documents page still works. Obligation matrix without context param shows all obligation types as before. | | |
| ☐ | C6 | Empty states | CP/CS matrix with no CP/CS obligations shows an empty table (not an error). PI page with no agent enabled shows no Run button (not a broken section). | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
