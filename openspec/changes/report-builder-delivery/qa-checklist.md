# Report Builder delivery — QA checklist

> Run by hand on a deployed build. IDs match [business-rules.md](business-rules.md) and the Cucumber scenarios.

## Contents

- [ID legend](#id-legend)
- [Setup](#setup)
- [Worked examples](#worked-examples)
- [Journeys](#journeys)
- [Role sweep](#role-sweep)
- [Cross-cutting checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

## ID legend

H happy path · E edge case · X error case · J journey step · R role sweep · C cross-cutting.

## Setup

A fund company with two funds, a few LP investors with cities, and a report like "LPs" (investors, Category, commitments' Committed and Called totals, Category is LP, commitments in one fund). A second company's user for the role sweep. An outside mailbox you can read.

## Worked examples

| ☐ | ID | Check | Steps | Expected | Pass/Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | H1 | Export from the report page | Open the report › **Export XLSX** | *Preparing…* (disabled), then **Download** and **Export again**; Recent exports' first row is the report, by you, now | | |
| ☐ | H2 | Export from the builder | Edit › **Export XLSX** in the header | Same states in the header | | |
| ☐ | H3 | Recent exports | Export 7 times › reload | 5 rows, newest first, each with name · you · date time · Download | | |
| ☐ | H4 | Save inside the company | Delivery › on › Weekly › India Standard Time › two colleagues › **Save schedule** | No popup; "Schedule saved — weekly on Monday at 09:00 IST to 2 people" | | |
| ☐ | H5 | Outsider, Proceed | Add your outside mailbox › Save | Immediate Actions popup naming it › **Proceed** saves | | |
| ☐ | H6 | Send test to me | **Send test to me** | "A test is on its way to <you>"; one email with the Excel file arrives to you only | | |
| ☐ | H7 | Last sent · Next | After a scheduled send (ask a developer to run the scheduler) | "Last sent <dd Mon yyyy HH:MM> IST · Next … IST" | | |
| ☐ | H8 | Test isn't "last sent" | Send a test | "Last sent" unchanged | | |
| ☐ | H9 | Saved chips | Open the report | "This report shows only:" *Category is LP* · *Only capital commitments in <fund>*; "Change in builder" | | |
| ☐ | H10 | Narrow down | Narrow down › City › is › Mumbai › Apply | Mumbai rows only; chip *City is Mumbai ✕* | | |
| ☐ | H11 | Cards | Open the report | Cards equal the totals row's figures, in column order, at most 4 | | |
| ☐ | H12 | No View settings | Builder, every tab | No View/Sharing controls | | |
| ☐ | E1 | No exports | A new report | "No exports yet — Export XLSX makes one." | | |
| ☐ | E2 | Only this report | Export report A; open report B | B shows E1's text | | |
| ☐ | E3 | Outsider, Cancel | As H5 › **Cancel** | Nothing saved (reload: no schedule) | | |
| ☐ | E4 | Tidy addresses | `Meera@X.com; ravi@x.com` + new line `meera@x.com` › Save | Reload: two lower-case addresses | | |
| ☐ | E5 | Turn off | Switch off a saved schedule | "Schedule turned off" at once | | |
| ☐ | E6 | Old UTC schedule | A schedule saved before this release | Time zone UTC; "Next … UTC" | | |
| ☐ | E7 | Never sent | Save a new schedule | "Not sent yet · Next …" | | |
| ☐ | E8 | Remove reader chip | As H10 › ✕ | All rows back | | |
| ☐ | E9 | Saved filter wins | Add `&q[category_eq]=Co-Investor` to the address | Still LPs; "Category is already set by the report" | | |
| ☐ | E10 | Unknown field | Add `&q[no_such_field_eq]=x` | Same rows; no chip | | |
| ☐ | E11 | No saved filters | A report without filters | No "This report shows only" line | | |
| ☐ | E12 | Paged | `&per_page=2` | Cards say "this page"; equal "Total (this page)" | | |
| ☐ | E13 | Nothing to total | A names-only report | No cards | | |
| ☐ | E14 | Old view report | A report once marked as a view | Opens and runs | | |
| ☐ | X1 | Export fails | Ask a developer to break the export (e.g. no folder) › Export | Button back to **Export XLSX**; "Couldn't export <name>: …" | | |
| ☐ | X2 | Invalid address | `bob@` › Save | "bob@ isn't an email address" under the field; typed text kept | | |
| ☐ | X3 | Empty | Clear recipients › Save | "Add at least one email" | | |
| ☐ | X4 | Unconfirmed outsider | Developer sends the save request without confirming | Refused: "Confirm sending to people outside <company> first" | | |
| ☐ | X5 | Another company | Second company's user opens the test-send address | Access Denied | | |

## Journeys

| ☐ | ID | Step | Expected | Pass/Fail |
|---|---|---|---|---|
| ☐ | J1.1–J1.4 | Export from page and builder, Download | As design J1 | |
| ☐ | J2.1–J2.7 | Schedule: on, error, popup, save, test, history, off | As design J2 | |
| ☐ | J3.1–J3.4 | Read: cards, chips, Narrow down, ✕ | As design J3 | |

## Role sweep

| ☐ | ID | Role | Export / Narrow down | Schedule / test |
|---|---|---|---|---|
| ☐ | R1 | User of the report's company | Yes | Yes |
| ☐ | R2 | User of another company | Access Denied | Access Denied |

## Cross-cutting checks

| ☐ | ID | Check | Expected |
|---|---|---|---|
| ☐ | C1 | Emails | Scheduled and test emails arrive; subject "Scheduled Report: <name>"; Excel attached |
| ☐ | C2 | Dates | Recent exports and Last sent use `dd Mon yyyy HH:MM` |
| ☐ | C3 | Narrow width | Report page at 390 px: cards stack, chips wrap, Narrow down usable |
| ☐ | C4 | Tenant isolation | Second company can't open the report, its exports or its schedule |
| ☐ | C5 | Regression | Builder tabs, report sorting, totals row, Duplicate, templates still work |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
