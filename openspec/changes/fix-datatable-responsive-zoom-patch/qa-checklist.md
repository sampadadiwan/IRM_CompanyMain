# DataTable responsive patch crashes at fractional zoom — Manual QA Checklist

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
| Environment | Staging, in Google Chrome (desktop) |
| Accounts | Any user who can open the Investments list and the Favorites page. A company admin is simplest. |
| Seed data | At least one fund with a few investments, so the Investments list has rows and a Show / Edit column. Add one or two favorites so the Favorites page isn't empty. |
| Browser zoom | Change it with **Ctrl + −** / **Ctrl + +** (**⌘** on Mac). Reset it with **Ctrl + 0**. Zoom is remembered for each site, so reset it between rows. |
| Error console | Press **F12** (or **⌥⌘I** on Mac) and open the **Console** tab. Several rows ask you to check that no red error mentioning `forEach` appears. Clear the console (🚫 icon) before each row. |
| Background work | None |
| Developer-assisted rows | None |

---

## The Original Bug

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | B1 | The console error at 90% zoom is gone | 1. Open the Investments list at 100% zoom. 2. Open the Console and clear it. 3. Press **Ctrl + −** once (90%). 4. Reload the page (**Ctrl + Shift + R**). | The table loads with its search box and paging. The Console shows **no** red `TypeError: columns.forEach is not a function`. | | |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Table works normally at 100% | Zoom reset to 100% (**Ctrl + 0**) | 1. Open the Favorites page. 2. Type in the table's search box. | The table shows its rows and the search filters them. No `forEach` error in the Console. | | |
| ☐ | H2 | Table works at a fractional zoom, and the action buttons stay visible (manual only) | Investments list with rows | 1. Set zoom to 90%. 2. Reload. 3. Look at the last column. | Every row's **Show** / **Edit** buttons are visible on one line and aren't hidden behind a ▶ toggle. No `forEach` error. | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Repeated recalculation at 90% doesn't keep shrinking the columns | Investments list at 90% | 1. Reload. 2. Make the browser window narrower and then wider several times. 3. Return it to the starting size. | The same columns are shown as after the first load. Columns don't gradually fold away. (Manual only: no automated scenario.) | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message shown, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | No error at other fractional zooms | Investments list | 1. Repeat B1 at **80%**, **110%** and **125%** zoom, reloading each time. | No red `forEach` error at any of these zooms. At 110% / 125%, if the table is too wide, data columns fold behind ▶ first and **Show** / **Edit** stay visible. | | |

---

## Regression

| ☐ | ID | What still has to work | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | R1 | Other list pages set up fully at fractional zoom | At 90% zoom, open 3 other list pages, e.g. Investors, Documents, Reports. | Each one has a search box with a "Search..." placeholder, working page numbers, and working row dropdown menus. No `forEach` error. | | |
| ☐ | R2 | Tables re-fit when the sidebar is collapsed or expanded | At 90% zoom on the Investments list, collapse and then expand the left sidebar. | The table re-fits each time without a reload. No error in the Console. | | |
| ☐ | R3 | Tables re-fit when the window is resized | At 90% zoom, drag the browser window narrower until columns fold behind ▶, then wider again. | Columns fold and unfold smoothly. Clicking ▶ shows the hidden values. No error. | | |
| ☐ | R4 | Nothing changes at 100% | At 100% zoom, open the Investments list and one other list page. | They look and behave exactly as they did before this release. | | |
| ☐ | R5 | The 90% behaviour that #1745 added still works | At 90% zoom on a table that fits the screen | No column, including the actions column, is folded behind ▶. | | |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Dates on any screen the fix touched | N/A. The fix doesn't change how dates are shown. | N/A | |
| ☐ | C2 | Dates in any email the fix touched | N/A. No emails are involved. | N/A | |
| ☐ | C3 | Narrow / mobile width | On a phone, or in DevTools device mode on an iPhone preset (which uses a fractional zoom), the Investments list loads with no `forEach` error. Data columns fold behind ▶ and the buttons can be reached. | | |
| ☐ | C4 | Tenant isolation | N/A. This is a browser-only display fix that doesn't change which data is loaded. | N/A | |
| ☐ | C5 | Screens the fix touched | Covered by H1, H2, R1–R5 (all data-table list pages). | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
