# KYC Agent Dashboard — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging or local dev |
| Account: Fund Manager | A user with access to Support Agents, entity "Alpha Capital" |
| Account: Other Entity | A user in a different entity (for isolation checks) |
| Seed data: KYC Agent | KYC Onboarding Agent enabled for Alpha Capital with LLM key configured |
| Seed data: KYCs | At least 5 completed KYCs: 1 Individual with all docs (successful), 1 Individual expired (partially failed), 1 Non-Individual with missing docs (failed), 1 Individual with no agent report (pending), 1 Non-Individual successful |
| Seed data: Funds | Two funds (Fund Alpha, Fund Beta) with capital commitments linking to the KYCs |
| Seed data: Investors | At least two investors linked to the KYCs |
| Seed data: Documents | KYC-001: 5 uploaded docs (all required present). KYC-003: 4 of 7 required docs uploaded. KYC-004: 0 of 5 required docs uploaded |
| Seed data: FormCustomFields | File-type required fields configured for both Individual and Non-Individual form types |
| Background work | "Run Agent on All Pending" button triggers agent runs. No manual job execution needed. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Dashboard loads with correct stats | 5 KYCs as per setup | 1. Open KYC Onboarding Agent page 2. Click "KYC Dashboard" tab | **Row 1 (KYC Form Status):** Five cards showing Not Sent, Link Sent, Draft Saved, Completed, Verified counts across ALL entity KYCs. **Row 2 (Agent Validation Status):** Six stat cards: Validated=5, Pending=1, Successful=2, Failed=1, Partially Failed=0, Expired=1. Row 2 counts are mutually exclusive (sum to Validated). KYC-002 is expired so it counts as Expired only, not Partially Failed. Each Row 2 card shows a percentage. Table shows 5 rows. | | |
| ☐ | H1b | Basic metrics navigate to KYC page | Dashboard loaded with Row 1 cards | 1. Click "Link Sent" card in Row 1 | Browser navigates to the normal KYC list page filtered by "Link Sent" status. The KYC page shows only investors whose KYC link has been sent. | | |
| ☐ | H2 | Stat card filters the table | Dashboard loaded | 1. Click "Successful" stat card in Row 2 | Table shows only 2 rows (the successful KYCs). "Successful" card is highlighted with a distinct border. | | |
| ☐ | H3 | Stat card toggle clears filter | "Successful" card active | 1. Click "Successful" card again | Table shows all 5 rows. No card highlighted. | | |
| ☐ | H4 | Bulk run on pending KYCs | 1 pending KYC exists | 1. Click "Run Agent on All Pending" button 2. Confirm in modal | Batch progress panel appears. Progress shows "Processing... 1/1". On completion, "Pending" card drops to 0. Table row updates with status and result. | | |
| ☐ | H5 | Charts show correct breakdown | KYCs of both types exist with reports | 1. View the charts section | Two half-donut (semicircle) charts: "Individual" on left, "Non-Individual" on right. Each shows colored segments for Successful, Partially Failed, Failed, Expired with percentages. | | |
| ☐ | H6 | Run output panel opens | KYC with successful report exists | 1. Click eye icon on a successful KYC row | Detail panel expands below the clicked row. Header shows KYC ID, Customer Name, Run Date. Table shows items with Matched/Warning/Failed status badges. All items show "Matched". | | |
| ☐ | H7 | Mark Verified from table | KYC with successful report | 1. Click "Mark Verified" (check icon) on a successful KYC row | Row refreshes. Status changes. Toast or confirmation shown. | | |
| ☐ | H8 | Docs column shows upload ratio with tooltip | KYC with 3 required docs and 3 uploaded; another with 5 required and 2 uploaded | 1. View the table 2. Hover over a Docs cell | First KYC shows "3 / 3" in green. Second shows "2 / 5" in orange. Hovering shows tooltip: "Required: PAN, Address Proof, ... / Uploaded: PAN, ... / Missing: Declaration, ...". KYCs with no required file fields show "—". | | |
| ☐ | H8b | Documents tab in detail panel | KYC with mixed results (field issues + document issues) | 1. Click eye icon on a KYC row 2. Click "Documents" tab | Only document-related items shown (not field checks). Click "All" to see everything again. Document count in tab label matches. | | |
| ~~☐~~ | ~~H9~~ | ~~Export CSV — removed, not in product design~~ | — | — | — | — | — |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No completed KYCs | Entity has 0 completed KYCs | 1. Open KYC Dashboard tab | **Row 1 (basic metrics):** May show non-zero counts for Not Sent, Link Sent, Draft Saved (KYCs exist but none completed). **Row 2 (agent stats):** All six cards show 0. Empty state message: "No KYC submissions yet..." Table is empty. | | |
| ☐ | E2 | All KYCs pending (never run) | 5 completed KYCs, agent never run | 1. Open KYC Dashboard tab | Validated=5, Pending=5, Successful=0, Failed=0, Partially Failed=0, Expired=0. All rows show "Pending" status. Charts show no data or empty state. | | |
| ☐ | E3 | Combined stat card + dropdown filter | Dashboard loaded | 1. Click "Failed" stat card 2. Select "Individual" in Customer Type dropdown | Table shows only Individual KYCs that failed. Both filters are active. | | |
| ☐ | E4 | No KYCs of one type | Entity has only Individual KYCs | 1. View charts | Individual chart shows data. Non-Individual chart shows "No Non-Individual KYCs" or similar empty state. | | |
| ☐ | E4b | Non-individual count accuracy | Entity has both Individual and Non-Individual KYCs (at least 8 non-individuals) | 1. View charts | Non-Individual chart shows correct count matching the actual non-individual KYCs in the entity. Compare with the count on the normal KYC page filtered by "Non-Individual". | | |
| ☐ | E5 | Expired is mutually exclusive | A KYC has expired expiry_date and a blocked report with some successes | 1. Click "Expired" card — see the KYC 2. Click "Partially Failed" card | The KYC appears in "Expired" only. It does NOT appear in "Partially Failed". Stat cards are mutually exclusive — counts sum to Validated. | | |
| ☐ | E6 | Fund filter narrows everything | 2 funds with different KYCs | 1. Select "Fund Alpha" in fund dropdown | Stat cards, charts, table, and top failure reasons all update to show only Fund Alpha's KYCs. Select "All Funds" to restore. | | |
| ☐ | E7 | Top failures with no failures | All reports are successful | 1. View top failure reasons panel | Panel shows "No failures found" or is hidden. | | |
| ☐ | E7b | Failure reason drill-down | At least one failure reason with affected investors | 1. Click on a failure reason row (e.g. "Missing PAN Number (12)") | Row expands to show list of affected investor names as links to their KYC pages. Clicking the same row again collapses the list. Links navigate to the correct KYC page. | | |
| ☐ | E8 | Detail panel tabs filter items | KYC with mixed results (some matched, some failed, some warning) | 1. Click eye icon (detail row expands below) 2. Click "Failed" tab | Only failed items shown. Click "All Items" to see all again. | | |
| ☐ | E9 | Eye icon disabled for pending KYC | KYC with no agent report | 1. Look at the pending KYC row | Eye icon is disabled (greyed out) or hidden. Cannot open detail panel. | | |
| ☐ | E10 | Mark Verified hidden for failed KYC | KYC with failed agent report | 1. Look at the failed KYC row actions | "Mark Verified" (check icon) is NOT shown. Other actions (eye, re-run) are available. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Bulk run fails (no LLM key) | Remove LLM API key from entity settings | 1. Click "Run Agent on All Pending" 2. Confirm | Batch completes. All KYCs show "Failed" status. Stat cards update with increased Failed count. Opening a failed row's detail shows the error. | | |
| ☐ | X2 | Re-run agent on existing report | KYC that already has a report | 1. Click "Re-run Agent" (play icon) on the row | Agent re-runs. Row shows a spinner/loading state. On completion, row refreshes with updated results. Old report is replaced. | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Agent show page | Click "KYC Dashboard" tab | Dashboard tab content loads without full page reload. Row 1 (basic metrics) + Row 2 (agent stats) + charts + table are visible. | | |
| ☐ | J1.1b | KYC Dashboard | Click a Row 1 card (e.g. "Link Sent") | Browser navigates to the normal KYC page filtered by that status. Back button returns to the agent dashboard. | | |
| ☐ | J1.2 | KYC Dashboard | Click a Row 2 stat card | Table filters. Card becomes highlighted. URL does NOT change in browser bar (no history push). | | |
| ☐ | J1.3 | KYC Dashboard | Change Customer Type dropdown to "Individual" | Table reloads (Turbo Frame) showing only Individual KYCs. Page does not fully reload. | | |
| ☐ | J1.4 | KYC Dashboard | Enter text in Search box, press Enter or wait | Table filters to KYCs matching the search (by KYC ID, Customer Name, or PAN). | | |
| ☐ | J1.5 | KYC Dashboard | Set Submitted On date range | Table shows only KYCs submitted within that range. | | |
| ☐ | J1.6 | KYC Dashboard | Click "Clear Filters" | All dropdowns reset to "All". Search box clears. Date range clears. Stat card deselected. Table shows all rows. | | |
| ☐ | J1.7 | KYC Dashboard table | Click page 2 in pagination | Table shows rows 11-20. Stats and charts remain unchanged. | | |
| ☐ | J1.8 | KYC Dashboard | Click "Run Agent on All Pending" | Confirmation modal appears with pending count. | | |
| ☐ | J1.9 | Confirmation modal | Click "Confirm" / "Run" | Modal closes. Batch progress panel appears below the button. Button becomes disabled with spinner. | | |
| ☐ | J1.10 | Batch progress panel | Wait for completion | Progress updates in real-time. On completion, panel shows summary. Stats and table refresh. Button re-enables. | | |
| ☐ | J1.11 | Run output panel (inline) | Click Close button | Detail row collapses. Table row returns to normal. | | |
| ☐ | J1.12 | Run output panel (inline) | Click eye icon again on same row | Detail row toggles closed. | | |
| ~~☐~~ | ~~J1.13~~ | ~~Run output panel~~ | ~~Click outside the panel~~ | ~~Removed — inline panel doesn't need click-outside-to-close~~ | — | — |
| ☐ | J1.14 | KYC Dashboard | Change Fund dropdown | All components refresh: stat cards, charts, table, top failure reasons. | | |

---

## Role Sweep

| ID | Screen / action | Fund Manager (agent access) | User without agent access | Investor user | Other-entity Fund Manager |
|---|---|---|---|---|---|
| R1 | Open KYC Dashboard tab | ✓ Tab visible, data loads | ✗ Agent page not accessible | ✗ Agent page not accessible | ✗ Cannot see this entity's agent |
| R2 | Click "Run Agent on All Pending" | ✓ Batch runs | ✗ N/A (can't reach page) | ✗ N/A | ✗ N/A |
| R3 | Click "Mark Verified" | ✓ KYC verified | ✗ N/A | ✗ N/A | ✗ N/A |
| R4 | Access `kyc_run_output` with direct URL | ✓ Panel renders | ✗ 403 or redirect | ✗ 403 or redirect | ✗ 403 or redirect (different entity) |
| ~~R5~~ | ~~Export CSV — removed, not in product design~~ | — | — | — | — |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Docs column accuracy | Docs column shows uploaded/required count. Hover tooltip lists doc names (required, uploaded, missing). Compare with actual documents on the KYC page — counts and names should match. Agent validation results are in the detail panel's "Documents" tab. | | |
| ☐ | C2 | Dates on dashboard | "Submitted On" and "Agent Run On" columns show dates in user's locale format (e.g. `27/10/2026` for en-IN). | | |
| ☐ | C3 | Narrow / mobile width | Dashboard is usable at 768px width. Stat cards stack vertically. Table scrolls horizontally. No horizontal page scroll. | | |
| ☐ | C4 | Tenant isolation | Log in as a user from a different entity. Navigate to `/support_agents/<id>/kyc_run_output?report_id=<id>` using the first entity's report ID. Should get 403 or 404, NOT the report data. Also verify Docs column does not leak cross-entity data. | | |
| ☐ | C5 | Regression: Agent General tab | The General tab still shows agent config correctly. | | |
| ☐ | C5b | Regression: Agent Schedule tab | The Schedule tab still shows schedule correctly. | | |
| ☐ | C5c | Regression: Agent Execution History tab | The Execution History tab still shows logs correctly. | | |
| ☐ | C5d | Regression: Individual KYC page agent cards | Open an individual KYC page. The per-KYC stat cards (Missing Fields, Missing Docs, etc.) still render correctly. | | |
| ☐ | C6 | Empty states | Dashboard with no data shows "No KYC submissions yet." Charts with no data show empty state. Table with no matching filter results shows "No results found." | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
