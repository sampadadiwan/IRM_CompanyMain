# NDA Version History & Resign Control — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J1.1 = journey 1, step 1) · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | Staging or local dev (`localhost:3001`) |
| GP Account | A GP user with access to an entity that has Data Room folders |
| LP Account (signatory) | An LP user tagged as signatory for the test NDA |
| LP Account (non-signatory) | An LP user under the same investor, NOT tagged as signatory |
| Second entity | A GP user in a different entity (for isolation checks) |
| Seed data | 1. Create a Data Room folder with NDA enabled. 2. Ensure at least 2 investors with approved users have access. 3. Accept the NDA as the signatory LP for at least one investor. |
| Background work | Notifications are sent via Sidekiq — ensure Sidekiq is running, or check the Sidekiq dashboard for enqueued jobs |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Upload new PDF with resign required (default) | GP logged in, NDA already created on a folder, at least 1 investor accepted | 1. Open NDA Settings modal (click lock icon on folder) 2. Upload a new PDF file 3. Verify "Require existing signatories to re-sign this version" checkbox appears inside the version warning banner 4. Leave checkbox checked (default) 5. Click Save | Version increments (check Version History section on dashboard). Accepted investor now shows "Pending" status on dashboard. Version change notification emails sent (check Sidekiq). | | |
| ☐ | H2 | Upload new PDF without resign required | GP logged in, NDA already created, at least 1 investor accepted | 1. Open NDA Settings modal 2. Upload a new PDF 3. Uncheck "Require existing signatories to re-sign this version" 4. Click Save | Version increments. Accepted investor STILL shows "Accepted" on dashboard. No notification emails sent. | | |
| ☐ | H3 | LP access after non-resign version bump | LP (signatory) who accepted version N, GP just uploaded version N+1 without resign | 1. Log in as LP signatory 2. Navigate to the NDA-protected folder | Folder opens normally — no acceptance screen shown. LP retains access. | | |
| ☐ | H4 | LP access after resign-required version bump | LP (signatory) who accepted version N, GP just uploaded version N+1 with resign required | 1. Log in as LP signatory 2. Navigate to the NDA-protected folder | NDA acceptance screen shown with the new PDF. Version mismatch note visible. LP must re-accept. | | |
| ☐ | H5 | Version history visible on dashboard | GP logged in, NDA with at least 2 versions | 1. Go to NDA Status Dashboard 2. Look for "Version History" collapsible section 3. Expand it | Shows all versions, newest first. Current version marked "(current)". Each row shows version number, upload date, uploader name, resign decision, and a download link. | | |
| ☐ | H6 | Download historical PDF | GP on dashboard, version history expanded | 1. Click the download link for a previous version | PDF downloads and is the correct file (different from the current version's PDF). | | |
| ☐ | H7 | First NDA creation creates version 1 record | GP logged in, a folder with no NDA | 1. Open NDA Settings on a folder with no NDA 2. Upload a PDF and save | NDA created. On dashboard, Version History shows "v1 (current)" with "(Initial upload)" label. | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Mixed version history — LP signed old, some non-resign, then resign | LP accepted at v2. GP uploaded v3 (no resign), then v4 (resign required) | 1. Log in as LP signatory 2. Navigate to NDA-protected folder | Acceptance screen shown — v4 required resign, so v2 acceptance is stale. | | |
| ☐ | E2 | All versions since acceptance are non-resign | LP accepted at v2. GP uploaded v3 (no resign), v4 (no resign), v5 (no resign) | 1. Log in as LP signatory 2. Navigate to NDA-protected folder | Folder opens normally — no version required re-signing. | | |
| ☐ | E3 | Non-signatory access after resign-required bump | Non-signatory LP, investor accepted at v2, GP uploaded v3 with resign | 1. Log in as non-signatory LP 2. Navigate to NDA-protected folder | Blocked page shown: "Please ensure that the authorised signatory has signed the NDA to access the documents." | | |
| ☐ | E4 | Non-signatory access after non-resign bump | Non-signatory LP, investor accepted at v2, GP uploaded v3 without resign | 1. Log in as non-signatory LP 2. Navigate to NDA-protected folder | Folder opens normally — investor acceptance still valid. | | |
| ☐ | E5 | Edit NDA settings without uploading new PDF | GP logged in, NDA exists | 1. Open NDA Settings 2. Change contact email only (no new PDF) 3. Click Save | Settings saved. No version change. No resign checkbox shown. Version history unchanged. | | |
| ☐ | E6 | Resign checkbox not shown on first NDA creation | GP logged in, folder with no NDA | 1. Open NDA Settings on a new folder 2. Upload PDF and fill in settings | No resign checkbox or version warning shown — this is the first version. | | |
| ☐ | E7 | Exempt investor after resign-required bump | Exempt investor, GP uploaded new version with resign | 1. Log in as LP of exempt investor 2. Navigate to NDA-protected folder | Folder opens — exemption bypasses all NDA checks. | | |

---

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Double-submit on NDA update | GP logged in, NDA settings modal open with new PDF | 1. Click Save rapidly twice | NDA saved once. One version record created. No duplicate version error shown. | | |

---

## UI Journeys

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | J1.1 | Resign checkbox appears on PDF upload | GP editing existing NDA | 1. Open NDA Settings 2. Upload a new PDF | Version warning banner appears with the resign checkbox inside it. Checkbox is checked by default. | | |
| ☐ | J1.2 | Resign checkbox disappears if upload cancelled | GP editing existing NDA, new PDF selected | 1. After checkbox appears, remove the uploaded file (if possible) or close and reopen modal | Resign checkbox no longer visible (warning banner hidden). | | |
| ☐ | J2.1 | Version history section on dashboard | GP on NDA Status Dashboard | 1. Look for "Version History" section | Collapsible section exists, collapsed by default. Shows count of versions. | | |
| ☐ | J2.2 | Expand version history | GP on dashboard | 1. Click "Version History" toggle | Expands to show table of all versions with download links. | | |
| ☐ | J2.3 | Version history after multiple uploads | GP uploaded v1, v2 (no resign), v3 (resign) | 1. View version history on dashboard | Shows: v3 (current) — Resign: Required, v2 — Resign: Not required, v1 — (Initial upload). All have download links. | | |

---

## Role Sweep

| ☐ | ID | Role | Action | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | GP (same entity) | Upload new PDF with resign toggle | Can see resign checkbox, can save, version record created | | |
| ☐ | R2 | GP (different entity) | Try to access NDA settings of another entity's folder | Access denied — cannot see or modify the NDA | | |
| ☐ | R3 | LP (signatory) | Visit folder after non-resign bump | Folder opens (acceptance still valid) | | |
| ☐ | R4 | LP (signatory) | Visit folder after resign bump | Acceptance screen shown | | |
| ☐ | R5 | LP (non-signatory) | Visit folder after resign bump | Blocked page shown | | |
| ☐ | R6 | LP (exempt investor) | Visit folder after resign bump | Folder opens (exempt bypasses all) | | |

---

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Notification email received (resign=true) | Upload new PDF with resign checked. Check LP email inbox. | LP receives "A new NDA version has been uploaded" email with correct version numbers. | | |
| ☐ | C2 | No notification email (resign=false) | Upload new PDF with resign unchecked. Wait 2 minutes. | LP does NOT receive any version change email. | | |
| ☐ | C3 | Dates in locale format | View version history on dashboard | Upload dates display in the application's short date format, not raw timestamps. | | |
| ☐ | C4 | Narrow/mobile width | Open NDA Settings modal and NDA Status Dashboard on a narrow browser window (375px) | Resign checkbox wraps correctly inside warning banner. Version history table scrolls horizontally if needed. | | |
| ☐ | C5 | Tenant isolation | Log in as GP of entity B. Navigate to NDA Status Dashboard for entity A's folder. | Access denied. Version history of entity A is not visible. | | |
| ☐ | C6 | Regression — existing NDA accept flow | LP (signatory) visits folder with NDA never version-bumped (v1 only) | Standard acceptance screen shown, can accept, folder opens after acceptance. | | |
| ☐ | C7 | Regression — NDA settings save without version change | GP edits contact email without uploading new PDF | Settings saved, no version bump, no resign checkbox shown, no notification. | | |

---

## Sign-off

| Tester | Build / Commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
