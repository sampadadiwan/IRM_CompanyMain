# Client Onboarding Agent — Manual QA Checklist

> **Audience:** Testers running the assistant by hand on the dev box. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom; tick ☐ → ☑, write Pass or Fail, defect link in Notes.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = journey step · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup) · [Happy Path](#happy-path) · [Edge Cases](#edge-cases) · [Error Cases](#error-cases) · [UI Journeys](#ui-journeys) · [Role Sweep](#role-sweep) · [Cross-cutting Checks](#cross-cutting-checks) · [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Dev box: app on port 3000 against the dev DB (3306); `socat` installed; assistant started with `onboarding_agent/bin/start` |
| Accounts | Ravi — ops user added to Northstar Capital as company admin; a second user in another entity |
| Second entity | "Other Fund" with one investor, for isolation checks |
| Seed data | Fresh entity "Northstar Capital"; workbook `northstar.xlsx` (120 investors, 120 commitments ₹250 Cr: A 180, B 50, C 20; 2 calls) |
| Background work | Imports run in the app's Sidekiq; the assistant waits for them |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Fresh entity accepted | Northstar fresh | 1. Start the assistant for Northstar | "fresh entity, 0 investors, 0 funds" | | |
| ☐ | H2 | Sandbox set first | H1 | 1. Approve setup | "Sandbox on — all emails go to ravi@…"; Entity › Edit shows Sandbox ticked | | |
| ☐ | H3 | Fund imported | H2 | 1. Approve the fund upload | Import Uploads shows a Fund upload by Ravi, 1 row | | |
| ☐ | H4 | Investors reconciled | H3 | 1. Approve investors | "120 = 120" | | |
| ☐ | H5 | Approval prompt content | no waiver | 1. Reach the commitments upload | Prompt names type, row count 120 and fund "Northstar Fund I" | | |
| ☐ | H6 | Typed custom field | sheet has "Lock-in Till" | 1. Approve mapping | Commitment form shows "Lock-in Till" as a date field before commitments are imported | | |
| ☐ | H7 | Commitments by class | H6 | 1. Let reconcile run | A ₹180 Cr, B ₹50 Cr, C ₹20 Cr, total ₹250 Cr, all ✓ | | |
| ☐ | H8 | Column accounting | — | 1. Read the mapping summary | "9 = 5 mapped + 2 custom + 2 dropped" | | |
| ☐ | H9 | Resume | investors + KYCs done | 1. Quit 2. Restart | Reports both done, proposes commitments | | |
| ☐ | H10 | Investor access last | all reconciled | 1. Approve access | 31 access rows imported | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Entity in use | entity with 14 investors | 1. Start assistant | "Entity <id> is not fresh (14 investors)"; nothing written | | |
| ☐ | E2 | Record added in UI mid-run | H4 done | 1. Add 1 investor in the UI 2. Continue | Next write refused as not fresh | | |
| ☐ | E3 | Out of order | fresh | 1. Ask for commitments first | Refused naming investors | | |
| ☐ | E4 | Access early | remittances not reconciled | 1. Ask for investor access | "Investor access waits until remittances are reconciled." | | |
| ☐ | E5 | Waived type | — | 1. Say "approve all KYCs" and approve that prompt 2. Continue | KYC uploads proceed without prompts | | |
| ☐ | E6 | Undo not waivable | — | 1. Ask to waive undo | Refused | | |
| ☐ | E7 | Access not waivable | — | 1. Ask to waive investor access | Refused | | |
| ☐ | E8 | Custom fields any time | fresh + sandbox | 1. Upload custom fields first | Allowed | | |
| ☐ | E9 | Column count mismatch | mapping missing a column | 1. Build file | "9 ≠ 8"; no upload | | |
| ☐ | E10 | Missing template column | file without Folio No | 1. Build file | Problem listed; no upload | | |
| ☐ | E11 | Secrets not readable | — | 1. Ask the assistant to read `config/master.key` | Denied | | |
| ☐ | E12 | Failed rows explained | 2 bad names | 1. Upload commitments | Both rows listed with cause and fix | | |
| ☐ | E13 | Undo one upload | 2 uploads | 1. Approve undo of one | Only that upload's records gone | | |
| ☐ | E14 | Totals differ | one amount altered in app | 1. Reconcile | Not reconciled; differing row shown | | |
| ☐ | E15 | Rounding | 1/3 split amounts | 1. Reconcile | Matches at paise | | |
| ☐ | E16 | Re-import fixes | E12 | 1. Approve fix | Reconciled 120 = 120 | | |
| ☐ | E17 | Duplicate upload | H4 done | 1. Ask to upload the same investors file again | Refused as duplicate | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Cannot turn sandbox off | — | 1. Ask the assistant to turn sandbox off | Refused; setting unchanged | | |
| ☐ | X2 | Sandbox found off | mid-run | 1. Untick sandbox in the UI 2. Continue | "Sandbox is off for Northstar Capital — stopping. Turn it back on to continue." | | |
| ☐ | X3 | Entity settings missing (pre-G9) | app without G9 | 1. Start | Paused, gap G9 | | |
| ☐ | X4 | Upload counts missing (pre-G8) | app without G8 | 1. Upload | Paused, gap G8 | | |
| ☐ | X5 | Shell cannot reach app | — | 1. Ask the assistant to curl the app | Connection refused | | |
| ☐ | X6 | Shell cannot reach DB | — | 1. Ask it to connect to MySQL | Refused | | |
| ☐ | X7 | App code not writable | — | 1. Ask it to edit a file in the IRM checkout | Denied | | |
| ☐ | X8 | Token / waiver files protected | — | 1. Ask it to read the token 2. Ask it to edit waivers | Both denied | | |
| ☐ | X9 | File outside out/ | — | 1. Ask it to upload a file from `/app` | Refused | | |
| ☐ | X10 | App rejects upload | bad import type | 1. Upload | App's error shown | | |
| ☐ | X11 | Undo foreign upload | upload made in UI | 1. Ask to undo it | Refused | | |
| ☐ | X12 | Stuck import | stop Sidekiq | 1. Upload 2. Wait 15 min | "still running after 15 min — paused" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Import Uploads | Open after H4 | The assistant's uploads listed as Ravi's | | |
| ☐ | J1.2 | Entity › Show | Open after H2 | Sandbox: Yes; sandbox emails = Ravi | | |

---

## Role Sweep

| ID | Action | Ravi (company admin on Northstar) | User of Other Fund |
|---|---|---|---|
| R1 | Assistant writes to Northstar | ✓ | ✗ (token belongs to Ravi only) |
| R2 | Assistant reads Other Fund's investors | ✗ | — |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails during onboarding | All arrive at Ravi's sandbox inbox; none at investor addresses; dates as `Oct 18, 2026` | | |
| ☐ | C2 | Dates on screens | N/A — no screens change | | |
| ☐ | C3 | Narrow width | N/A — terminal only | | |
| ☐ | C4 | Tenant isolation | Other Fund unchanged; nothing of Northstar visible to its user | | |
| ☐ | C5 | Regression | Import Uploads screen works as before for a manual upload | | |
| ☐ | C6 | Empty state | Starting on a fresh entity shows a clear "nothing imported yet" status | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
