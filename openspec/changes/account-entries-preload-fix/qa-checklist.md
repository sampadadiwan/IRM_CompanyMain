# Account Entries Index Query Fix — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row.

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
| Environment | Staging, with a large entity (100k+ account entries) if available |
| Accounts | Company admin, an employee with access to the second fund only |
| Second entity | A company admin in a different entity |
| Seed data | At least two funds in the entity, each with entries; one fund with entries that have a commitment and investor KYC, and a fund-level entry with no commitment |
| Background work | None |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Related details are shown on each row | Seed data | 1. Reports → Account Entries 2. Look at the rows | Each row shows fund, investor, folio and KYC details as before | | |
| ☐ | H2 | Page opens fast for a large entity | Large entity | 1. Open Account Entries with no fund chosen | Page loads in seconds, no timeout | | |
| ☐ | H3 | Opens on the first fund | Two funds | 1. Reports → Account Entries, no fund chosen | Only the first fund's entries (fund ordering: position, then created); filter shows that fund; notice names the fund | | |
| ☐ | H4 | Narrowed list keeps all funds | Import with entries in a fund that is not first | 1. Open the import's page | Its entries are listed; no notice | | |
| ☐ | H5 | Delete returns to the fund | Two funds | 1. Delete an entry of the second fund | List of the second fund, not the first | | |
| ☐ | H6 | Choose another fund | Two funds | 1. Set the fund filter to the second fund | Only the second fund's entries | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Entry without commitment or investor | Fund-level entry exists | 1. Open the list 2. Find that entry | Row shown with blank commitment/investor | | |
| ☐ | E2 | Change page size | 25+ entries | 1. Set 5 per page 2. Set 10 per page | Both pages load, rows complete | | |
| ☐ | E3 | Employee with access to one fund | Employee login | 1. Open the list | Only that fund's entries, no repeats | | |
| ☐ | E4 | Select several funds | Two funds | 1. In the fund filter or address, select both funds | Both funds' entries are listed, no error | | |
| ☐ | E5 | Employee default | Employee login (second fund only) | 1. Open the list with no fund | The employee's fund entries, not an empty list | | |
| ☐ | E6 | Portfolio investment page | Portfolio investment with entries | 1. Open the investment 2. Look at its account entries | Its entries are listed, even if its fund is not the entity's first fund | | |
| ☐ | E7 | Account entries from a commitment page | Commitment in the second fund | 1. Open the commitment 2. Open its account entries | All of the commitment's entries | | |
| ☐ | E8 | Choose All Funds on purpose | Two funds | 1. Open the list 2. Set the fund filter to "All Funds" and search | Both funds' entries are listed; the filter still says "All Funds" | | |
| ☐ | E9 | Delete Results and Export All follow the fund shown | Two funds | 1. Open the list with no fund 2. Check where "Export All" and "Delete Results" point (hover, or export and read the file) | Export holds the first fund only; Delete Results asks about that fund's results only | | |
| ☐ | E10 | Download menu and New Account Entry | Two funds | 1. Open the list with no fund 2. Open Download 3. Click New Account Entry | Download is a menu with Export All; New Account Entry has the first fund filled in | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Other entity's data hidden | Second entity user | 1. Open the list | None of the first entity's entries appear | | |
| ☐ | X2 | Fund of another entity | Second entity's fund id | 1. Open `/account_entries?fund_id=<other entity fund>` | Empty list; not replaced by the first fund | | |

---

## UI Journeys

| ☐ | ID | Journey step | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | J1 | Open Account Entries from Reports | First fund pre-selected in the Filter card | | |
| ☐ | J2 | Change the fund filter to another fund and search | That fund's entries are listed | | |
| ☐ | J3 | Set the fund filter to All Funds and search | Every fund's entries are listed; the page does not jump back to the first fund | | |

---

## Role Sweep

| ID | Screen / action | Company admin | Employee | Investor | Other-entity user |
|---|---|---|---|---|---|
| R1 | Open Account Entries list | ✓ (first fund) | ✓ (first fund they can access) | ✗ | ✓ (own data only) |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Emails / alerts | N/A | | |
| ☐ | C2 | Dates on the list | Same format as before | | |
| ☐ | C3 | Narrow / mobile width | No horizontal page scroll introduced | | |
| ☐ | C4 | Tenant isolation | Other entity user cannot see these entries, even with a direct URL | | |
| ☐ | C5 | Regression: filters, search, sort and export on the list | Same results as before for the fund shown; export unchanged | | |
| ☐ | C6 | Empty state | A fund with no entries shows the usual empty list | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
