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
| Seed data | Entity with CP/CS and SLO agents enabled; at least 3 portfolio investments: one with SHA-tagged doc, one with SPA-tagged doc, one with no tagged docs. At least 1 capital commitment with a side letter. |
| Agent config | CP/CS agent `investment_doc_tag` set to "SHA,SPA" |
| Background work | Agent extraction runs in Sidekiq automatically after clicking "Run". No manual job triggering needed. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Single PI extraction finds both SHA and SPA documents | PI has one SHA doc and one SPA doc; agent configured with "SHA,SPA" | 1. Go to the PI show page 2. Click "Run CP/CS Agent" 3. Wait for progress to complete | Progress panel shows "Locate Document" step finding both docs. "Extract Obligations" shows total count from both docs. Obligations created as "Pending review". | | |
| ☐ | H2 | Batch extraction processes multiple PIs | At least 3 PIs with mixed tags | 1. Go to CP/CS Agent page 2. Click "Run Batch" 3. Wait for completion | Report shows PIs with matching docs processed; PI with no matching docs skipped. | | |
| ☐ | H3 | Run from PI show page shows progress | CP/CS agent enabled | 1. Go to any PI show page with matching doc 2. Click "Run CP/CS Agent" | Progress panel appears with steps: Initialize, Locate Document, Extract Obligations, Save For Review, Generate Report. Each step shows ✓ on completion. | | |
| ☐ | H4 | Matrix with legal category filter pre-selected | Some CP and CS obligations exist | 1. Click "Open Obligation Matrix" from CP/CS agent results page | Title is "LP Obligation Matrix". Legal category filter pre-selected to "Condition Precedent". Only CP obligations shown. Stakeholder dropdown shows portfolio companies. | | |
| ☐ | H5 | Edit CP obligation — change legal category | CP obligation exists | 1. Open obligation matrix 2. Filter by legal category = "Condition Precedent" 3. Click Edit on a CP obligation 4. Change legal category to "Condition subsequent" 5. Click Save | Obligation saves successfully. No error. Legal category updated to CS. | | |
| ☐ | H6 | Run SLO agent from capital commitment page | SLO agent enabled; commitment has side letter | 1. Go to the capital commitment show page 2. Click "Run SLO Agent" 3. Wait for progress to complete | Progress panel appears with steps. After completion, auto-redirects to standalone obligation matrix with legal category = "Side Letter Obligation" AND stakeholder = that LP pre-selected. Only that LP's SLO obligations shown. | | |
| ☐ | H7 | CP/CS single-company redirect with stakeholder pre-filter | CP/CS agent enabled; portfolio company has obligations | 1. Go to portfolio company (investor) page 2. Run CP/CS agent for that company 3. Wait for completion | Auto-redirects to standalone matrix with legal category = "Condition Precedent" AND stakeholder = that company pre-selected. Only that company's CP obligations shown. | | |
| ☐ | H8 | Batch run redirects to agent Obligations tab | CP/CS agent enabled; entity has PIs | 1. Go to CP/CS agent General tab 2. Click "Run Now" 3. Wait for batch to complete | Batch summary shown, then after 3 seconds auto-redirects to agent's Obligations tab. "Open Obligation Matrix" button on that tab links to standalone matrix with legal category = "Condition Precedent", no stakeholder filter. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Single tag (no comma) works | Change agent config to "SHA" only | 1. Run batch extraction | Only SHA-tagged documents found. SPA-tagged docs ignored. | | |
| ☐ | E2 | Tags with whitespace trimmed | Change agent config to "SHA , SPA" (spaces around comma) | 1. Run batch extraction | Both SHA and SPA documents found (spaces trimmed). | | |
| ☐ | E3 | Zero targets — tag mismatch | Change agent config to "XYZ" (no matching docs) | 1. Run from a PI page | Agent completes with empty report. No crash. Progress shows "no document" or similar. | | |
| ☐ | E4 | PI with no matching documents skipped in batch | One PI has no docs matching any configured tag | 1. Run batch | That PI skipped in progress ("no document"). Other PIs processed normally. | | |
| ☐ | E5 | Dedup across docs on same PI | PI has both SHA and SPA docs that mention the same clause | 1. Run agent on that PI | Obligation created only once (not duplicated). | | |
| ☐ | E6 | SLO filter shows LP stakeholders | SLO obligations exist | 1. Open obligation matrix 2. Select "Side Letter Obligation" in legal category filter 3. Click Filter | Only SLO obligations shown. Stakeholder dropdown shows LPs/investors, NOT portfolio companies. | | |
| ☐ | E7 | Legal category filter preserved across filter submission | Viewing matrix with legal_category_eq = Condition Precedent | 1. Select an additional filter (e.g. Type = "Reporting") 2. Click Filter | Results filtered AND legal category still set to "Condition Precedent". | | |
| ☐ | E8 | Navigate away and return — no duplicate panels | Agent was run on a PI page | 1. Run agent on a PI page 2. Navigate to another page (e.g. Home) 3. Press Back to return to the PI page | Only ONE progress panel visible. Not duplicated. | | |
| ☐ | E9 | No legal category filter — stakeholder shows all | No filters applied | 1. Open obligation matrix without any filters | Stakeholder dropdown shows both portfolio companies and LPs. All obligation types visible. | | |
| ☐ | E10 | Clear all filters | Matrix has legal category and stakeholder pre-selected | 1. Click "Clear" button | All filters cleared. All obligations shown. Title still "LP Obligation Matrix". Stakeholder shows all. | | |

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
| ☐ | J1.5 | PI show page — results link | Click "Open Obligation Matrix" on completed report | Matrix opens with legal category pre-selected to "Condition Precedent" | | |

### Journey 2: Review Obligations in Matrix

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Obligation matrix page | Open matrix (from agent link or direct URL) | Title: "LP Obligation Matrix". Info banner explains all obligation types. | | |
| ☐ | J2.2 | Obligation matrix page | Check legal category filter | Filter shows all options: "Condition Precedent", "Condition Subsequent", "Side Letter Obligation". If arriving from agent, one is pre-selected. | | |
| ☐ | J2.3 | Obligation matrix page | Click a column header | Table rows sort by that column (client-side, no page reload) | | |
| ☐ | J2.4 | Obligation matrix page | Click Edit on a CP obligation | Edit form appears with: legal category showing only CP/CS options, MFN checkbox NOT visible | | |
| ☐ | J2.5 | Obligation matrix page — breadcrumb | Click the breadcrumb | Returns to the matrix page. No misleading "Side Letters" link. | | |
| ☐ | J2.6 | Obligation matrix page | Change legal category filter from CP to SLO, click Filter | Matrix now shows SLO obligations. Stakeholder dropdown now shows LPs, not portfolio companies. | | |

### Journey 3: Run SLO Agent from Commitment Page

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | Commitment show page | Look for the SLO Agent section | "Run SLO Agent" button visible (if agent is enabled) | | |
| ☐ | J3.2 | Commitment show page | Click "Run SLO Agent" | Progress panel appears with step indicators. | | |
| ☐ | J3.3 | Commitment show page — results | Wait for completion, click "Open Obligation Matrix" | Matrix opens with legal category pre-selected to "Side Letter Obligation". | | |

### Journey 4: CP/CS Single-Company Run

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J4.1 | Portfolio company page | Run CP/CS agent for this company | Agent extracts from this company's PIs only. | | |
| ☐ | J4.2 | Portfolio company page — results | Click "Open Obligation Matrix" after completion | Matrix opens with legal category = "Condition Precedent" AND stakeholder = this company pre-selected. | | |
| ☐ | J4.3 | Obligation matrix | Click "Clear" | All filters removed. All obligations visible. | | |

---

## Role Sweep

| ID | Screen / action | Fund manager (admin) | Counsel | Regular employee | Other-entity user |
|---|---|---|---|---|---|
| R1 | View obligation matrix | ✓ Sees own entity's obligations | ✓ Sees own entity's obligations | ✓ or ✗ per policy | ✗ No obligations from this entity visible |
| R2 | Run CP/CS Agent from PI page | ✓ Can trigger extraction | ✓ Can trigger extraction | ✗ or ✓ per policy | ✗ Cannot see the PI page |
| R3 | Run SLO Agent from commitment page | ✓ Can trigger extraction | ✓ Can trigger extraction | ✗ or ✓ per policy | ✗ Cannot see the commitment page |
| R4 | Edit obligation | ✓ Can edit | ✓ Can edit | ✗ per policy | ✗ Cannot access |
| R5 | Approve/reject obligation | ✓ or ✗ per policy | ✓ Can approve/reject | ✗ per policy | ✗ Cannot access |
| R6 | View matrix via direct URL with filter params | ✓ Sees only own entity | ✓ Sees only own entity | ✓ or ✗ per policy | ✗ Empty or redirected |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | No new emails or alerts are introduced by this change. Existing enforcement alerts unchanged. | | |
| ☐ | C2 | Dates on changed screens | Due dates on the matrix follow the user's locale format. Estimated closing date input uses date picker. | | |
| ☐ | C3 | Narrow / mobile width | Obligation matrix table scrolls horizontally on mobile. No content overflow. Run button accessible on both PI and commitment pages. | | |
| ☐ | C4 | Tenant isolation | Log in as a user from a different entity. Navigate to the obligation matrix URL with filter params. No obligations from the first entity visible. Attempt to access a PI or commitment page from the first entity directly — should be blocked. | | |
| ☐ | C5 | Regression on modified screens | PI show page still loads correctly for PIs without the CP/CS agent. Commitment page still loads without SLO agent. Documents page still works. Obligation matrix without any filters shows all obligation types as before. | | |
| ☐ | C6 | Empty states | Matrix with no obligations matching the filter shows an empty table (not an error). PI page with no agent enabled shows no Run button (not a broken section). Commitment page with no SLO agent shows no Run button. | | |
| ☐ | C7 | Old `context` param in URL | Navigate to `/side_letter_obligations?context=cp_cs` (old URL) | Page loads without error. The `context` param is ignored — all obligations shown (no crash, just unscoped). | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
