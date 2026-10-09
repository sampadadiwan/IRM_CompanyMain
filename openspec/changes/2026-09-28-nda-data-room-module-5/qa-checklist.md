# NDA Inheritance — Manual QA Checklist

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
| Environment | Staging or dev server (`localhost:3001`) |
| GP account | `fm1@ian.com` / `password` — entity: Alpha Capital (must have `enable_data_rooms: true`) |
| LP account | An investor user with access rights to Data Room folders |
| Second entity | A GP user from a different entity (for tenant isolation checks) |
| Seed data | 1. Data Room folder with NDA-A configured (Module 1) 2. Child folder "Deal Pipeline" (no own NDA) 3. Child folder "Fund Financials" with its own NDA-B 4. Child folder "Marketing" (will be used for opt-out) 5. Grandchild "TechCo Acquisition" under Deal Pipeline 6. Grandchild "Q3 Report" under Fund Financials |
| Prerequisite | Module 1 (NDA Configuration) must be deployed and working. At least one folder must have NDA configured via the NDA Settings modal. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Direct child inherits parent NDA | Data Room has NDA-A; Deal Pipeline has no own NDA | 1. Log in as LP 2. Navigate to Documents 3. Click on Deal Pipeline | NDA acceptance screen for NDA-A is shown (not folder contents) | | |
| ☐ | H2 | Grandchild inherits grandparent NDA | Data Room has NDA-A; Deal Pipeline inherits; TechCo has no own NDA | 1. Log in as LP 2. Navigate to TechCo Acquisition | NDA acceptance screen for NDA-A is shown | | |
| ☐ | H3 | Accepting on parent covers inheriting child | Data Room has NDA-A; Deal Pipeline inherits | 1. Log in as LP 2. Accept NDA-A on Data Room 3. Navigate to Deal Pipeline | Folder contents shown directly (no NDA screen — already accepted) | | |
| ☐ | H4 | Accepting on child covers parent (same config) | Data Room has NDA-A; Deal Pipeline inherits | 1. Log in as LP (fresh, not accepted) 2. Accept NDA-A via Deal Pipeline screen 3. Navigate to Data Room | Folder contents shown directly (NDA-A already accepted) | | |
| ☐ | H5 | GP views inherited Settings tab | Deal Pipeline inherits NDA-A from Data Room | 1. Log in as GP 2. Navigate to Documents → Deal Pipeline 3. Click Actions → NDA Settings | Modal shows: "This folder inherits NDA from: Data Room", read-only NDA details, three radio options with "Use parent's NDA" selected | | |
| ☐ | H6 | GP overrides with different NDA | Deal Pipeline inherits NDA-A | 1. Open NDA Settings on Deal Pipeline 2. Select "Set different NDA for this folder" 3. Upload a different PDF, set validity, save | New NDA config created, solid lock icon shown on Deal Pipeline (no "(Inherited)" label) | | |
| ☐ | H7 | GP opts out a folder | Deal Pipeline inherits NDA-A | 1. Open NDA Settings on Deal Pipeline 2. Select "No NDA required" 3. Click Save | Confirmation prompt: "LPs will be able to access this folder without accepting an NDA. Are you sure?" After confirming: no lock icon on Deal Pipeline | | |
| ☐ | H8 | New folder auto-inherits | Data Room has NDA-A | 1. Create a new folder "New Deal" inside Data Room | Lock + "(Inherited)" shown on "New Deal" in folder tree | | |
| ☐ | H9 | GP reverts from own to parent | Fund Financials has NDA-B; Data Room has NDA-A | 1. Open NDA Settings on Fund Financials 2. Click "Remove this NDA and use parent's" 3. Confirm | Folder tree changes from solid lock to lock + "(Inherited)". NDA-A now applies. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Grandchild inherits child's override, not grandparent's | Data Room has NDA-A; Fund Financials has NDA-B | 1. Log in as LP 2. Navigate to Q3 Report (child of Fund Financials) | NDA-B acceptance screen shown (not NDA-A) | | |
| ☐ | E2 | Child of opted-out folder has no NDA | Data Room has NDA-A; Marketing is opted out | 1. Create "Press Releases" inside Marketing 2. Log in as LP 3. Navigate to Press Releases | Folder contents shown directly (no NDA screen) | | |
| ☐ | E3 | Child of opted-out folder can have own NDA | Marketing opted out; "Sensitive Materials" child has own NDA-C | 1. Log in as LP 2. Navigate to Sensitive Materials | NDA-C acceptance screen shown | | |
| ☐ | E4 | No NDA in ancestry | No NDA configs anywhere in tree | 1. Log in as LP 2. Navigate to any folder | Folder contents shown directly | | |
| ☐ | E5 | New folder inside opted-out parent | Marketing opted out | 1. Create "Campaign" inside Marketing 2. Check folder tree | No lock icon on Campaign | | |
| ☐ | E6 | Different configs require separate acceptance | LP accepted NDA-A | 1. Navigate to Fund Financials (has NDA-B) | NDA-B acceptance screen shown (different config) | | |
| ☐ | E7 | Removing parent NDA uncascades | Data Room has NDA-A; Deal Pipeline inherits; Fund Fin. has own NDA-B; Marketing opted out | 1. Open NDA Settings on Data Room 2. Toggle "Require NDA" to No 3. Save | Deal Pipeline: no lock icon. Fund Financials: solid lock remains. Marketing: unchanged (no icon). | | |
| ☐ | E8 | Own folder with parent — shows revert option | Fund Financials has NDA-B; Data Room has NDA-A | 1. Open NDA Settings on Fund Financials | Standard NDA config form shown + "Remove this NDA and use parent's" option below | | |
| ☐ | E9 | Opted-out folder Settings tab | Marketing opted out; Data Room has NDA-A | 1. Open NDA Settings on Marketing | Opted-out variant: parent NDA info + "No NDA required" selected | | |
| ☐ | E10 | Existing acceptances preserved on revert | Users accepted NDA-B on Fund Financials | 1. GP reverts Fund Financials to parent NDA-A 2. LP visits Fund Financials | LP sees NDA-A acceptance screen (NDA-B acceptance is historical, not lost) | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | LP cannot access NDA Settings | LP user logged in | 1. Navigate directly to NDA Settings URL for a folder | Access denied — redirect with "Not authorized" | | |
| ☐ | X2 | GP without folder rights cannot change mode | GP without folder management rights | 1. Navigate to NDA Settings for a folder they cannot manage | Access denied — redirect with "Not authorized" | | |

---

## UI Journeys

### Journey 1: GP views inherited folder NDA settings

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Documents page — folder tree | Click on Deal Pipeline (inherited) | Deal Pipeline selected; lock + "(Inherited)" visible | | |
| ☐ | J1.2 | Documents page — Actions dropdown | Click "NDA Settings" | Modal opens on same page (no navigation) | | |
| ☐ | J1.3 | NDA Settings modal | Read header | "This folder inherits NDA from: Data Room" | | |
| ☐ | J1.4 | NDA Settings modal | Review NDA details | Read-only: document name, validity type, acceptance method | | |
| ☐ | J1.5 | NDA Settings modal | Check radio options | Three options shown; "Use parent's NDA" is pre-selected | | |

### Journey 2: GP overrides or opts out

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | NDA Settings modal (inherited) | Select "Set different NDA for this folder" | Full NDA config form expands below the radios | | |
| ☐ | J2.2 | NDA Settings modal (override form) | Upload PDF, set validity, click Save | Modal closes; folder tree shows solid lock (own NDA) | | |
| ☐ | J2.3 | NDA Settings modal (inherited) | Select "No NDA required for this folder" then Save | Confirmation prompt appears | | |
| ☐ | J2.4 | Confirmation prompt | Click "OK" / confirm | Modal closes; folder tree shows no lock icon | | |

### Journey 3: GP reverts from own NDA to parent

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J3.1 | NDA Settings modal (own NDA, parent has NDA) | Scroll to bottom of form | "Parent folder 'Data Room' also has an NDA configured." with "Remove this NDA and use parent's" link | | |
| ☐ | J3.2 | NDA Settings modal | Click "Remove this NDA and use parent's" | Confirmation prompt | | |
| ☐ | J3.3 | After confirm | Check folder tree | Lock changes from solid to lock + "(Inherited)" | | |

---

## Role Sweep

| ID | Screen / action | GP/Admin (with folder rights) | GP/Admin (without folder rights) | LP / Investor | Other-entity GP |
|---|---|---|---|---|---|
| R1 | See NDA Settings in Actions dropdown (Data Room folder) | ✓ visible | ✓ visible | ✗ not shown | ✗ not shown |
| R2 | Open NDA Settings modal | ✓ modal opens | ✗ access denied | ✗ access denied | ✗ access denied |
| R3 | See lock icons and "(Inherited)" in folder tree | ✓ visible | ✓ visible | ✗ no icons shown | ✗ different entity |
| R4 | Change inheritance mode (override/opt-out/revert) | ✓ allowed | ✗ denied by policy | ✗ denied by policy | ✗ denied by policy |
| R5 | See inherited lock tooltip ("Inherits NDA from: ...") | ✓ tooltip shown | ✓ tooltip shown | ✗ no icons at all | ✗ different entity |

---

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Turbo Stream updates — no page reload | 1. Save inheritance change 2. Watch browser network tab | No full page reload; folder tree icons update inline via Turbo Stream | | |
| ☐ | C2 | Descendant carets update on parent change | 1. Opt out a parent with 3+ inheriting children 2. Check all children's icons | All inheriting children's lock icons disappear without page reload | | |
| ☐ | C3 | Mobile/narrow width | 1. Resize browser to mobile width 2. Open NDA Settings modal | Modal is usable; radio buttons and form fit the screen | | |
| ☐ | C4 | Tenant isolation | 1. Log in as GP from Entity B 2. Try to access NDA Settings URL for Entity A's folder | Access denied — cannot see or modify Entity A's NDA | | |
| ☐ | C5 | Inherited lock tooltip text | 1. Hover over inherited lock icon | Tooltip: "Inherits NDA from: [Source Folder Name]" — correct ancestor name | | |
| ☐ | C6 | Module 1 regression — own NDA still works | 1. Create NDA on a folder (Module 1 flow) 2. Verify lock icon, edit, disable | All Module 1 functionality unchanged | | |
| ☐ | C7 | Folder tree expand/collapse preserved after Turbo Stream | 1. Expand folder tree 2. Save inheritance change 3. Check tree state | Expanded/collapsed state preserved after Turbo Stream caret replacements | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| — | — | — | — | — | — |
