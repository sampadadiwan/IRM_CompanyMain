# KYC Onboarding Agent Improvements — Manual QA Checklist

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
| Environment | Staging |
| Admin account | Fund manager with agent access on an Indian entity (has "PAN" label) |
| Admin account (US) | Fund manager with agent access on a US entity (has "Tax ID" label) |
| Second entity | A user in a different entity, for isolation checks |
| Entity AML setting | Indian entity: AML NOT enabled; US entity: AML enabled |
| KYC Onboarding Agent | Created for both entities with `validate_documents: true`, `trigger_aml: true` |
| Completed KYC records | At least 2 completed KYC records per entity, each with PAN/Tax ID, Bank Details, and Address Proof documents uploaded |
| Background work | Agent runs can be triggered manually via the "Play" button on the dashboard, or "Run Agent on All Pending" for bulk |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Setup table renders with dropdowns | KYC Onboarding Agent exists for entity with File-type and non-File FormCustomFields | 1. Go to Agents page 2. Click Edit on KYC Onboarding Agent 3. Scroll to "Document Verification Setup" section | Section visible with a 3-column table. Document dropdown shows File-type fields (Upload PAN, Upload Bank Details, etc.). Field to Verify dropdown shows non-File fields (PAN, bank_name, etc.). | | |
| ☐ | H2 | Admin configures and saves mappings | Setup table visible | 1. Select "Upload PAN" from Document dropdown 2. Type "PAN / Tax ID number" in Information to pull 3. Select "PAN" from Field to Verify 4. Click Save 5. Reload page | Config saved. On reload, the row shows "Upload PAN" / "PAN / Tax ID number" / "PAN". | | |
| ☐ | H3 | New format used in consistency check | Agent configured via setup table (H2 done) | 1. Go to KYC Dashboard tab 2. Click Play on a completed KYC row 3. Wait for agent to finish 4. Click Eye to view report | Field-Doc Consistency section shows items based on the configured mappings (e.g., "PAN" matched/mismatched). | | |
| ☐ | H4 | Document Validity validates PAN only | KYC has Upload PAN, Upload Bank Details, Upload Address Proof documents | 1. Run agent on the KYC 2. View the report detail panel 3. Check Document Validity items | Only PAN/Tax ID document has a validity result (e.g., "Valid Upload PAN"). Bank Details and Address Proof have NO validity items. | | |
| ☐ | H5 | Document Presence checks required docs | All required documents uploaded | 1. Run agent on KYC with all docs present 2. View report | "All required documents are present" in the report. | | |
| ☐ | H6 | AML skipped when entity AML not enabled | Indian entity with AML NOT enabled, trigger_aml toggle ON, no blocking issues | 1. Run agent on a KYC with no issues 2. View report 3. Check Trigger AML step | Step shows "AML not enabled for entity" and is marked as skipped. No AML report generated. | | |
| ☐ | H7 | Agent description updated | Any KYC Onboarding Agent | 1. View agent description on the agents list or agent detail page | Description says "Tax ID, Address Proof, Bank Details". Does NOT mention "passport". | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Empty row discarded on save | Setup table visible | 1. Click "+ Add Row" 2. Leave Document dropdown blank 3. Click Save 4. Reload | The empty row is gone. Other configured rows remain. | | |
| ☐ | E2 | Same document multiple rows | Setup table visible | 1. Add 3 rows, all selecting "Upload Bank Details" 2. Enter different extraction prompts and target fields for each 3. Save 4. Reload | All 3 rows saved and visible with correct values. | | |
| ☐ | E3 | No File-type fields on entity | Entity with no File-type FormCustomFields (or no KYC form types) | 1. Open agent Edit page 2. Look at Document Verification Setup | Document dropdown is empty. If no form types: "No KYC form types found for this entity". | | |
| ☐ | E4 | Old text format still works | Agent configured with old attribute=prompt format (not via new setup table) | 1. Run agent on a completed KYC 2. View report | Field-Doc Consistency check runs and shows results based on old-format mappings. | | |
| ☐ | E5 | Re-save migrates to new format | Agent with old format config | 1. Open agent Edit page 2. Click Save (no changes) 3. Run agent 4. View report | Agent runs correctly using new format. Consistency check results same as before. | | |
| ☐ | E6 | Document named differently still matched | KYC has a document named "PAN Card" (not "Upload PAN") | 1. Run agent 2. View Document Validity items | "PAN Card" is sent to AI for validation (result shown). Non-PAN docs still skipped. | | |
| ☐ | E7 | validate_documents toggle OFF | Agent with validate_documents: false | 1. Run agent 2. View report | Steps 3, 4, 5 all show as "Disabled" / skipped. No document checks run. | | |
| ☐ | E8 | AML enabled for entity, toggle ON | US entity with AML enabled, no blocking issues | 1. Run agent on a KYC with no issues 2. View report | AML step shows "AML triggered". AML report generated. | | |
| ☐ | E9 | Entity has no entity settings record | Entity without an entity_setting record (edge case) | 1. Run agent with trigger_aml ON 2. View report | AML step shows "AML not enabled for entity" and is skipped. No error. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | PAN document AI call fails | PAN document uploaded but AI returns error / unparseable response | 1. Upload a corrupt or unusual PAN document 2. Run agent 3. View report | Document validity shows "Could not ascertain Upload PAN" with warning severity. Agent continues to next steps. | | |

---

## UI Journeys

### J1 — Configure document verification setup

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Navigate to setup | 1. Go to Agents page 2. Click KYC Onboarding Agent 3. Click Edit | Agent settings form loads with Document Verification Setup section visible | | |
| ☐ | J1.2 | Add first mapping row | 1. In setup table, select "Upload PAN" from Document dropdown 2. Type "PAN / Tax ID number" in Information to pull 3. Select "PAN" from Field to Verify | Row populated with selections. No page reload. | | |
| ☐ | J1.3 | Add second row | 1. Click "+ Add Row" 2. Select "Upload Bank Details" / "bank name" / "bank_name" | Second row added below the first. | | |
| ☐ | J1.4 | Remove a row | 1. Click ✕ on the second row | Row removed. First row still visible. | | |
| ☐ | J1.5 | Save configuration | 1. Click Save | Flash: "Agent updated successfully" or similar. Page reloads with configured rows intact. | | |

### J2 — Run agent and view results

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J2.1 | Trigger single run | 1. Go to KYC Dashboard tab 2. Click Play button on a completed KYC row | Step-circle progress appears. Agent runs. | | |
| ☐ | J2.2 | View report with PAN-only validity | 1. After run completes, click Eye button | Detail panel shows: Document Validity items only for PAN/Tax ID. No items for Bank Details or Address Proof. | | |
| ☐ | J2.3 | View AML step result (AML not enabled) | 1. In detail panel, check Trigger AML step | Shows "AML not enabled for entity" or "Disabled" depending on toggle. | | |

---

## Role Sweep

| ☐ | ID | Role | What to check | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Admin / Fund Manager | Can see and edit Document Verification Setup | Section visible on edit page; can add/remove rows and save | | |
| ☐ | R2 | Read-only user | Cannot edit agent settings | Edit page not accessible or form is read-only (existing behavior) | | |
| ☐ | R3 | User from different entity | Cannot see this entity's agent or config | Agent not visible in their agents list (existing behavior) | | |

---

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Tenant isolation | 1. Log in as user from a different entity 2. Try to access the agent edit page URL directly | Access denied or 404. Cannot see another entity's agent config. | | |
| ☐ | C2 | Label adapts per entity (India vs US) | 1. Check Document dropdown on Indian entity → should show "Upload PAN" 2. Check on US entity → should show "Upload Tax ID" | Labels match the entity's actual FormCustomField labels. | | |
| ☐ | C3 | No regression on existing toggles | 1. Toggle validate_fields, validate_documents, check_expiry, send_reminder, trigger_aml on/off 2. Save and reload | Toggles persist correctly. Agent respects them during run. | | |
| ☐ | C4 | Dashboard still works | 1. Run agent on several KYCs 2. Check dashboard: stat cards, charts, table, detail panel | Dashboard shows correct data. No errors. Stat card counts match. | | |
| ☐ | C5 | Existing KYC pages unaffected | 1. Navigate to normal KYC index and detail pages | No changes to KYC form pages. Links from dashboard stat cards still work. | | |

---

## Sign-off

| Tester | Build / Commit | Environment | Date | Result | Open Defects |
|---|---|---|---|---|---|
| | | | | | |
