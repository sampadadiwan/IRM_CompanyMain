# Fix NDA Signatory Auto-Tag — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X).

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (acefund.altconnects.com) or localhost:3001 |
| GP account | `fm1@ian.com` / `password` — entity Ace Fund |
| LP account 1 | An existing investor user with folder access (for existing signatory check) |
| LP account 2 | A new investor user to be added during testing (for auto-tag verification) |
| Second entity | Any user from a different entity (for tenant isolation check) |
| Seed data | 1. A Data Room folder with NDA configured and enabled. 2. At least one investor with folder access and existing signatory. 3. A second investor to add during testing. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | New investor access (created as approved) auto-tagged as signatory | Folder has enabled NDA, new investor has AccessRight on folder | 1. Log in as GP. 2. Go to Stakeholders. 3. Add a new investor access for the investor (approved). 4. Check NDA Status Dashboard for that folder. | New investor appears on NDA Status Dashboard with a signatory tagged | | |
| ☐ | H2 | Unapproved access toggled to approved triggers auto-tag | Folder has enabled NDA, investor has unapproved access | 1. Log in as GP. 2. Go to Stakeholders. 3. Find the unapproved investor access. 4. Click approve toggle. 5. Check NDA Status Dashboard. | Investor appears with signatory tagged after approval | | |
| ☐ | H3 | NDA creation only tags folder-access investors | Folder has AccessRights for Investor A but not Investor B | 1. Log in as GP. 2. Navigate to a Data Room folder with mixed access. 3. Set up a new NDA on the folder. 4. Check NDA Status Dashboard. | Only Investor A appears with signatory; Investor B is not listed | | |
| ☐ | H4 | Auto-tagged LP can accept NDA | Folder has NDA, LP user was auto-tagged as signatory | 1. Log in as the auto-tagged LP user. 2. Navigate to the NDA-protected folder. | LP sees NDA acceptance form (not blocked page) | | |
| ☐ | H5 | AccessRight grant triggers auto-tag (investor already has approved access) | Folder has enabled NDA, investor has approved InvestorAccess but no folder AccessRight | 1. Log in as GP. 2. Navigate to folder's Access Rights. 3. Grant folder AccessRight to the investor. 4. Check NDA Status Dashboard. | Investor appears with signatory tagged | | |
| ☐ | H6 | Category AccessRight grant triggers auto-tag for multiple investors | Folder has enabled NDA, multiple LP investors have approved InvestorAccess | 1. Log in as GP. 2. Grant category AccessRight "LP" on the NDA folder. 3. Check NDA Status Dashboard. | All matching LP investors appear with signatory tagged | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No auto-tag when folder has no NDA | Investor has folder access, but folder has no NDA configured | 1. Add investor access (approved) for investor on a non-NDA folder. 2. Check that no NdaSignatory is created (via NDA Status or console). | No signatory created, no errors | | |
| ☐ | E2 | No duplicate signatory when investor already has one | Investor already has a signatory for the folder's NDA | 1. Add a second investor access (approved) for the same investor. 2. Check NDA Status Dashboard. | Original signatory preserved, no duplicate row created | | |
| ☐ | E3 | Entity-level investor without folder access not tagged on NDA creation | Investor has entity access but no AccessRight on the specific folder | 1. Create an NDA on a folder. 2. Check NDA Status Dashboard. | Entity-only investor does not appear on dashboard | | |
| ☐ | E4 | AccessRight grant does not auto-tag when investor has no approved access | Folder has NDA, investor has only unapproved InvestorAccess | 1. Grant folder AccessRight for the investor. 2. Check NDA Status Dashboard. | No signatory created for that investor | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Race condition handled gracefully | Two browser tabs open for same GP | 1. Open two tabs, both on the approve button for the same investor access. 2. Click approve in both tabs quickly. | One signatory created, no error shown in either tab | | |

---

## Role Sweep

| ID | Screen / action | GP (fund manager) | LP (investor user) | Other-entity GP |
|---|---|---|---|---|
| R1 | NDA Status Dashboard — view signatories | ✓ sees auto-tagged signatories | ✗ cannot access dashboard | ✗ cannot access other entity's dashboard |
| R2 | Folder access after auto-tag | N/A | ✓ sees acceptance form (if signatory) or blocked page (if not) | ✗ cannot access folder |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A — auto-tag does not send notifications | | |
| ☐ | C2 | Dates on changed screens | N/A — no date display changes | | |
| ☐ | C3 | Narrow / mobile width | N/A — no UI changes | | |
| ☐ | C4 | Tenant isolation | A GP from entity B cannot see entity A's NDA Status Dashboard or trigger auto-tag on entity A's investors | | |
| ☐ | C5 | Regression: existing NDA acceptance flow | Existing signatories can still accept/decline NDA; blocked page still shows for non-signatories | | |
| ☐ | C6 | Regression: NDA Status Dashboard | Dashboard counters (accepted, pending, declined) still correct after auto-tag | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
