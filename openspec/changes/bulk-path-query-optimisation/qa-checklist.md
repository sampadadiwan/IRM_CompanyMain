# Faster bulk jobs — Manual QA Checklist

> **Audience:** Testers running the change by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail. Row IDs match
> [business-rules.md](business-rules.md). This change must look **exactly like before** — every row
> compares a result with what the same action produced on the previous build.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step · **R** = Role sweep · **C** = Cross-cutting check

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
| Environment | staging |
| Accounts | Fund admin (Meera) and portfolio analyst (Arjun) in entity "QA Fund Co"; one user in a second entity |
| Seed data | As [business-rules shared setup](business-rules.md#shared-setup): Fund Alpha (3 commitments), Company Acme (KPI mappings + Jan–Jun 2026 Revenue), Fund Beta (formulas 1–3), Fund Gamma (2 portfolio investments) |
| Baseline | Record the results of each row on the previous build first (screenshots or exports) |
| Background work | Capital call generation, KPI cumulation and re-value jobs run in the background; wait for the progress line / notification, or ask a developer to run "fair value recompute" for Fund Gamma |

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Capital call remittances | Fund Alpha | 1. Fund Alpha › Capital Calls › New "Q3" 10% 2. Generate Remittances 3. Wait for progress to finish | 3 remittances: Acme LP ₹1,00,00,000, Beta Trust ₹50,00,000, Gamma HUF ₹20,00,000; same as baseline | | |
| ☐ | H2 | Payments generated | H1 | 1. Capital Call › Generate payments | Each remittance shows its payment; statuses same as baseline | | |
| ☐ | H3 | KPI cumulation | Company Acme | 1. KPI grid › Actions › Approve all 2. Wait for "Approved … KPIs for Acme" 3. Open Quarter / YTD views | Q1 Revenue 33, Q2 42, YTD Jun 75 | | |
| ☐ | H4 | KPI workbook upload | Company Acme | 1. KPI Reports › Upload the sample workbook | 12 staged KPIs; same as baseline | | |
| ☐ | H5 | Formula import (append) | Fund Beta | 1. Fund › Formulas › Import sheet with sequences 4,5,6 | List shows sequences 1–6 in order | | |
| ☐ | H9 | Remittance form type | Fund Alpha with a CapitalRemittance form type | Generate remittances for Q3; open one | The remittance's custom fields form is the CapitalRemittance one, as baseline | | |
| ☐ | H10 | Portfolio as of a past date | Fund Gamma | Fund › Portfolio › as-of date last quarter | Quantities, FMV and gains same as baseline | | |
| ☐ | H6 | Fair value recompute | Fund Gamma | 1. Ask developer to run fair value recompute 2. Fund › Portfolio | Quantities and values same as baseline | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Missing Quarter report created once | Acme, no Q2 Quarter report | Approve all, wait | Exactly one Q2 Quarter report in KPI Reports | | |
| ☐ | E2 | Repeated workbook row | Workbook with Jan Revenue twice, same value | Upload | One Jan Revenue KPI | | |
| ☐ | E3 | Revenue in several reports | Acme | Approve all | Values as H3 | | |
| ☐ | E4 | Blank report tag | Acme report with no tag | Approve all | Cumulative values written as baseline | | |
| ☐ | E5 | Formula inserted in the middle | Fund Beta | Import one row with sequence 2 | New formula at 2; old 2,3 now 3,4 | | |
| ☐ | E6 | Duplicate sequences in sheet | Fund Beta | Import rows 4,4,4 | Order same as baseline | | |
| ☐ | E7 | Blank sequence | Fund Beta | Import a row with no sequence | Appended at the end (4) | | |
| ☐ | E9 | Investment with no attributions | Fund Gamma third PI | Recompute | Quantities same as baseline | | |
| ☐ | E12 | No remittance form type | Entity without one | Generate remittances | Generation completes; remittances as baseline | | |
| ☐ | E13 | Proforma and later sales | Fund Gamma with a proforma sale and a sale after the as-of date | Portfolio as of the date | Net quantity leaves out both the proforma sale and the later one; same as baseline | | |
| ☐ | E10 | Portfolio import totals | 3 PIs into one company | Import | Company totals same as baseline | | |
| ☐ | E11 | Mapping edited between runs | Acme | Change Revenue mapping, approve again | New mapping applied | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Invalid document blocks save | A remittance with a broken attached document | Generate payments | Same error as baseline; other remittances fine | | |
| ☐ | X2 | Cumulation error email | Acme with one invalid cumulative KPI | Approve all | One error email listing the KPI once | | |

## UI Journeys

No screen changes. J1.1–J1.4 = proposal Part A steps A1–A4; J2.1–J2.6 = Part B B1–B6; J3.1–J3.4 = Part C C1–C4 — walk each and confirm every screen looks like the baseline.

## Role Sweep

| ☐ | ID | Role | Check | Expected |
|---|---|---|---|---|
| ☐ | R1 | Fund admin | H1, H2, H5 | Allowed, same as baseline |
| ☐ | R2 | Portfolio analyst | H3, H4 | Allowed, same as baseline |
| ☐ | R3 | Read-only user | Try Generate / Approve all | Refused, same as baseline |

## Cross-cutting Checks

| ☐ | ID | Check | Expected |
|---|---|---|---|
| ☐ | C1 | Remittance notice emails | Same content; dates as `Aug 19, 2026` |
| ☐ | C2 | Screen dates | In the user's locale format |
| ☐ | C3 | Narrow / mobile width | Remittances and KPI grid unchanged |
| ☐ | C4 | Tenant isolation | Second-entity user cannot see Fund Alpha / Acme data |
| ☐ | C5 | Regression spot-check | Capital call page, KPI grid, Formulas page, Portfolio page load and look as before |

## Sign-off

| Tester | Build/commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
