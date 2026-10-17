# Tenant isolation, batch 1 — Manual QA Checklist

> **Audience:** Testers on a deployed build. **Companion document:** [Report](report.md)

> **How to use:** tick ☐ → ☑, write Pass or Fail. Rows marked **(dev)** need a developer to send a
> crafted request; everything else is clicking.

**ID legend:** IDs match the report · **R-** = regression · **C** = cross-cutting

## Contents

- [Test Setup](#test-setup)
- [The Original Bugs](#the-original-bugs)
- [Regression](#regression)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

## Test Setup

| Item | Detail |
|---|---|
| Accounts | GP company admin of *Artha* (fund *F*); a second tenant *Zeta* with a fund; an LP user of *F*; an advisor with a grant on a client; a seller with an unverified offer |
| (dev) rows | S1–S4, R1, R1b, R4 need a crafted request or a console check |

## The Original Bugs

| ☐ | ID | Check | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | S1 | **(dev)** PATCH a grant with another `entity_id` | grant stays in its entity; role edits still save | |
| ☐ | S2 | **(dev)** Add Investor Advisor with Zeta's fund id | Access Denied | |
| ☐ | S3 | **(dev)** PATCH a user with another `entity_id` | entity unchanged | |
| ☐ | S4 | **(dev)** document search with Zeta's `entity_id` | only own documents | |
| ☐ | S5 | Investor user opens another seller's unverified offer edit page | Access Denied | |
| ☐ | S6 | LP opens a fund report link (e.g. advisor payouts) | Access Denied; no **Sign In Report** on the LP's fund card | |
| ☐ | S7a | Employee without deal update right opens a deal's edit page | Access Denied | |
| ☐ | S8 | Advisor switches into a client named with `<b>` markup | name shown literally | |
| ☐ | R1 | **(dev)** post an import with Zeta's `entity_id` | runs in own entity | |
| ☐ | R2 | Delete a grant while the advisor is switched into it | advisor lands back in their own firm | |
| ☐ | R3 | Advisor on two clients in one fund; delete one client's Users-tab row | that client's fund disappears from the advisor's view in that client | |
| ☐ | R4 | **(dev)** scheduled report whose owner is switched elsewhere | report contains its own entity's data | |
| ☐ | R5 | Client admin opens a switched-in advisor's user page | Access Denied; the advisor's own firm admin can still edit them | |

## Regression

| ☐ | ID | Still works | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | R-1 | Edit an advisor grant's roles/permissions | saved | |
| ☐ | R-2 | Add Investor Advisor from a commitment | advisor created with fund access | |
| ☐ | R-3 | Create and edit users | as before | |
| ☐ | R-4 | Document search by tag link | results as before | |
| ☐ | R-5 | Seller edits own unverified offer | saved | |
| ☐ | R-6 | GP staff open every fund report | as before | |
| ☐ | R-7 | Any import from its screen | runs as before | |
| ☐ | R-8 | Advisor switch / Self | as before | |
| ☐ | R-9 | On-demand report export | as before | |
| ☐ | R-10 | Support login-as for a regular user | as before | |

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail |
|---|---|---|---|---|
| ☐ | C1 | Dates | N/A — no date rendering changed | |
| ☐ | C2 | Email dates | N/A | |
| ☐ | C3 | Mobile width | N/A — no layout changed | |
| ☐ | C4 | Tenant isolation | the whole checklist | |
| ☐ | C5 | Fund page for LPs | loads; only the report button is gone | |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
