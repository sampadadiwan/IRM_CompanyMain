# NDA Settings Enhancements — Manual QA Checklist

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
| Environment | Staging or local dev (port 3001) |
| GP Account | Log in as a GP admin user (e.g., `fm1@ian.com` / `password` on local) |
| LP Account | An LP user with approved InvestorAccess to the GP entity |
| Second entity | A GP user from a different entity (for tenant isolation check) |
| Seed data — Parent folder | A Data Room folder with NDA enabled (any validity type) |
| Seed data — Child folder | A child folder inside the parent Data Room, in "inherit" mode |
| Seed data — LP acceptance | The LP investor must have accepted the inherited NDA on the child folder |
| Seed data — Expired NDA | An NDA with "Specific Date" validity set to a past date (use Rails console: `nda.update_columns(validity_type: "specific_date", validity_date: Date.yesterday)`) |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Override with resign unchecked carries forward acceptances | Child folder inherits parent NDA, LP accepted inherited NDA | 1. Open child folder NDA settings 2. Click "Set Own NDA" 3. Leave resign checkbox unchecked 4. Upload NDA PDF 5. Click Save Settings | Success flash. Open child's NDA Status → LP shows as "Accepted" | | |
| ☐ | H2 | Override with resign checked starts fresh | Same as H1 | 1. Open child folder NDA settings 2. Click "Set Own NDA" 3. Check "Require them to re-sign the new NDA" 4. Upload PDF 5. Save | Success flash. Open child's NDA Status → LP shows as "Pending" | | |
| ☐ | H3 | Locked validity with expiry summary | NDA with Fixed Period 90 days, at least 1 LP accepted | 1. Open NDA settings (edit) 2. Look at Validity section | Validity type radios are grayed out/disabled. Lock icon message: "Validity type is locked because investors have already accepted." Below period dropdown: "Earliest expiry: [date] · Latest expiry: [date]" | | |
| ☐ | H4 | Save expired NDA with new date | NDA with Specific Date validity, date in the past | 1. Open NDA settings (edit) 2. Pick a future date in the date picker 3. Click Save | Form submits successfully. Success flash shown. NDA updated with new date. | | |
| ☐ | H5 | Actions dropdown on single-row table | NDA Status with exactly 1 investor | 1. Open NDA Status page 2. Click the three-dot (kebab) button on the investor row | Dropdown menu renders fully visible, not clipped by table boundary | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No resign checkbox when no inherited acceptances | Child folder inherits parent NDA, no LP has accepted | 1. Open child folder NDA settings 2. Click "Set Own NDA" | Form shows without resign checkbox section. No "X investors have already signed" banner. | | |
| ☐ | E2 | Parent acceptances untouched after override | LP accepted parent NDA, then GP overrides child with resign unchecked | 1. Complete H1 2. Navigate to parent folder's NDA Status | LP still shows as "Accepted" on the parent folder's NDA Status (original acceptance preserved) | | |
| ☐ | E3 | Validity not locked when no acceptances | NDA exists but no LP has accepted | 1. Open NDA settings (edit) | Validity type radios are enabled (clickable). No lock icon or message. | | |
| ☐ | E4 | No expiry summary for Until Revoked | NDA with "Until Revoked" validity, LP accepted | 1. Open NDA settings (edit) | No expiry dates shown below validity options | | |
| ☐ | E5 | Save expired NDA changing only email | NDA with expired Specific Date | 1. Open NDA settings (edit) 2. Change only the Contact Email field 3. Click Save | Form submits successfully. Email updated. Expired date unchanged. | | |
| ☐ | E6 | Fixed period dropdown only shows >= current | NDA with Fixed Period 90 days, LP accepted | 1. Open NDA settings (edit) 2. Click the period dropdown | Dropdown shows: 90 days, 6 months, 12 months. Does NOT show 30 days. | | |
| ☐ | E7 | Specific date can only extend forward | NDA with Specific Date (future), LP accepted | 1. Open NDA settings (edit) 2. Try to pick a date before the current validity date | Date picker does not allow selecting earlier dates (min attribute enforced) | | |
| ☐ | E8 | Specific date expiry summary | NDA with Specific Date Dec 31, 2027 | 1. Open NDA settings (edit) | Below the date field: "All NDAs expire on: Dec 31, 2027" | | |
| ☐ | E9 | Multiple investor rows still show dropdown | NDA Status with 3+ investors | 1. Click kebab on any investor row | Dropdown renders fully visible (no regression from single-row fix) | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Duplicate override attempt | GP already overrode child folder's NDA | 1. Try to open "Set Own NDA" again on same child folder | Should not show "Set Own NDA" — folder already has own NDA, shows edit form instead | | |

---

## UI Journeys

### Journey 1 — Override inherited NDA

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Documents page › child folder | Click NDA settings icon/link | NDA settings modal opens showing inherited info panel | | |
| ☐ | J1.2 | NDA modal › inherited info panel | Read the panel | Shows parent folder name. "Set Own NDA" button visible | | |
| ☐ | J1.3 | NDA modal › after clicking "Set Own NDA" | Check form content | Override context banner: "Overriding inherited NDA. The parent folder X has an active NDA." Resign section: "[N] investors have already signed the inherited NDA for this folder." Checkbox unchecked by default. | | |
| ☐ | J1.4 | NDA modal › Save | Upload PDF, click Save | Modal closes. Lock icon appears on folder in tree. Flash: "NDA settings saved successfully." | | |

### Journey 2 — Edit NDA with locked validity

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Documents page › folder with NDA | Click NDA settings | Edit modal opens | | |
| ☐ | J2.2 | NDA modal › Validity section | Look at radio buttons | Radios grayed out. Lock icon + explanation text above them. | | |
| ☐ | J2.3 | NDA modal › below validity options | Read expiry info | For Fixed Period: "Earliest expiry: [date] · Latest expiry: [date]". For Specific Date: "All NDAs expire on: [date]" | | |
| ☐ | J2.4 | NDA modal › period dropdown (if Fixed Period) | Open dropdown | Only shows options >= current period | | |
| ☐ | J2.5 | NDA modal › Save | Change a non-locked field (e.g., email), click Save | Saves successfully. Validity type unchanged. | | |

---

## Role Sweep

| ID | Screen / action | GP Admin (same entity) | LP User | GP Admin (different entity) |
|---|---|---|---|---|
| R1 | Open NDA settings modal | ✓ Sees form | ✗ No access to settings | ✗ 403 or redirected |
| R2 | Click "Set Own NDA" | ✓ Form with resign option | ✗ Not visible | ✗ Not accessible |
| R3 | Save NDA settings | ✓ Saves successfully | ✗ Cannot submit | ✗ Cannot submit |
| R4 | View NDA Status page | ✓ Sees investor table | ✗ Not accessible | ✗ Not accessible |
| R5 | Click Actions kebab | ✓ Dropdown visible | ✗ N/A | ✗ N/A |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on NDA settings form | Expiry dates formatted as "Mon DD, YYYY" (e.g., "Jan 15, 2027") | | |
| ☐ | C2 | Narrow / mobile width | NDA settings modal is usable on narrow screens. Resign checkbox section does not overflow. Validity section readable. | | |
| ☐ | C3 | Tenant isolation | A GP user from a different entity cannot open NDA settings for this folder (even with direct URL) | | |
| ☐ | C4 | Regression — NDA settings | Edit an NDA without any of the new features triggering (e.g., Until Revoked, no acceptances). Confirm Save still works as before. | | |
| ☐ | C5 | Regression — NDA Status | Open NDA Status with multiple investors. Confirm all existing functionality (filters, search, export, exemption, revoke) still works. | | |
| ☐ | C6 | Regression — NDA gate | LP tries to access a folder with active NDA. Confirm the NDA acceptance gate still blocks correctly and allows access after signing. | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
