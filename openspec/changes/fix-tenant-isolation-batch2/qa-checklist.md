# Tenant isolation, batch 2 — Manual QA Checklist

> **Audience:** Testers on a deployed build. **Companion document:** [Report](report.md)

> **How to use:** tick ☐ → ☑, write Pass or Fail. **(dev)** rows need a developer.

**ID legend:** IDs match the report · **R-** regression · **C** cross-cutting

## Contents

- [Test Setup](#test-setup)
- [The Original Bugs](#the-original-bugs)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Accounts | GP admin of *Artha* (funds F1, F2); LP *Harshal* with a user; advisor for Harshal on F1 only; a plain Artha employee; another tenant *Zeta* |
| Seed data | **(dev)** F1 and F2 statements and an AGM deck shared with Harshal; an approval and a sale shared with Harshal; fund ratios with per-folio rows for two LPs |

## The Original Bugs

| ☐ | ID | Check | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | B1-X | Harshal's user opens Zeta's company page (by URL) | name, logo, type; no tax id or email | |
| ☐ | B1-H | Artha admin opens Harshal's company page | full details | |
| ☐ | B3-1 | Advisor switched into Harshal opens Artha's documents | only the F1 statement listed and downloadable | |
| ☐ | B3-H | Harshal's own user | all three documents | |
| ☐ | B3-2 | Advisor's folder tree | AGM folder absent | |
| ☐ | B3-3 | Advisor's approvals and secondary sales lists | neither the approval nor the sale | |
| ☐ | B4-1 | LP1 opens fund ratios | fund-level and own folio only | |
| ☐ | B4-2 | Advisor opens edit on a client KYC with no commitment | Access Denied | |
| ☐ | B4-3 | Advisor opens a client deal investor by link | Access Denied | |
| ☐ | B4-4 | Plain employee searches a deal they have no access to | not in results | |
| ☐ | B4-5 | **(dev)** MCP token for Artha after the user switches | client asked to re-authorise | |
| ☐ | B4-6 | **(dev)** Artha admin calls a Zeta validation rule | refused | |

## Regression

| ☐ | ID | Still works | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | R-1 | LP portal documents, data room, NDA acceptance | as before | |
| ☐ | R-2 | Request access → GP company page | opens (public profile) | |
| ☐ | R-3 | Company admin searches in every module | same results as before | |
| ☐ | R-4 | Investor autocomplete for admins | as before | |
| ☐ | R-5 | LP completes own KYC from the email link | works | |
| ☐ | R-6 | MCP client of a non-advisor user | works | |
| ☐ | R-7 | Deal ingest address edit by admin | works | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | C1 | Dates | N/A | |
| ☐ | C2 | Email dates | N/A | |
| ☐ | C3 | Mobile width | N/A | |
| ☐ | C4 | Tenant isolation | the whole checklist | |
| ☐ | C5 | Screens touched | load as before | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
