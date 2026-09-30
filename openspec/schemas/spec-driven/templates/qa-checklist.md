# [Feature Name] — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

<!-- CORE. Links to every ## heading. -->

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

<!-- CORE. Everything the tester needs before starting: environment, accounts, seed data, and how
     to trigger background work by hand. Follow the design's shared-setup table. -->

| Item | Detail |
|---|---|
| Environment | <!-- staging URL --> |
| Accounts | <!-- one per role in the Role Sweep, with the entity each belongs to --> |
| Second entity | <!-- a user in a different entity, for isolation checks --> |
| Seed data | <!-- records to create first, with exact names/emails from design.md --> |
| Background work | <!-- how to make it run now: a button (e.g. Sync now), or ask a developer --> |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | <!-- from design.md H1 --> | <!-- --> | 1. <!-- click / type --> 2. … | <!-- exact on-screen text where there is one --> | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | | | | | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | | | | | | |

---

## UI Journeys

<!-- CONDITIONAL: include when design.md has UI Changes. One row per journey step. Check that
     each numbered callout on the design's wireframe behaves as described. -->

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | <!-- My profile → X panel --> | <!-- open it --> | <!-- ① status, ② field --> | | |

---

## Role Sweep

<!-- CORE. From design.md Policy: every role against every new or changed screen/action. Mark
     ✓ = allowed and works, ✗ = correctly blocked, ! = wrong. -->

| ID | Screen / action | <!-- Fund admin --> | <!-- Employee --> | <!-- Investor --> | <!-- Other-entity user --> |
|---|---|---|---|---|---|
| R1 | <!-- open the new page --> | | | | |

---

## Cross-cutting Checks

<!-- CORE. Keep the rows that apply, and mark the rest N/A. -->

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts sent by this feature arrive | Correct recipient, subject and links; dates shown as `Aug 19, 2026` | | |
| ☐ | C2 | Dates on changed screens | Follow the user's locale format (e.g. `19/08/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | No horizontal scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | A user in a different entity cannot see or reach any of this data, even with a direct URL | | |
| ☐ | C5 | Regression on modified screens | Each modified screen still does what it did before | | |
| ☐ | C6 | Empty states | New lists/panels with no data show a sensible message | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Pass with defects / Fail --> | |
