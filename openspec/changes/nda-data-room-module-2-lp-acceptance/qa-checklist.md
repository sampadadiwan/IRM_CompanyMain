# NDA Module 2: LP Acceptance Flow (Stakeholder-Level) — Manual QA Checklist

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
| Environment | Staging or local dev server (port 3001) |
| GP Admin account | A company_admin user for entity "Alpha Ventures" (e.g. `fm1@ian.com` / `password`) |
| LP User A | An investor user for Investor "Acme Capital", with InvestorAccess to Alpha Ventures (approved, NDA tag) |
| LP User B | Another investor user for the **same** Investor "Acme Capital", with InvestorAccess to Alpha Ventures (approved, no NDA tag) — for stakeholder-level tests |
| LP User C | An investor user for a **different** Investor "Beta Holdings", with InvestorAccess to Alpha Ventures — for isolation checks |
| Other-entity GP | A company_admin from a different entity (for tenant isolation) |
| Seed data — Data Room | Alpha Ventures must have Data Room enabled with at least 4 folders: "Data Room" (root), "Deal Pipeline" (child, inherit), "Fund Alpha Docs" (child, own NDA), "Public Info" (child, opt_out) |
| Seed data — NDA-A | NDA config on "Data Room" folder: enabled=true, click_through, validity=until_revoked, contact_email=legal@alpha.com, PDF uploaded |
| Seed data — NDA-B | NDA config on "Fund Alpha Docs" folder: enabled=true, click_through, no contact_email, PDF uploaded |
| Seed data — Access Rights | LP User A, B, and C must have access rights to all 4 folders above |
| Seed data — InvestorAccess | LP User A: InvestorAccess for Acme Capital → Alpha Ventures (approved=true, tag_list includes "NDA"). LP User B: InvestorAccess for Acme Capital → Alpha Ventures (approved=true, no NDA tag). LP User C: InvestorAccess for Beta Holdings → Alpha Ventures (approved=true). |
| Background work | None required for this feature |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | LP User A accepts NDA on behalf of stakeholder | LP User A logged in, no prior acceptance for NDA-A by Acme Capital | 1. Go to Data Rooms listing 2. Click "Alpha Ventures" Data Room 3. See NDA acceptance screen 4. Check confirmation checkbox 5. Click Accept | Redirected to Data Room folder, folder contents visible. DB: nda_acceptances record has investor_id = Acme Capital's investor_id, user_id = User A's id | | |
| ☐ | H2 | LP User A accesses folder after acceptance | LP User A has accepted NDA-A (from H1) | 1. Navigate away 2. Click "Alpha Ventures" Data Room again | Folder contents shown immediately — no NDA screen | | |
| ☐ | H3 | LP User A declines NDA | LP User A logged in, no prior acceptance for NDA-A | 1. Go to Data Rooms listing 2. Click Data Room 3. See NDA screen 4. Click Decline | Decline page shown: "You have declined the Non-Disclosure Agreement for the folder 'Data Room'." with contact email and retry link | | |
| ☐ | H4 | LP retries after decline | LP User A on decline confirmation page (from H3) | 1. Click "Try Again" | NDA acceptance screen shown again | | |
| ☐ | H5 | Acceptance screen shows all elements | LP User A on NDA acceptance screen | Observe the screen | PDF document shown inline, entity name ("Alpha Ventures"), folder name ("Data Room"), unchecked checkbox, disabled Accept button, enabled Decline button, "Questions? Contact: legal@alpha.com" shown | | |
| ☐ | H6 | Another user of same stakeholder accesses folder | LP User A has accepted NDA-A (from H1). LP User B logged in (same Investor "Acme Capital", no NDA tag) | 1. LP User B goes to Data Rooms listing 2. Click "Alpha Ventures" Data Room | Folder contents shown immediately — no NDA screen. User A's acceptance covers the whole stakeholder. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Inherited NDA already accepted | LP accepted NDA-A on Data Room | 1. Navigate to "Deal Pipeline" (child folder, inherits NDA-A) | Folder contents shown immediately — no NDA screen (NDA-A already accepted) | | |
| ☐ | E2 | Child with own NDA requires separate acceptance | LP accepted NDA-A on Data Room | 1. Navigate to "Fund Alpha Docs" (has own NDA-B) | NDA acceptance screen shown for NDA-B (different NDA document) | | |
| ☐ | E3 | Opted-out folder — no gate | LP has no acceptances | 1. Navigate to "Public Info" (opt_out mode) | Folder contents shown — no NDA screen | | |
| ☐ | E4 | Folder with no NDA | LP logged in | 1. Navigate to a Data Room folder that has no NDA configured | Folder contents shown — no NDA screen | | |
| ☐ | E5 | GP employee bypasses gate | GP Admin logged in | 1. Navigate to "Data Room" (NDA-A active) | Folder contents shown — no NDA screen (GP employees bypass NDA gate) | | |
| ☐ | E6 | NDA disabled | GP disables NDA-A (enabled=false) | 1. LP navigates to "Data Room" | Folder contents shown — no NDA screen | | |
| ☐ | E7 | E-sign falls back to click-through | GP changes NDA-A acceptance_method to "esign" | 1. LP navigates to "Data Room" | Standard click-through NDA screen shown (not an error) | | |
| ☐ | E8 | Acceptance screen without contact email | LP on NDA screen for NDA-B (no contact_email) | Observe the screen | No "Questions? Contact:" line displayed | | |
| ☐ | E9 | Multiple acceptance records preserved | LP accepted, then repeat acceptance flow (after clearing acceptance via DB) | 1. Check DB: multiple nda_acceptances rows for same investor+config | Both records exist with investor_id and timestamps | | |
| ☐ | E10 | Accept button disabled without checkbox | LP on NDA acceptance screen | 1. Do NOT check the checkbox 2. Try to click Accept | Accept button is visually disabled and not clickable | | |
| ☐ | E11 | Decline by one user does not block another user of same stakeholder | LP User A accepted NDA-A. LP User C (different investor) declined NDA-A. | 1. LP User A accesses folder → contents shown (Acme Capital accepted) 2. LP User C accesses folder → NDA screen shown (Beta Holdings has no acceptance, only a decline) | User A's stakeholder is unaffected by User C's decline. | | |
| ☐ | E12 | User with no InvestorAccess cannot reach NDA screen | A user with no InvestorAccess record for Alpha Ventures | 1. Navigate directly to NDA acceptance URL | Denied by policy — user has no investor relationship with this entity | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Invalid return_to URL | LP on acceptance screen | 1. Manually alter the return_to param in the URL to "https://evil.com" 2. Accept NDA | Redirected to Data Rooms listing page (not to evil.com) | | |
| ☐ | X2 | Missing return_to | LP on acceptance screen | 1. Remove the return_to param from the URL 2. Accept NDA | Redirected to Data Rooms listing page | | |
| ☐ | X3 | NDA config not found | None | 1. Navigate to /nda_acceptances?nda_config_id=99999 | 404 error page | | |
| ☐ | X4 | Acceptance record audit fields | LP User A accepts NDA-A | 1. Check DB: nda_acceptances record | Record contains: nda_config_id, investor_id (Acme Capital), user_id (User A), entity_id, status="accepted", nda_version=1, ip_address (not null), user_agent (not null), accepted_at (not null), created_at | | |

---

## UI Journeys

### Journey 1: LP accepts NDA to access folder

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Data Rooms listing | Click "Alpha Ventures" Data Room link | Redirected to NDA acceptance screen (not folder contents) | | |
| ☐ | J1.2 | NDA acceptance screen | Observe layout | Minimal layout — no sidebar, no header navigation. Company logo visible. "Back to Data Rooms" link visible. | | |
| ☐ | J1.3 | NDA acceptance screen | Observe NDA document | PDF rendered inline in a scrollable frame. Can read the full document. | | |
| ☐ | J1.4 | NDA acceptance screen | Observe context info | Title "Non-Disclosure Agreement", entity name "Alpha Ventures", folder name "Data Room" | | |
| ☐ | J1.5 | NDA acceptance screen | Check the confirmation checkbox | Accept button becomes enabled (was disabled before) | | |
| ☐ | J1.6 | NDA acceptance screen | Click Accept | Redirected to Data Room folder — folder contents now visible with documents list and folder tree | | |
| ☐ | J1.7 | NDA acceptance screen | Click "Back to Data Rooms" (without accepting) | Redirected to Data Rooms listing page. No acceptance record created. | | |

### Journey 2: LP declines NDA

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | NDA acceptance screen | Click Decline | Decline confirmation page shown | | |
| ☐ | J2.2 | Decline page | Observe layout | Same minimal layout. No sidebar/navigation. | | |
| ☐ | J2.3 | Decline page | Observe content | "NDA Declined" heading. Message: "You have declined the Non-Disclosure Agreement for the folder 'Data Room'." and "You cannot access this folder's contents without accepting the NDA." | | |
| ☐ | J2.4 | Decline page | Observe contact info | "Questions? Contact: legal@alpha.com" shown (because NDA-A has contact_email) | | |
| ☐ | J2.5 | Decline page | Click "Try Again" | Returns to NDA acceptance screen | | |
| ☐ | J2.6 | Decline page | Click "Back to Data Rooms" | Redirected to Data Rooms listing page | | |

---

## Role Sweep

| ID | Screen / action | GP Admin (same entity) | LP with InvestorAccess | Investor Advisor (different entity) | Other-entity GP | User without InvestorAccess |
|---|---|---|---|---|---|---|
| R1 | Navigate to NDA-protected folder | ✓ Folder contents shown (no NDA gate) | ✓ NDA acceptance screen shown (unless stakeholder already accepted) | ✓ NDA acceptance screen shown (if has InvestorAccess) | ✗ No access (no access right to folder) | ✗ Denied by policy |
| R2 | NDA acceptance screen | ✗ Should never see this screen | ✓ Can view and interact | ✓ Can view and interact | ✗ Should not reach | ✗ Denied |
| R3 | Accept NDA | N/A | ✓ Acceptance recorded with investor_id, redirected to folder. All users of same stakeholder unlocked. | ✓ Acceptance recorded, redirected to folder | ✗ Denied | ✗ Denied |
| R4 | Decline NDA | N/A | ✓ Decline recorded, decline page shown. Does NOT block other users of same stakeholder. | ✓ Decline recorded, decline page shown | ✗ Denied | ✗ Denied |
| R5 | Direct URL to /nda_acceptances?nda_config_id=X | ✗ Denied by policy (GP should not access) | ✓ Allowed if has InvestorAccess | ✓ Allowed if has InvestorAccess | ✗ Denied by policy | ✗ Denied by policy |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | N/A — Module 2 sends no emails. Notifications are Module 8. | | |
| ☐ | C2 | Dates on changed screens | N/A — no dates displayed on acceptance/decline screens | | |
| ☐ | C3 | Narrow / mobile width | NDA acceptance and decline pages display correctly on mobile. No horizontal scroll. Buttons reachable. PDF iframe scales or scrolls. | | |
| ☐ | C4 | Tenant isolation | 1. Log in as Other-entity GP 2. Try direct URL to /nda_acceptances?nda_config_id=X (Alpha Ventures' NDA) → Denied. 3. Log in as LP without InvestorAccess to Alpha Ventures → Cannot see NDA screens. | | |
| ☐ | C5 | Regression on modified screens | 1. GP navigates to Documents page for a non-NDA folder → works as before 2. GP navigates to NDA-protected folder → works as before (GP bypasses gate) 3. LP navigates to non-NDA folder → works as before 4. Data Rooms listing page unchanged | | |
| ☐ | C8 | Stakeholder-level acceptance | 1. LP User A accepts NDA-A. 2. Check DB: nda_acceptances.investor_id = Acme Capital's id. 3. LP User B (same Acme Capital) navigates to Data Room → bypasses NDA. 4. LP User C (different Beta Holdings) navigates to Data Room → sees NDA screen. | | |
| ☐ | C6 | Empty states | N/A — no list pages or panels with variable data in this feature | | |
| ☐ | C7 | NDA PDF renders in iframe | PDF from Shrine S3/filesystem displays correctly in the acceptance screen iframe. Scrollable. No broken link or CORS error. | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
