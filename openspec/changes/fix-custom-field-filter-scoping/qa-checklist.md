# Custom-field list filters — Manual QA Checklist

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
| Environment | Staging (IN), then US |
| Accounts | Company A admin; Company B admin (a different company on the same staging server) |
| Seed data | Company A: on the Capital Commitment form (Company menu → **Customize Forms**), a Number field **Ticket size** with **Show in Filter** ticked, and a Text field **A only field** with **Show in Filter** ticked. Three commitments with Ticket size 9, 25 and 100. Company B: no such fields |
| Background work | None |
| Developer-assisted rows | X1 |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | Number filters compare as numbers | 1. As Company A, open the capital commitments list and open the filter. 2. Pick **Ticket size**, **greater than**, type 10. 3. Search | The 25 and 100 commitments are listed; the 9 one is not | | |
| ☐ | B2 | Company B does not see Company A's fields | 1. Do B1 as Company A. 2. Log in as Company B, open the capital commitments list and open the filter. 3. Open the attribute dropdown | No **Ticket size** or **A only field** in B's dropdown | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Number filter, less than / at most | Seed data | Filter **Ticket size** **less than** 30 | 9 and 25 listed; 100 not | | |
| ☐ | H2 | Text and dropdown filters still work | A text custom field filterable | Filter it with **contains** a value one record has | Only that record listed | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Labels are your own company's | Both companies have a field with the same key but different labels | Open the filter dropdown as each company | Each sees its own label | | |
| ☐ | E2 | Same field name, different type | A: Number "Score"; B: Text "Score" | Each filters on Score | A compares numbers; B compares text; neither errors | | |
| ☐ | E3 | Un-ticking Show in Filter takes effect at once | A field currently offered | Admin unticks **Show in Filter**, user reloads the list with the filter open | The field is no longer offered | | |
| ☐ | E4 | Workflow rule fields unaffected | Company B opened its KYC filter | Company A opens a new auto-assignment rule on a KYC template | Only A's KYC custom fields are listed under **Custom fields** | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Background work with no signed-in user **(dev)** | — | Ask a developer to run a KYC search in a console with no current user | No error; custom fields simply not searchable there | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Investor KYC list filter on a custom field | Filter KYCs by a filterable custom field | Matching KYCs only | | |
| ☐ | R2 | Account entries filter on a custom field | Open a fund's account entries, filter by a filterable custom field | Matching entries only; page loads in normal time | | |
| ☐ | R3 | Portfolio investments and valuations filters | Filter each by a filterable custom field | Matching rows only | | |
| ☐ | R4 | Stakeholder custom field on the commitments filter | Filter commitments by a filterable stakeholder custom field (under the stakeholder group) | Matching commitments only | | |
| ☐ | R5 | Custom-field labels elsewhere | Open a KYC form and a commitment list with custom-field columns | Labels show as before | | |
| ☐ | R6 | Workflow auto-assignment rules | Create a KYC with a rule on a custom field | Gets the rule's template as before | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | A date custom-field filter still accepts and shows the locale format (e.g. `19/08/2026` for en) | | |
| ☐ | C2 | Dates in any email the fix touched | N/A — no email involved | | |
| ☐ | C3 | Narrow / mobile width | Filter panel unchanged; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Company B never sees Company A's custom-field names or labels in any filter dropdown (B2, E1) | | |
| ☐ | C5 | Screens the fix touched | The five list screens' filters do everything they did before | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
