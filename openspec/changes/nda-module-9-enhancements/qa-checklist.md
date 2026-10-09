# NDA Module 9 — Signatory Gating & Enhancements — Manual QA Checklist

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
| Environment | Staging (or local with `rails s -p 3001`) |
| GP account | Log in as a GP user (e.g. `fm1@ian.com` / `password`) who owns the entity |
| Signatory LP account | An LP user who will be tagged as signatory (must have approved InvestorAccess to the GP's entity) |
| Non-signatory LP account | A second LP user under the same investor, NOT tagged as signatory |
| Exempt LP account | An LP user whose investor has `exempt_from_nda: true` |
| Second entity user | A user from a completely different entity (for isolation checks) |
| Seed data | 1. Create a Data Room folder. 2. Do NOT create NDA settings yet (tests start from first creation). 3. Ensure at least one investor has 2+ LP users with InvestorAccess. |
| Background work | No background jobs needed — all features are synchronous |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Signatory can accept NDA | LP user is tagged as signatory for this NDA config, NDA not yet accepted | 1. Log in as signatory LP 2. Navigate to the NDA-protected Data Room folder 3. See NDA acceptance screen with PDF 4. Check "I have read and agree..." checkbox 5. Click Accept | Redirected to folder contents. Folder is accessible. | | |
| ☐ | H2 | Non-signatory sees blocked page | LP user is NOT tagged as signatory, NDA not yet accepted for their investor | 1. Log in as non-signatory LP 2. Navigate to the same NDA-protected folder | See blocked page with message: "NDA acceptance is pending. A designated signatory for your organisation must accept the NDA before you can access this folder." Entity logo, folder name, and contact email shown. No PDF, no Accept/Decline buttons. | | |
| ☐ | H3 | GP guided to tag signatories after first NDA creation | No NDA config exists on the folder yet | 1. Log in as GP 2. Go to Documents, open a Data Room folder 3. Click the NDA settings icon (lock) 4. Fill in NDA settings (upload PDF, choose Click-through, Until Revoked) 5. Click Save | Redirected to the NDA Status Dashboard (not back to Documents). Banner shows: "NDA settings saved. Tag designated signatories for each investor below." All investor rows are auto-expanded showing user details with Tag/Untag buttons. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Non-signatory cannot accept via URL crafting | LP user is NOT tagged as signatory | 1. Log in as non-signatory LP 2. Manually navigate to the NDA acceptance screen URL (`/nda_acceptances?nda_config_id=X&folder_id=Y`) | Redirected to the blocked page. Non-signatory cannot see the acceptance screen, PDF, or buttons. | | |
| ☐ | E2 | Non-signatory blocked after version bump | NDA was accepted at v1, GP uploaded new PDF (v2), LP user is NOT a signatory | 1. Log in as non-signatory LP 2. Navigate to the NDA-protected folder | See blocked page (NOT the acceptance screen with version mismatch note). Message: "NDA acceptance is pending..." | | |
| ☐ | E3 | Exempt investor bypasses signatory gate | Investor is marked exempt from NDA, LP user is NOT a signatory | 1. Log in as exempt LP user 2. Navigate to the NDA-protected folder | Folder opens directly. No NDA screen, no blocked page. | | |
| ☐ | E4 | GP updating existing NDA does NOT redirect to dashboard | NDA config already exists on the folder | 1. Log in as GP 2. Open the NDA settings modal on a folder that already has NDA configured 3. Change a setting (e.g. validity type) 4. Click Save | Modal updates in-place (turbo stream). GP stays on the Documents page. No redirect to the dashboard. | | |
| ☐ | E5 | Zero-signatory warning on dashboard | At least one investor has no users tagged as signatory for this NDA | 1. Log in as GP 2. Navigate to the NDA Status Dashboard for the folder | Investors with no signatories show a ⚠ warning icon. Hover over it — tooltip reads: "No signatories tagged — no one can accept the NDA for this investor" | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-signatory cannot decline via URL crafting | LP user is NOT tagged as signatory | 1. Log in as non-signatory LP 2. Manually POST to the decline URL (`/nda_acceptances/decline?nda_config_id=X&folder_id=Y`) or use browser dev tools | Redirected to the blocked page. No NdaAcceptance record created. No notification sent. | | |

---

## UI Journeys

### Journey 1: Non-signatory blocked, then signatory accepts, then non-signatory gains access

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Documents page | Log in as non-signatory LP, click on NDA-protected folder | Folder gate fires, blocked page appears inside the right pane (documents_frame) | | |
| ☐ | J1.2 | Blocked page | Read the page | Entity logo at top, folder name in subtitle, alert-info box with lock icon and "NDA acceptance is pending..." message, contact email if configured, "Back to Data Rooms" link. No PDF iframe. No buttons. | | |
| ☐ | J1.3 | Blocked page | Click "Back to Data Rooms" | Navigated back to Data Rooms folder list | | |
| ☐ | J1.4 | Documents page | Log in as signatory LP, click on same NDA-protected folder | NDA acceptance screen appears with PDF iframe, checkbox, Accept and Decline buttons | | |
| ☐ | J1.5 | NDA acceptance screen | Check checkbox, click Accept | Redirected to folder contents | | |
| ☐ | J1.6 | Documents page | Log back in as non-signatory LP, click on the same folder | Folder opens — contents are visible (stakeholder-level access granted by signatory's acceptance) | | |

### Journey 2: GP creates first NDA and tags signatories

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Documents page | Log in as GP, open NDA settings on a folder with no NDA | NDA settings modal opens with empty form | | |
| ☐ | J2.2 | NDA settings modal | Upload PDF, set acceptance method to Click-through, validity to Until Revoked, enter contact email. Click Save | Page redirects to NDA Status Dashboard (full page load, not modal update) | | |
| ☐ | J2.3 | NDA Status Dashboard | Read the page | Green dismissible banner at top: "NDA settings saved. Tag designated signatories for each investor below." All investor rows are expanded showing users. | | |
| ☐ | J2.4 | NDA Status Dashboard | Find an investor with ⚠ warning, click Tag next to a user | User is tagged as signatory. "Signatory" badge appears. ⚠ warning disappears for that investor. | | |
| ☐ | J2.5 | NDA Status Dashboard | Click ✕ on the banner | Banner is dismissed. Does not reappear on page refresh (unless `first_creation=true` is still in the URL). | | |

---

## Role Sweep

| ID | Screen / action | GP (same entity) | Signatory LP | Non-signatory LP | Exempt LP | Other-entity user |
|---|---|---|---|---|---|---|
| R1 | Access NDA-protected folder | ✓ Folder opens (GP bypass) | ✓ Acceptance screen (if not accepted) | ✗ Blocked page | ✓ Folder opens (exemption) | ✗ No InvestorAccess |
| R2 | Accept NDA | N/A (GP bypasses) | ✓ Can accept | ✗ Redirected to blocked | N/A (exempt) | ✗ No InvestorAccess |
| R3 | Decline NDA | N/A | ✓ Can decline | ✗ Redirected to blocked | N/A | ✗ No InvestorAccess |
| R4 | View NDA Status Dashboard | ✓ Full access | ✗ Not accessible (GP only) | ✗ Not accessible | ✗ Not accessible | ✗ Not accessible |
| R5 | Tag/Untag signatories | ✓ Can tag/untag | ✗ Not accessible | ✗ Not accessible | ✗ Not accessible | ✗ Not accessible |
| R6 | See blocked page | N/A | N/A (sees acceptance screen) | ✓ Sees blocked page | N/A | ✗ No InvestorAccess |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature | No new emails — Module 8 notifications unchanged. Verify that existing accept/decline notifications still fire when a signatory accepts/declines. | | |
| ☐ | C2 | Dates on changed screens | N/A — no new dates displayed on blocked page or first-creation banner | | |
| ☐ | C3 | Narrow / mobile width | Blocked page renders properly on mobile (no horizontal scroll, text wraps, Back button reachable). Dashboard banner wraps neatly. | | |
| ☐ | C4 | Tenant isolation | A user from a different entity cannot access the blocked page or NDA acceptance screen for another entity's NDA config (even with a direct URL with nda_config_id from another entity) | | |
| ☐ | C5 | Regression on modified screens | 1. NDA acceptance screen still works for signatories (PDF loads, checkbox enables button, accept creates record). 2. NDA declined page still works after signatory decline. 3. NDA Status Dashboard still shows correct counters, filters, search, export, revoke, send reminders. 4. NDA settings update still closes modal with turbo stream (no redirect). | | |
| ☐ | C6 | Empty states | Dashboard with no investors shows existing empty state. Dashboard with investors but no signatories shows ⚠ per investor (not a broken state). | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
