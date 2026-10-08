# [Bug Name] — Manual QA Checklist

> **Audience:** Testers running the fix by hand on a deployed build. No code knowledge needed.
> **Companion document:** [Report](report.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the report's Verification table (H/E/X), so a
> failure maps straight to the automated scenario that should have caught it.

**ID legend:** **B** = the original bug, reproduced · **H** = Happy path · **E** = Edge case ·
**X** = Error case · **R** = Regression (from Blast Radius) · **C** = Cross-cutting check ·
**(dev)** = needs a developer or a config change

---

## Contents

- [Test Setup](#test-setup)
- [The Original Bug](#the-original-bug)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | <!-- staging URL(s) --> |
| Accounts | <!-- one per role the fix touches --> |
| Seed data | <!-- records to create first; say if a developer must create them --> |
| Background work | <!-- how to make it run now: a button, or ask a developer --> |
| Developer-assisted rows | <!-- list the (dev) IDs and what they need --> |

---

## The Original Bug

<!-- The first thing a tester does: reproduce the bug exactly as it was reported, and confirm it
     is gone. If this row passes and everything else fails, the fix is still probably right. If
     this row fails, nothing else matters. -->

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | <!-- the reported symptom is gone --> | 1. <!-- the original reproduce steps --> | <!-- what should happen now --> | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | | | | | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | | | | | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | | | | | | |

---

## Regression

<!-- One row per Blast Radius entry marked as needing checking: the things that share the code
     the fix changed and must still behave exactly as before. -->

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | | | | | |

---

## Cross-cutting Checks

<!-- Keep the rows that apply; mark the rest N/A with a reason. -->

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | Locale format (e.g. `19/08/2026` for en) | | |
| ☐ | C2 | Dates in any email the fix touched | `Aug 19, 2026`, whatever the locale | | |
| ☐ | C3 | Narrow / mobile width | No horizontal scroll; buttons reachable | | |
| ☐ | C4 | Tenant isolation | A user in a different entity cannot see or reach this data, even with a direct URL | | |
| ☐ | C5 | Screens the fix touched | Each still does everything it did before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | <!-- Pass / Pass with defects / Fail --> | |
