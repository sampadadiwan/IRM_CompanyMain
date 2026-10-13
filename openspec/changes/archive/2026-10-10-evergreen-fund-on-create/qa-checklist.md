# Choose Closed-end or Open-ended When Creating a Fund — Manual QA Checklist

> **Audience:** Testers on a deployed build.

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
| Accounts | Asha (company admin) in a company with evergreen and units on; a user in a company without evergreen |
| Data | One existing closed-end fund; one existing evergreen fund |

---

## Happy Path

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 | Create an open-ended fund | New Fund › Open-ended › Unit Types "A, B" › through the wizard › Class A and B ₹10,000 › Create fund | Fund page with evergreen tabs; "Alpha Long-Short Fund created as an open-ended fund" | | |
| ☐ | H2 | Create a closed-end fund | New Fund › Closed-end › Save | "Fund was successfully created." | | |
| ☐ | H3 | Back button | New Fund › Next › Back | Step 1 with values kept | | |

## Edge Cases

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | E1 | No evergreen switch | Open New Fund | No Fund type field | | |
| ☐ | E2 | Cards follow unit types | "A, B" → Classes → Back → "A" | Only Class A | | |
| ☐ | E3 | Messy unit types | " A, B, A " | Two cards | | |
| ☐ | E4 | Change mind before saving | Open-ended, then Closed-end, Save | Closed-end fund | | |
| ☐ | E5 | Edit shows the type | Edit each fund | Read-only type | | |
| ☐ | E6 | Terms still editable | Evergreen Settings › gate 10% › Save | Saved; no "Make closed-end again" | | |

## Error Cases

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | X1 | No unit types | Open-ended, Unit Types blank, Create fund | "Add at least one unit class for an open-ended fund"; nothing saved | | |
| ☐ | X2 | Missing starting price | Class B blank, Create fund | "Class B needs a starting price"; nothing saved; values kept | | |
| ☐ | X3 | Missing name | Name blank, Create fund | Name error; nothing saved | | |
| ☐ | X4 | No make-evergreen | Existing closed-end fund › Actions; open its settings URL | No menu item; redirected with "A fund's type is chosen when it is created and can't be changed" | | |
| ☐ | X5 | No switch-back | Evergreen Settings of an evergreen fund | No "Make closed-end again" | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | New Fund | Toggle the fund type | The step bar grows from 2 to 11 steps and shrinks back; the last button reads Create fund / Save | | |

---

## Role Sweep

| ID | Action | Company admin | Employee without create rights | Other company |
|---|---|---|---|---|
| R1 | Create an open-ended fund | ✓ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C3 | Narrow width | The 11-step bar stays usable | | |
| ☐ | C4 | Tenant isolation | Other company can't use the presets endpoint without evergreen | | |
| ☐ | C5 | Regression | Closed-end creation unchanged | | |

---

## Sign-off

| Tester | Build | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
