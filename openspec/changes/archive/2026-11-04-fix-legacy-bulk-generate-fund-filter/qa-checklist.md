# Fix Legacy Bulk Generate Fund Filter — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **R** = Role sweep · **C** = Cross-cutting

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
| Environment | dev / staging (MySQL, where the error occurred) |
| Accounts | A user with permission to bulk generate portfolio reports |
| Second entity | A user in another entity |
| Seed data | A fund with investments in at least two portfolio companies (one with several investments); a fund with none; companies with differing sectors |
| Background work | None |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Preview by fund | Seed data | 1. Open Bulk generate portfolio reports 2. Pick the fund 3. Click Preview | Page loads with no error; only companies with investments in the fund are selected | | |
| ☐ | H2 | Fund plus sector | Seed data | 1. Pick the fund and one sector 2. Preview | Only companies in both the fund and sector are selected | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Several investments in one fund | Company with 3+ investments in the fund | Preview with the fund | Company is selected once | | |
| ☐ | E2 | Fund with no investments | Empty fund | Preview with it | Nothing selected, no error | | |
| ☐ | E3 | No fund chosen | None | Preview with only a tag | Fund filter not applied; list alphabetical | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Original crash is gone | MySQL environment; open the URL with `previewed=true&fund_ids[]=<fund id>` | Load it directly | Page renders; no error page; no new exception alert email | | |

---

## UI Journeys

N/A — no UI changes.

---

## Role Sweep

| ID | Screen / action | Bulk-generate user | User without access | Other-entity user |
|---|---|---|---|---|
| R1 | Open the bulk generate page and preview by fund | ✓ | ✗ | ✗ (cannot see this entity's companies) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A | | |
| ☐ | C2 | Dates on changed screens | N/A | | |
| ☐ | C3 | Narrow / mobile width | N/A | | |
| ☐ | C4 | Tenant isolation | Other-entity user sees none of this entity's companies | | |
| ☐ | C5 | Regression | Preview with Tag only and Sector only still works; company list is alphabetical | | |
| ☐ | C6 | Empty states | N/A | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
