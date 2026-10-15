# Block Capital Calls Without Commitments — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J1.3 = journey 1, step 3) · **R** = Role sweep · **C** = Cross-cutting check

**The message** checked throughout (call it "the message" below):

> No commitments in this fund apply to this call. Add commitments for the selected fund closes before creating a capital call.

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
| Accounts | A company admin of entity "Urban" who can create capital calls; an employee of "Urban" without capital call create permission |
| Second entity | A company admin of a different entity, for the isolation check |
| Seed data | **SAAS Fund** (Urban): two investors, each with a commitment in **First Close** only, and a capital call notice template. **Empty Fund** (Urban): no commitments. |
| Import file | `capital_calls_no_commitments.xlsx` from the build's sample uploads (row 1: SAAS Fund, Fund Closes "All"; row 2: SAAS Fund, Fund Closes "Second Close") |
| Background work | Remittances are created in the background after a call is saved. Refresh the call page after a few seconds. Imports run in the background; refresh the import page until it shows Completed. |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | A call for all closes on a fund with commitments still works | SAAS Fund | 1. Open SAAS Fund → Calls. 2. Click New Call → Classic Form. 3. Name "QA H1", Applicable To "All", 10% for First Close, today's dates. 4. Save. | "Capital call was successfully created." After a refresh, 2 remittances are listed. | | |
| ☐ | H2 | An Upload call on a fund with commitments still works | SAAS Fund | 1. New Call → Classic Form. 2. Name "QA H2", Call Basis "Upload". 3. Save. | "Capital call was successfully created." | | |
| ☐ | H3 | A call naming a close with commitments and one without is allowed | SAAS Fund | 1. New Call → Classic Form. 2. Name "QA H3", Applicable To "First Close" and "Second Close". 3. Save. | Call created. Remittances only for the two First Close investors. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Editing an existing call is not blocked | Call "QA H1" exists | 1. Open "QA H1" → Edit. 2. Change Applicable To to "Second Close" only. 3. Save. | Saved as before; the message does **not** appear. | | |
| ☐ | E2 | A call for a close with no commitments is refused | SAAS Fund | 1. New Call → Classic Form. 2. Name "QA E2", Applicable To "Second Close" only. 3. Save. | Form shown again with the message. No "QA E2" on the Calls tab. | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | A call on a fund with no commitments is refused and the form keeps the input | Empty Fund | 1. Open Empty Fund → Calls → New Call → Classic Form. 2. Name "QA X1", fill the dates. 3. Save. | Form shown again; name "QA X1" still filled in; error box shows the message. No call on the Calls tab. No one is alerted. | | |
| ☐ | X2 | An Upload call on a fund with no commitments is refused | Empty Fund | 1. New Call → Classic Form. 2. Name "QA X2", Call Basis "Upload". 3. Save. | Form shown again with the message. No call created. | | |
| ☐ | X3 | Nothing is left behind after a refusal | After X1 and X2 | 1. Open Empty Fund → Calls. | No calls listed; the fund's call totals are unchanged. | | |
| ☐ | X4 | The API refuses the call | Empty Fund; ask a developer or use an API client | 1. Send a JSON create request for a call on Empty Fund. | Response status 422; the body contains the message. | | |
| ☐ | X5 | An import fails only the bad row | SAAS Fund | 1. SAAS Fund → Calls → Upload. 2. Choose `capital_calls_no_commitments.xlsx`, Save. 3. Refresh until Completed. 4. Download the import result. | 1 row succeeded, 1 failed. The failed row (Second Close) shows the message. The All-closes call is on the Calls tab. | | |

---

## UI Journeys

Journey 1: fixing a refused call on the New Call form (design [What users see](design.md#what-users-see)).

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | SAAS Fund → Calls | Click New Call → Classic Form | The New Call button looks and works as before (not disabled, no tooltip) | | |
| ☐ | J1.2 | New Capital Call form | Name "QA J1", Applicable To "Second Close", Save | Error box at the top with "1 error prohibited this capital call from being saved:" and the message | | |
| ☐ | J1.3 | Same form | Look at the fields | Every value entered is still there | | |
| ☐ | J1.4 | Same form | Change Applicable To to "First Close", enter 10%, Save | "Capital call was successfully created."; the call page opens | | |

---

## Role Sweep

✓ = allowed and works · ✗ = correctly blocked · ! = wrong

| ID | Screen / action | Company admin (Urban) | Employee without call create permission | Other-entity admin |
|---|---|---|---|---|
| R1 | Create a call on SAAS Fund | ✓ created | ✗ blocked as before (no access) | ✗ cannot reach the fund |
| R2 | Create a call on Empty Fund | ✓ refused with the message | ✗ blocked as before (no access) | ✗ cannot reach the fund |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | N/A — the feature sends no emails or alerts | | |
| ☐ | C2 | Dates on changed screens | N/A — no dates added or changed | | |
| ☐ | C3 | Narrow / mobile width | On a phone-width window, the error box on the New Call form wraps without horizontal scroll | | |
| ☐ | C4 | Tenant isolation | The other-entity admin cannot open either fund's New Call form, even with a direct URL | | |
| ☐ | C5 | Regression on modified screens | Creating a normal call (H1), editing a call (E1) and importing calls on a fund with commitments still work as before | | |
| ☐ | C6 | Empty states | N/A — no new lists or panels | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
