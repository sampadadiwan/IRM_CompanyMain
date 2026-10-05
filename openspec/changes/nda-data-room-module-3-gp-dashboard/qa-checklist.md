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
| Exempt LP account | eve@acme.com — same investor, will be exempted during tests |
| Other-entity GP | A GP admin from a different entity (e.g. "Beta Corp") for isolation checks |
| Second entity | "Beta Corp" with its own folder + NDA config for isolation |
| Seed data — Folder | Create or use a Data Room folder "Fund Alpha Docs" under Alpha Ventures |
| Seed data — NDA Config | Enable NDA on "Fund Alpha Docs" (click_through, until_revoked) |
| Seed data — Access Rights | Grant folder access to 3 investors: "Acme Capital" (LP), "Beta Holdings" (LP), "Gamma Fund" (LP). Use category-based access right "All LPs" if applicable, or direct investor access rights. |
| Seed data — Users per investor | Acme Capital: 5 users (alice, bob = NDA-tagged; carol, dave, eve = not NDA-tagged). Beta Holdings: 1 user (frank = NDA-tagged). Gamma Fund: 1 user (gina = NDA-tagged). |
| Seed data — Acceptances | Acme Capital: Alice accepted NDA. Gamma Fund: Gina declined NDA. Beta Holdings: no acceptance (pending). |
| Background work | Reminder emails are sent via background job. After clicking "Send Reminders", wait 30 seconds and check the recipient's inbox (or ask a developer to flush the Sidekiq queue). |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | GP views NDA status summary in modal | NDA enabled on folder. Acme=accepted, Beta=pending, Gamma=declined. Eve not yet exempted. | 1. Log in as GP Admin (fm1@ian.com) 2. Navigate to Data Room → "Fund Alpha Docs" 3. Open NDA Settings modal 4. Click the "Status" tab | Counters show: Accepted: 1, Pending: 1, Declined: 1, Exempt: 0. Table shows 3 investor rows: Acme Capital = Accepted, Beta Holdings = Pending, Gamma Fund = Declined. "View Full Dashboard" link visible at bottom. | | |
| ☐ | H2 | GP opens dedicated dashboard | Same as H1 | 1. From the Status tab in the modal, click "View Full Dashboard" | Dedicated page opens with AG Grid table. 3 investor rows visible. Click to expand Acme Capital → 5 user rows appear: Alice (NDA) = Signer, Bob (NDA) = —, Carol = —, Dave = —, Eve = —. | | |
| ☐ | H3 | GP marks user as exempt | Eve is NOT exempt. Dashboard open. | 1. On the dedicated dashboard, expand Acme Capital 2. Find Eve's row 3. Click "Exempt" button on Eve's row 4. Enter reason "NDA signed offline" and confirm | Eve's status changes to "Exempt" on the dashboard. "Exempt" button is replaced with "Revoke" button. | | |
| ☐ | H4 | GP revokes exemption | Eve IS exempt (from H3). Dashboard open. | 1. On the dedicated dashboard, expand Acme Capital 2. Find Eve's row 3. Click "Revoke" button on Eve's row | Eve's status reverts to "—" (since Acme has accepted, it follows stakeholder status). "Revoke" button is replaced with "Exempt" button. | | |
| ☐ | H5 | GP exports NDA status | Dashboard open with all data. | 1. Click "Export" button on the dedicated dashboard | An XLSX file downloads. Open it and verify it contains all investors and users with columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until, Exemption Reason. | | |
| ☐ | H6 | GP sends bulk reminders | Beta Holdings is pending. Frank is NDA-tagged. Gamma declined. | 1. Click "Send Reminders" on the dashboard 2. Confirmation dialog appears: "Send NDA reminders to 1 pending investor (1 NDA-tagged user)?" 3. Click Confirm | Success message: "Reminders sent to 1 user". Wait 30s, then check Frank's email inbox — he should receive a reminder email with a link to the Data Room. Gina (Gamma, declined) should NOT receive a reminder. | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Exempt user accesses folder before stakeholder signs | Eve is exempt. Acme has NOT accepted NDA (remove Acme's acceptance or use a fresh investor with no acceptance). | 1. Log in as Eve 2. Navigate to Data Room → "Fund Alpha Docs" | Folder contents are shown immediately — no NDA acceptance screen. | | |
| ☐ | E2 | Exemption revoked, stakeholder not accepted | Eve's exemption is revoked. Acme has NOT accepted NDA. | 1. As GP, revoke Eve's exemption 2. Log in as Eve 3. Navigate to Data Room → "Fund Alpha Docs" | Eve sees the NDA acceptance screen (redirected to sign NDA). | | |
| ☐ | E3 | Category-based access right expands | Folder has an AccessRight with category "LP" (not specific investors). Multiple LP investors in the entity. | 1. Log in as GP Admin 2. Open the NDA status dashboard for the folder | All LP-category investors in Alpha Ventures appear in the dashboard, not just individually assigned ones. | | |
| ☐ | E4 | Investor removed from access rights | Acme Capital has access to folder. Dashboard shows Acme. | 1. Remove Acme Capital's access right from the folder 2. Reload the NDA status dashboard | Acme Capital no longer appears in the dashboard. | | |
| ☐ | E5 | No pending investors for reminders | All investors have either accepted or declined (none pending). | 1. Open the dashboard 2. Look at "Send Reminders" button | The "Send Reminders" button is disabled, or clicking it shows "No pending investors to remind". | | |
| ☐ | E6 | Duplicate exemption attempt | Eve is already exempt. | 1. Try to exempt Eve again (if the Exempt button is still visible or via direct URL) | No duplicate exemption created. Either the button is hidden/disabled, or an error message says "User already exempt". | | |
| ☐ | E7 | Reminder skips exempt users | Frank (Beta Holdings, NDA-tagged) is exempt. Beta is pending. | 1. Exempt Frank 2. Click "Send Reminders" | Frank does NOT receive a reminder email (he is exempt). The count message reflects 0 users reminded (or excludes Frank from the count). | | |
| ☐ | E8 | Reminder targets only NDA-tagged users | Beta Holdings is pending. Frank is NDA-tagged, Hannah is NOT NDA-tagged (add a second user to Beta without the NDA tag). | 1. Click "Send Reminders" and confirm | Only Frank receives the reminder email. Hannah does NOT receive one. | | |
| ☐ | E9 | Status tab hidden for folder without NDA | A folder that does NOT have an NDA config enabled. | 1. Open NDA Settings modal for that folder | Only the Settings tab is visible. The Status tab is not shown. | | |
| ☐ | E10 | Inherited NDA status | A child folder inherits NDA from its parent folder. The child has its own access rights. | 1. Open NDA Settings modal on the child folder 2. Click Status tab | Status tab shows investor statuses for the parent's NDA config. The investor list comes from the child folder's access rights (may differ from parent). | | |
| ☐ | E11 | Investor fully exempt | Create investor "Delta LP" with 2 users, both individually exempted. | 1. Open the dashboard | Delta LP shows investor-level status = "Exempt". | | |

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

### Journey 2: GP opens dedicated dashboard and manages exemptions

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Dashboard page — toolbar | Select a status from the Filter dropdown (e.g. "Pending") | Grid filters to show only investors with "Pending" status (Beta Holdings). Other investors hidden. | | |
| ☐ | J2.2 | Dashboard page — toolbar | Type "Acme" in the Search box | Grid filters to show only Acme Capital (and its users if expanded). Other investors hidden. | | |
| ☐ | J2.3 | Dashboard page — toolbar | Click "Export" button | XLSX file downloads to browser. | | |
| ☐ | J2.4 | Dashboard page — toolbar | Click "Send Reminders" button | Confirmation dialog appears with count of pending investors and NDA-tagged users. | | |
| ☐ | J2.5 | Dashboard page — grid | Click the expand arrow on Acme Capital row | User rows appear underneath: Alice (NDA), Bob (NDA), Carol, Dave, Eve. Each with their status. | | |
| ☐ | J2.6 | Dashboard page — expanded row | Look at Alice's row | Alice is marked as "Signer" with "(NDA)" next to her name. Signed date visible. | | |
| ☐ | J2.7 | Dashboard page — expanded row | Look at Eve's row (after exemption) | Eve shows status "Exempt" with a "Revoke" button. No "(NDA)" tag (she's not NDA-tagged). | | |

### Journey 3: GP sends bulk reminders

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | Dashboard page | Click "Send Reminders" | Confirmation dialog: "Send NDA reminders to 1 pending investor (1 NDA-tagged user)?" | | |
| ☐ | J3.2 | Confirmation dialog | Click "Confirm" | Flash/toast message: "Reminders sent to 1 user". | | |
| ☐ | J3.3 | Dashboard page (no pending investors) | Click "Send Reminders" when all investors accepted/declined | Button is disabled, or message: "No pending investors to remind". | | |

---

## Role Sweep

| ID | Screen / action | GP Admin (same entity) | GP Employee (same entity) | LP User | Other-entity GP |
|---|---|---|---|---|---|
| R1 | View Status tab in NDA modal | ✓ Counters + table visible | ✓ Counters + table visible | ✗ Status tab not visible (LP doesn't see NDA settings modal) | ✗ Cannot open modal for another entity's folder |
| R2 | View dedicated dashboard page | ✓ Full AG Grid with all data | ✓ Full AG Grid with all data | ✗ 403 — access denied | ✗ 403 — access denied |
| R3 | Create exemption | ✓ Can exempt a user | ✓ Can exempt a user | ✗ 403 — access denied | ✗ 403 — access denied |
| R4 | Revoke exemption | ✓ Can revoke | ✓ Can revoke | ✗ 403 — access denied | ✗ 403 — access denied |
| R5 | Export XLSX | ✓ File downloads | ✓ File downloads | ✗ 403 — access denied | ✗ 403 — access denied |
| R6 | Send reminders | ✓ Reminders sent | ✓ Reminders sent | ✗ 403 — access denied | ✗ 403 — access denied |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Reminder email arrives and is correct | Frank receives email at frank@beta.com. Subject contains NDA or reminder keyword. Body includes: folder name "Fund Alpha Docs", entity name "Alpha Ventures", a clickable link to the Data Room. Date shown as `Mon dd, yyyy` format (e.g. "Oct 04, 2026"). | | |
| ☐ | C2 | Dates on dashboard and modal | Signed Date and Valid Until columns display dates in the user's locale format (e.g. `04/10/2026` or `Oct 4, 2026`). No raw timestamps visible. | | |
| ☐ | C3 | Narrow / mobile width | Resize browser to phone width (~375px). Dashboard page has no horizontal scroll. Buttons (Export, Send Reminders) are reachable. Modal Status tab renders without overflow. | | |
| ☐ | C4 | Tenant isolation | Log in as GP from "Beta Corp". Navigate directly to Alpha Ventures' dashboard URL. Confirm: 403 error, no Alpha Ventures data visible. Try the same for exemption and reminder endpoints. | | |
| ☐ | C5 | Regression — NDA Settings modal | Open the NDA Settings modal → Settings tab still works as before (can edit NDA config, upload document, save). Module 1 functionality unbroken. | | |
| ☐ | C6 | Regression — NDA acceptance gate | Log in as Bob (NDA-tagged, Acme accepted). Navigate to folder. Folder contents shown (stakeholder accepted). Log in as Frank (Beta, pending). Navigate to folder. NDA acceptance screen shown. Module 2 gate still works. | | |
| ☐ | C7 | Regression — Folder contents page | After all Module 3 changes, the folder contents page loads normally for an accepted user. No errors, no broken layout, documents list visible. | | |
| ☐ | C8 | Empty state — no investors | Create a folder with NDA enabled but no access rights (no investors). Open Status tab. | Dashboard shows empty state: "No investors have access to this folder" or similar message. No crash. | | |
| ☐ | C9 | XLSX file content | Open the exported XLSX. Verify: no formula injection (cells are plain text), column headers match spec (Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until, Exemption Reason), row count matches dashboard. | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Pass with defects / Fail --> | |
