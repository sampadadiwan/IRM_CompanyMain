# NDA Module 3: GP Status Dashboard — Manual QA Checklist

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
| Environment | Staging URL |
| GP Admin account | fm1@ian.com / password — entity "Alpha Ventures", company_admin role |
| GP Employee account | A second GP employee in Alpha Ventures (for role sweep) |
| LP User account | A user under "Acme Capital" investor (e.g. alice@acme.com) with InvestorAccess to Alpha Ventures, approved, NDA-tagged |
| Exempt investor InvestorAccess | An InvestorAccess record with exempt_from_nda=true for an investor (e.g. "Delta LP") used for exemption testing |
| Other-entity GP | A GP admin from a different entity (e.g. "Beta Corp") for isolation checks |
| Second entity | "Beta Corp" with its own folder + NDA config for isolation |
| Seed data — Folder | Create or use a Data Room folder "Fund Alpha Docs" under Alpha Ventures |
| Seed data — NDA Config | Enable NDA on "Fund Alpha Docs" (click_through, until_revoked) |
| Seed data — Access Rights | Grant folder access to 3 investors: "Acme Capital" (LP), "Beta Holdings" (LP), "Gamma Fund" (LP). Use category-based access right "All LPs" if applicable, or direct investor access rights. |
| Seed data — Users per investor | Acme Capital: 5 users (alice, bob = NDA-tagged; carol, dave, eve = not NDA-tagged). Beta Holdings: 1 user (frank = NDA-tagged). Gamma Fund: 1 user (gina = NDA-tagged). |
| Seed data — Acceptances | Acme Capital: Alice accepted NDA. Gamma Fund: Gina declined NDA. Beta Holdings: no acceptance (pending). |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | GP views NDA status summary in modal | NDA enabled on folder. Acme=accepted, Beta=pending, Gamma=declined. No exempt InvestorAccess records. | 1. Log in as GP Admin (fm1@ian.com) 2. Navigate to Data Room → "Fund Alpha Docs" 3. Open NDA Settings modal 4. Click the "Status" tab | Counters show: Accepted: 1, Pending: 1, Declined: 1, Exempt: 0. Table shows 3 investor rows: Acme Capital = Accepted, Beta Holdings = Pending, Gamma Fund = Declined. "View Full Dashboard" link visible at bottom. | | |
| ☐ | H2 | GP opens dedicated dashboard | Same as H1 | 1. From the Status tab in the modal, click "View Full Dashboard" | Dedicated page opens with AG Grid table. 3 investor rows visible. Click to expand Acme Capital → 5 user rows appear: Alice (NDA) = Signer, Bob (NDA) = —, Carol = —, Dave = —, Eve = —. | | |
| ☐ | H3 | GP creates InvestorAccess with exemption | Dashboard open. No exempt InvestorAccess for the target investor. | 1. Go to Investor > Add Stakeholder User 2. Fill email, check "Exempt from NDA" checkbox 3. Save | InvestorAccess created with exempt_from_nda=true. Dashboard shows investor status = "Exempt". | | |
| ☐ | H4 | GP removes exemption by re-adding InvestorAccess | An InvestorAccess with exempt_from_nda=true exists (from H3). | 1. Delete the exempt InvestorAccess 2. Re-add the stakeholder without checking "Exempt from NDA" | Investor status reverts to Pending/Accepted/Declined (based on NDA acceptance state). | | |
| ☐ | H5 | GP exports NDA status | Dashboard open with all data. | 1. Click "Export" button on the dedicated dashboard | An XLSX file downloads. Open it and verify it contains all investors and users with columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until. | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Exempt investor accesses folder before stakeholder signs | Investor has InvestorAccess with exempt_from_nda=true. Investor has NOT accepted NDA (remove acceptance or use a fresh investor with no acceptance). | 1. Log in as a user of that investor 2. Navigate to Data Room → "Fund Alpha Docs" | Folder contents are shown immediately — no NDA acceptance screen. | | |
| ☐ | E2 | Exemption removed, stakeholder not accepted | Exempt InvestorAccess deleted, re-added without exempt flag. Investor has NOT accepted NDA. | 1. As GP, delete the exempt InvestorAccess and re-add without exempt_from_nda 2. Log in as a user of that investor 3. Navigate to Data Room → "Fund Alpha Docs" | User sees the NDA acceptance screen (redirected to sign NDA). | | |
| ☐ | E3 | Category-based access right expands | Folder has an AccessRight with category "LP" (not specific investors). Multiple LP investors in the entity. | 1. Log in as GP Admin 2. Open the NDA status dashboard for the folder | All LP-category investors in Alpha Ventures appear in the dashboard, not just individually assigned ones. | | |
| ☐ | E4 | Investor removed from access rights | Acme Capital has access to folder. Dashboard shows Acme. | 1. Remove Acme Capital's access right from the folder 2. Reload the NDA status dashboard | Acme Capital no longer appears in the dashboard. | | |
| ☐ | E9 | Status tab hidden for folder without NDA | A folder that does NOT have an NDA config enabled. | 1. Open NDA Settings modal for that folder | Only the Settings tab is visible. The Status tab is not shown. | | |
| ☐ | E10 | Inherited NDA status | A child folder inherits NDA from its parent folder. The child has its own access rights. | 1. Open NDA Settings modal on the child folder 2. Click Status tab | Status tab shows investor statuses for the parent's NDA config. The investor list comes from the child folder's access rights (may differ from parent). | | |
| ☐ | E11 | Investor fully exempt | Investor has InvestorAccess with exempt_from_nda=true. | 1. Open the dashboard | Investor-level status = "Exempt". No need for multiple users to be individually exempted. | | |
| ☐ | E12 | NDA Settings hidden on Data Room root | GP Admin logged in. | 1. Navigate to Data Room root folder 2. Open Actions dropdown | No "NDA Settings" option visible in the dropdown. | | |

---

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-GP tries to access dashboard | Logged in as LP user (alice@acme.com). | 1. Navigate directly to the NDA status dashboard URL (e.g. /nda_status?nda_config_id=X&folder_id=Y) | Access denied (403 page or redirect to unauthorized). The dashboard is not visible. | | |
| ☐ | X2 | Other-entity GP tries dashboard | Logged in as GP admin from "Beta Corp" (different entity). | 1. Navigate directly to the NDA status dashboard URL for Alpha Ventures' NDA config | Access denied (403 page or redirect to unauthorized). No Alpha Ventures data is visible. | | |
| ☐ | X3 | NDA config not found | Logged in as GP Admin. | 1. Navigate to /nda_status?nda_config_id=99999&folder_id=Y (invalid NDA config ID) | 404 Not Found page. No crash or error trace visible. | | |

---

## UI Journeys

### Journey 1: GP views NDA status summary in modal

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | NDA Settings modal | Click the "Status" tab | Tab becomes active. Settings pane hides. Status pane loads (may show a brief loading spinner). | | |
| ☐ | J1.2 | Status tab | Look at the counters area | Four badges/counters: "Accepted: 1", "Pending: 1", "Declined: 1", "Exempt: 0" (numbers match test data). | | |
| ☐ | J1.3 | Status tab | Scan the investor table | Simple HTML table with one row per investor. Columns: Investor Name, Status, Signed By, Date. Data matches test setup. | | |
| ☐ | J1.4 | Status tab | Click "View Full Dashboard" link | Browser navigates to the dedicated NDA status dashboard page. Modal closes or stays behind. | | |

### Journey 2: GP opens dedicated dashboard

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Dashboard page — toolbar | Select a status from the Filter dropdown (e.g. "Pending") | Grid filters to show only investors with "Pending" status (Beta Holdings). Other investors hidden. | | |
| ☐ | J2.2 | Dashboard page — toolbar | Type "Acme" in the Search box | Grid filters to show only Acme Capital (and its users if expanded). Other investors hidden. | | |
| ☐ | J2.3 | Dashboard page — toolbar | Click "Export" button | XLSX file downloads to browser. | | |
| ☐ | J2.4 | Dashboard page — grid | Click the expand arrow on Acme Capital row | User rows appear underneath: Alice (NDA), Bob (NDA), Carol, Dave, Eve. Each with their status. | | |
| ☐ | J2.5 | Dashboard page — expanded row | Look at Alice's row | Alice is marked as "Signer" with "(NDA)" next to her name. Signed date visible. | | |

---

## Role Sweep

| ID | Screen / action | GP Admin (same entity) | GP Employee (same entity) | LP User | Other-entity GP |
|---|---|---|---|---|---|
| R1 | View Status tab in NDA modal | ✓ Counters + table visible | ✓ Counters + table visible | ✗ Status tab not visible (LP doesn't see NDA settings modal) | ✗ Cannot open modal for another entity's folder |
| R2 | View dedicated dashboard page | ✓ Full AG Grid with all data | ✓ Full AG Grid with all data | ✗ 403 — access denied | ✗ 403 — access denied |
| R3 | Create signatory | ✓ Can tag signatory | ✓ Can tag signatory | ✗ 403 — access denied | ✗ 403 — access denied |
| R4 | Untag signatory | ✓ Can untag | ✓ Can untag | ✗ 403 — access denied | ✗ 403 — access denied |
| R5 | Export XLSX | ✓ File downloads | ✓ File downloads | ✗ 403 — access denied | ✗ 403 — access denied |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C2 | Dates on dashboard and modal | Signed Date and Valid Until columns display dates in the user's locale format (e.g. `04/10/2026` or `Oct 4, 2026`). No raw timestamps visible. | | |
| ☐ | C3 | Narrow / mobile width | Resize browser to phone width (~375px). Dashboard page has no horizontal scroll. Buttons (Export) are reachable. Modal Status tab renders without overflow. | | |
| ☐ | C4 | Tenant isolation | Log in as GP from "Beta Corp". Navigate directly to Alpha Ventures' dashboard URL. Confirm: 403 error, no Alpha Ventures data visible. Try the same for exemption endpoints. | | |
| ☐ | C5 | Regression — NDA Settings modal | Open the NDA Settings modal → Settings tab still works as before (can edit NDA config, upload document, save). Module 1 functionality unbroken. | | |
| ☐ | C6 | Regression — NDA acceptance gate | Log in as Bob (NDA-tagged, Acme accepted). Navigate to folder. Folder contents shown (stakeholder accepted). Log in as Frank (Beta, pending). Navigate to folder. NDA acceptance screen shown. Module 2 gate still works. | | |
| ☐ | C7 | Regression — Folder contents page | After all Module 3 changes, the folder contents page loads normally for an accepted user. No errors, no broken layout, documents list visible. | | |
| ☐ | C8 | Empty state — no investors | Create a folder with NDA enabled but no access rights (no investors). Open Status tab. | Dashboard shows empty state: "No investors have access to this folder" or similar message. No crash. | | |
| ☐ | C9 | XLSX file content | Open the exported XLSX. Verify: no formula injection (cells are plain text), column headers match spec (Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until), row count matches dashboard. | | |
| ☐ | C10 | Data Room root — NDA Settings hidden | Navigate to Data Room root folder, open Actions dropdown. | "NDA Settings" option is NOT visible in the dropdown. NDA settings are only available on subfolders, not root. | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Pass with defects / Fail --> | |
