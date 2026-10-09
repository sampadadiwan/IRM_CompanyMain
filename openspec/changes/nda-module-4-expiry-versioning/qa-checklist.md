# NDA Module 4: Expiry & Version Management — Manual QA Checklist

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
| Environment | Staging (deploy the `feature/nda-module-4-expiry-versioning` branch) |
| GP Account | Fund manager at "Alpha Ventures" entity (e.g. `fm1@ian.com` / `password`) |
| LP Account 1 | Investor user at "Acme Capital" with approved InvestorAccess to Alpha Ventures |
| LP Account 2 | Investor user at "Beta Holdings" with approved InvestorAccess, **exempt** (`exempt_from_nda = true`) |
| LP Account 3 | Investor user at "Gamma Fund" with approved InvestorAccess, **no NDA acceptances** |
| Other-entity user | A user at a separate entity (e.g. "Other Corp") — for isolation checks |
| Seed data — Folder 1 | "Deal Pipeline" — Data Room folder with NDA enabled, click-through, **fixed_period 90 days**, version 1 |
| Seed data — Folder 2 | "Legal Docs" — Data Room folder with NDA enabled, click-through, **specific_date** set to a future date (e.g. 2027-01-01), version 1 |
| Seed data — Folder 3 | "Evergreen" — Data Room folder with NDA enabled, click-through, **until_revoked**, version 1 |
| Seed data — Acceptances | Acme Capital accepted all three NDAs at version 1. Gamma Fund has no acceptances. |
| Background work | None required — all checks are synchronous. For time-based expiry, ask a developer to run `travel_to` in console or manually backdate `accepted_at` on the acceptance record. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | LP sees acceptance screen after fixed-period expiry | Acme accepted Deal Pipeline NDA v1 more than 90 days ago (backdate `accepted_at`) | 1. Log in as Acme LP user. 2. Navigate to Deal Pipeline folder. | Redirected to NDA acceptance screen. A note reads: **"Your NDA acceptance has expired. Please review and re-accept."** | | |
| ☐ | H2 | LP re-accepts after fixed-period expiry | H1 setup — Acme LP is on acceptance screen | 1. Read NDA PDF. 2. Check the "I have read and agree..." checkbox. 3. Click Accept. | Redirected to Deal Pipeline folder — contents visible. New acceptance created with current date. | | |
| ☐ | H3 | GP uploads new PDF — version bumps | NDA on Deal Pipeline at version 1, Acme accepted | 1. Log in as GP. 2. Open NDA Settings for Deal Pipeline. 3. Note the version number (should say "Version 1"). 4. Upload a new PDF. 5. Observe warning banner. 6. Save. | Warning: **"Uploading a new document will require X accepted investors to re-accept the NDA."** After save, version shows "Version 2". | | |
| ☐ | H4 | LP sees acceptance screen after version bump | NDA at version 2, Acme accepted at version 1 | 1. Log in as Acme LP user. 2. Navigate to Deal Pipeline folder. | Redirected to NDA acceptance screen. A note reads: **"The NDA has been updated since you last signed. Please review and accept the new version."** | | |
| ☐ | H5 | LP re-accepts after version bump | H4 setup — Acme LP is on acceptance screen with "updated" note | 1. Check the checkbox. 2. Click Accept. | Redirected to Deal Pipeline folder — contents visible. | | |
| ☐ | H6 | LP accesses folder with valid until_revoked acceptance | Acme accepted Evergreen NDA v1 (any time ago) | 1. Log in as Acme LP user. 2. Navigate to Evergreen folder. | Folder contents shown immediately — no NDA screen. | | |
| ☐ | H7 | GP sees warning with accepted count | NDA at version 1, Acme accepted | 1. Log in as GP. 2. Open NDA Settings for Deal Pipeline. 3. Select a new PDF file (do not save yet). | Warning banner appears with the count of accepted investors. | | |
| ☐ | H8 | Dashboard shows Expired for version mismatch | NDA at version 2, Acme accepted at version 1 | 1. Log in as GP. 2. Open NDA Status Dashboard for Deal Pipeline NDA. | Acme Capital status: **"Expired"** with reason **"Version"**. | | |
| ☐ | H9 | Dashboard shows Expired for time expiry | NDA fixed_period 90d, Acme accepted > 90 days ago | 1. Log in as GP. 2. Open NDA Status Dashboard for Deal Pipeline NDA. | Acme Capital status: **"Expired"** with reason **"Period"**. Expired counter shows 1. | | |

---

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Specific-date NDA not yet expired | Acme accepted Legal Docs NDA v1, validity_date = 2027-01-01, today before that | 1. Log in as Acme LP user. 2. Navigate to Legal Docs folder. | Folder contents shown — no NDA screen. | | |
| ☐ | E2 | Specific-date NDA lapsed — dead-end page | Legal Docs NDA validity_date set to a past date (ask developer to change it) | 1. Log in as Acme LP user. 2. Navigate to Legal Docs folder. | Lapsed NDA page shown: **"This NDA expired on [date]."** No Accept or Decline buttons. "Back to Data Rooms" link visible. | | |
| ☐ | E3 | Exempt investor after version bump | NDA at version 2, Beta Holdings is exempt | 1. Log in as Beta Holdings LP user. 2. Navigate to Deal Pipeline folder. | Folder contents shown — no NDA screen. Exemption bypasses version check. | | |
| ☐ | E4 | Lapsed NDA page shows contact email | Legal Docs NDA lapsed, contact email set (e.g. legal@alpha.com) | 1. Log in as Acme LP user. 2. Navigate to Legal Docs folder. | Lapsed page shows: **"Questions? Contact: legal@alpha.com"** | | |
| ☐ | E5 | Settings change without new PDF does not bump version | NDA at version 1 | 1. Log in as GP. 2. Open NDA Settings for Deal Pipeline. 3. Change validity from 90 days to 180 days. 4. Save (without uploading a new PDF). | Version stays at 1 — no warning banner, no version change. | | |
| ☐ | E6 | Pending investor unaffected by version bump | Gamma Fund has no acceptance, NDA at version 1 | 1. Bump NDA to version 2 (upload new PDF). 2. Check dashboard. | Gamma Fund status: **"Pending"** (not Expired). | | |
| ☐ | E7 | Version bump on disabled config | Disable the NDA on Deal Pipeline | 1. Log in as GP. 2. Open NDA Settings. 3. Toggle NDA off. 4. Upload a new PDF and save. | Version stays at 1 — no version bump when disabled. | | |
| ☐ | E8 | Validity change applies retroactively | Acme accepted NDA-A 100 days ago under until_revoked | 1. Log in as GP. 2. Open NDA Settings for Deal Pipeline. 3. Change validity_type from until_revoked to fixed_period 90 days. 4. Save. 5. Check dashboard. | Acme status changes to **"Expired"** (100 days > 90 days). | | |
| ☐ | E9 | Version AND time both apply — version shown | NDA at version 2, Acme accepted v1 over 90 days ago | 1. Log in as Acme LP user. 2. Navigate to Deal Pipeline folder. | NDA acceptance screen shows "updated" note (version takes precedence over time). | | |
| ☐ | E10 | Exempt investor after time expiry | Beta Holdings exempt, accepted over 90 days ago | 1. Log in as Beta Holdings LP user. 2. Navigate to Deal Pipeline folder. | Folder contents shown — exemption bypasses time check. | | |
| ☐ | E11 | Lapsed NDA without contact email | Legal Docs NDA lapsed, no contact email set | 1. Log in as Acme LP user. 2. Navigate to Legal Docs folder. | Lapsed page shows — no contact email line displayed. | | |
| ☐ | E12 | No warning when no accepted investors | NDA with no acceptances | 1. Log in as GP. 2. Open NDA Settings. 3. Select a new PDF. | No warning banner shown (or shows "0 investors"). | | |
| ☐ | E13 | Re-uploading same filename bumps version | NDA at version 1, existing PDF named "NDA.pdf" | 1. Log in as GP. 2. Upload a new file also named "NDA.pdf". 3. Save. | Version becomes 2 — same filename still counts as a new upload. | | |

---

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Invalid reason param ignored | — | 1. Manually navigate to the NDA acceptance URL with `reason=malicious` in the query string. | Standard acceptance screen shown — no note banner, no error. Treated as first-time acceptance. | | |

---

## UI Journeys

### Journey 1 — LP re-acceptance after version bump

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Data Room folder tree | Click on a version-bumped NDA folder | Redirect to NDA acceptance screen (inside the right pane, not full page) | | |
| ☐ | J1.2 | NDA acceptance screen | Look at the top of the screen | ① Logo, ② "Back to Data Rooms" link, ③ "Non-Disclosure Agreement" title, entity and folder name below | | |
| ☐ | J1.3 | NDA acceptance screen | Read the note banner | ③ Blue/info banner: "The NDA has been updated since you last signed. Please review and accept the new version." | | |
| ☐ | J1.4 | NDA acceptance screen | Scroll to PDF area | ④ NDA PDF rendered in iframe | | |
| ☐ | J1.5 | NDA acceptance screen | Check the agreement checkbox | ⑤ Accept button becomes enabled | | |
| ☐ | J1.6 | NDA acceptance screen | Click Accept | ⑥ Full page redirects to the folder — contents now visible | | |

### Journey 2 — LP encounters lapsed specific-date NDA

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Data Room folder tree | Click on a lapsed NDA folder | Redirect to lapsed NDA page (inside right pane) | | |
| ☐ | J2.2 | Lapsed NDA page | Look at page content | Logo, folder name, expiry date, message that NDA has expired | | |
| ☐ | J2.3 | Lapsed NDA page | Look for Accept/Decline buttons | No Accept or Decline buttons present — dead-end page | | |
| ☐ | J2.4 | Lapsed NDA page | Look for contact info | Contact email shown if configured; omitted if not | | |
| ☐ | J2.5 | Lapsed NDA page | Click "Back to Data Rooms" | Returns to Data Rooms list | | |

### Journey 3 — GP version bump flow

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | NDA Settings modal | Open modal for a folder with NDA | Version number displayed (e.g. "Version 1") | | |
| ☐ | J3.2 | NDA Settings modal | Select a new PDF file | Warning banner appears with accepted investor count | | |
| ☐ | J3.3 | NDA Settings modal | Remove the new PDF selection (cancel upload) | Warning banner disappears | | |
| ☐ | J3.4 | NDA Settings modal | Select PDF again and click Save | Form saves, version increments, success message shown | | |
| ☐ | J3.5 | NDA Settings modal | Reopen modal | Version shows incremented number (e.g. "Version 2") | | |

### Journey 4 — GP dashboard with Expired status

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J4.1 | NDA Status Dashboard | Open dashboard with expired investors | "Expired" counter badge with count | | |
| ☐ | J4.2 | NDA Status Dashboard | Look at investor table | Expired investors show "Expired" status with reason indicator (Version or Period) | | |
| ☐ | J4.3 | NDA Status Dashboard | Filter by "Expired" | Only expired investors shown | | |
| ☐ | J4.4 | NDA Status Dashboard | Export to XLSX | Exported file includes "Expired" status and reason column | | |

---

## Role Sweep

| ID | Screen / action | GP admin | GP employee | LP user (non-exempt) | LP user (exempt) | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | Visit NDA-protected folder | ✓ bypass (own entity) | ✓ bypass (own entity) | Gate checks version + expiry | ✓ bypass (exempt) | ✗ no InvestorAccess |
| R2 | NDA acceptance screen (re-accept) | N/A (bypassed) | N/A (bypassed) | ✓ shown with note, can accept | N/A (bypassed) | ✗ cannot reach |
| R3 | Lapsed NDA page | N/A (bypassed) | N/A (bypassed) | ✓ dead-end page shown | N/A (bypassed) | ✗ cannot reach |
| R4 | NDA Settings modal — version display | ✓ visible | ✓ visible (if edit permission) | ✗ no access | ✗ no access | ✗ no access |
| R5 | NDA Status Dashboard — Expired status | ✓ visible | ✓ visible (if dashboard permission) | ✗ no access | ✗ no access | ✗ no access |
| R6 | Upload new NDA PDF (version bump) | ✓ can upload + save | ✗ (or ✓ depending on policy) | ✗ no access | ✗ no access | ✗ no access |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | N/A — Module 4 sends no emails. Notifications are Module 8 scope. | | |
| ☐ | C2 | Dates on changed screens | Lapsed page expiry date uses locale format (e.g. "31 December 2026"). Dashboard date columns follow existing format. | | |
| ☐ | C3 | Narrow / mobile width | NDA acceptance screen note banner, lapsed page, and version warning in Settings modal all display correctly at 375px width. No horizontal scroll. Buttons reachable. | | |
| ☐ | C4 | Tenant isolation | Log in as other-entity user. Navigate directly to NDA acceptance URL with a valid nda_config_id from Alpha Ventures. Expected: access denied or redirected. Cannot see any NDA data from another entity. | | |
| ☐ | C5 | Regression on modified screens | 1. NDA acceptance screen still works for first-time acceptance (no note). 2. NDA Settings modal still saves/creates config normally. 3. NDA Status Dashboard still shows Accepted/Pending/Declined/Exempt correctly. 4. Declined page still works. | | |
| ☐ | C6 | Empty states | 1. Dashboard with all investors expired (edge case). 2. Version warning when 0 investors accepted. Both should show sensible state. | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
