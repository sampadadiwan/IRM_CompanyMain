# Fund Units Pagination — Proposal

> **Audience:** Business team, product, QA, support — non-technical.
> **Companion document:** [Design](design.md)

> **Planning phase — no code changes.** This document proposes and explains the change. Do not
> edit application code while writing it; implementation happens later, in the tasks phase.

---

## Why

The Fund Units list loads every matching unit at once and pages through them in the browser. For an investor, fund or commitment with many units, the page is slow to open and heavy to render. The list is also embedded in the investor, commitment, remittance and distribution-payment screens, so the cost is paid on several screens.

## What Changes

- The Fund Units list shows **one page of units at a time** (25 by default) with a "Showing X-Y of Z" summary and page links underneath.
- Filtering still works as today. Filtering always returns to page 1, and moving between pages keeps the active filters.
- Units are listed by issue date, latest first, by default.
- The same paging applies wherever the list is embedded (investor, commitment, remittance, distribution payment).
- Excel download is unchanged: it still exports **all** matching units, not just the current page.
- The table's built-in browser paging is removed so there is only one set of page controls.
- A **Search** box above the table finds units across **all** pages (not just the page on screen) by unit type, reason and folio id.
- Clicking a **column header** sorts the whole list (all pages), and clicking it again reverses the order.
- The old table's built-in search, sorting and rows-per-page menu are replaced by the above. The rows-per-page menu and the narrow-screen column collapse are not carried over.

### Flow Diagram

Before: all rows are fetched, the browser pages them.

```mermaid
flowchart LR
    A["User opens Fund Units"] --> B["Server loads ALL matching units"]
    B --> C["Browser pages the rows"]
    classDef slow fill:#fdecea,stroke:#c62828,color:#000
    class B slow
```

After: the server sends one page; page links fetch the next.

```mermaid
flowchart LR
    A["User opens Fund Units"] --> B["Server loads one page of 25"]
    B --> C["User clicks page link"]
    C --> D{"Filters active?"}
    D -->|"Yes"| E["Next page, same filters"]
    D -->|"No"| F["Next page"]
    classDef new fill:#e8f5e9,stroke:#2e7d32,color:#000
    class B,E,F new
```

---

## User Stories

### US-1: Browse a long list of fund units

**As a** fund manager,
**I want** the Fund Units list to open quickly and let me page through results,
**So that** large funds and investors do not make the screen slow.

**Acceptance criteria:**

- The list shows at most 25 units per page by default.
- A "Showing X-Y of Z" summary appears below the table whenever there are results, and page links when there is more than one page.
- With 25 units or fewer, the summary is shown and no page links are needed.

### US-2: Page through a filtered list

**As a** fund manager,
**I want** my filters kept when I move between pages,
**So that** I do not lose the narrowed list.

**Acceptance criteria:**

- Applying or changing a filter shows page 1 of the new results.
- Clicking page 2 keeps every active filter.

### US-3: See paged units inside an investor or commitment screen

**As a** user viewing an investor, commitment, remittance or distribution payment,
**I want** the Fund Units section to page in place,
**So that** clicking a page link does not leave the screen I am on.

**Acceptance criteria:**

- Page links update only the Fund Units section.
- The rest of the screen, including other tabs, stays as it was.

### US-5: Search the list

**As a** fund manager,
**I want** to type a few letters and see the matching units,
**So that** I can find a unit without paging through the whole list.

**Acceptance criteria:**

- A Search box sits above the table, in every place the list appears.
- It matches unit type, reason and folio id across all pages.
- The summary counts all matches; page links keep the search; a new search shows page 1.
- Clearing the box shows the full list again.

### US-6: Sort by a column

**As a** fund manager,
**I want** to click a column header to sort,
**So that** I can order units by quantity, date, price and so on.

**Acceptance criteria:**

- Clicking a header sorts all matching units, not only the visible page, and shows page 1.
- Clicking it again reverses the order; an arrow shows the current sort.
- Filters and search stay applied while sorting.
- Without a chosen sort, the list is ordered by latest issue date first.

### US-4: Download everything

**As a** fund manager,
**I want** the Download button to export all matching units,
**So that** paging does not shrink my export.

**Acceptance criteria:**

- The Excel file contains every unit matching the current filters, regardless of the page shown.

---

## UI Behavior

### Fund Units list

```
+------------------------------------------------------------+
| Fund Units                      [Transfer] [Download] [Up]  |
| Filters: [Fund v] [Investor v] ...                          |
| Search: [ Search...                  ]                      |
|                                                             |
| Unit Type^| Folio Id | Issue Date v| Qty | Price | Amount   |
| Class A   | F-001    | 01/04/2025 | 100 | 10.00 | 1,000.00  |
| ...                                                         |
|                                                             |
| Showing 1-25 of 140          < 1 2 3 4 5 6 >                |
+------------------------------------------------------------+
```

**Behavior notes:**

- Page links only update the list area (no full page reload).
- The summary and links are hidden when there are no results.
- Changing a filter, searching, or sorting resets to page 1.
- The arrow next to a header shows the current sort; headers that cannot be sorted show no arrow.
- The Search box submits on Enter and refreshes only the list area.

---

## What This Feature Does NOT Cover

| Excluded                                                           | Covered In                                                                                                                         |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| A rows-per-page menu                                               | Not in this change                                                                                                                 |
| Narrow-screen column collapse (the table scrolls sideways instead) | Not in this change                                                                                                                 |
| The imported-units table on an import upload's page                | Loads the same server-paged list in a lazy frame, like the other models on that page: paging, search and sorting run on the server |
| A user-selectable page size control                                | Not in this change                                                                                                                 |
| Changes to other lists (fund unit settings, ratios, etc.)          | Already paginated or out of scope                                                                                                  |
| Changes to filtering rules or who can see which units              | Unchanged                                                                                                                          |

---

## Validation Rules

| Field                 | Rule                                                                                                                       | Default                  |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| Page                  | Whole number, 1 or more; an out-of-range page falls back to the last page                                                  | 1                        |
| Per page              | Whole number, 1 to 500; anything else uses the default                                                                     | 25                       |
| Search                | Text, matched anywhere in unit type, reason, folio, fund name, investor name, investing entity name; blank means no search | none                     |
| Sort                  | One of the sortable columns, ascending or descending; anything else is ignored                                             | issue date, latest first |
| Excel / "all" request | Never paginated                                                                                                            | -                        |

---

## Behavior Rules

| Scenario                              | What User Sees                                                       |
| ------------------------------------- | -------------------------------------------------------------------- |
| More than 25 matching units           | First 25, summary "Showing 1-25 of N", page links                    |
| 25 or fewer matching units            | All units, summary "Showing N of N", no page links                   |
| No matching units                     | Empty table, no summary or page links                                |
| Click a page link on an embedded list | Only the Fund Units section changes                                  |
| Click Download                        | Excel with all matching units                                        |
| Open the list                         | Latest issue date first; units with the same date keep a fixed order |
| Type in Search and press Enter        | Page 1 of the units matching the text, from all pages                |
| Search with no matches                | Empty table, no summary or page links                                |
| Click a column header                 | All matching units sorted by it, page 1                              |
| Click the same header again           | Order reversed                                                       |
| Search, then click page 2             | Page 2 of the same search                                            |
| Change a filter while on page 3       | Page 1 of the new results                                            |

---

## Resolved Design Decisions

| #   | Decision             | Resolution                                                                                                                                                       |
| --- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Default page size    | 25 per page (confirmed)                                                                                                                                          |
| 1a  | Maximum page size    | A request may ask for up to 500 per page, never more (confirmed)                                                                                                 |
| 1b  | Order                | Latest issue date first, unless the user sorts (confirmed)                                                                                                       |
| 2   | Column sorting       | Included. Header sort links sort the whole matching list on the server (confirmed)                                                                               |
| 2a  | Search               | Included. A Search box searches all matching units on the server across unit type, reason, folio, fund name, investor name and investing entity name (confirmed) |
| 3   | Where paging happens | On the server, so only one page is loaded and drawn                                                                                                              |
| 4   | Excel download       | Remains unpaginated                                                                                                                                              |

---

## Capabilities

### New Capabilities

- `funds/fund-units-list`: How the Fund Units list is paged, searched, sorted, filtered and exported, including its embedded use on investor, commitment, remittance and distribution-payment screens.

### Modified Capabilities

None. No existing capability covers the Fund Units list.

---

## Impact

- The Fund Units list page and its embedded sections on the investor, commitment, remittance and distribution-payment screens.
- No change to who can see units, to the Excel layout, or to other lists.
- Existing Fund Unit scenarios that assume every row is visible may need a paging-aware check.

---

## Benefits

1. The Fund Units list opens faster for large funds and investors.
2. One consistent paging style with other lists in the app.
3. Filters and embedded screens keep working while paging.
4. Exports are unaffected.

---

## FAQ

| Question                                        | Answer                                                                                                                   |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Does paging change which units a user can see?  | No. Access rules are applied before paging.                                                                              |
| Will the Excel download be limited to one page? | No. It exports all matching units.                                                                                       |
| Is anything stored or migrated?                 | No. This is a display change only.                                                                                       |
| Does this affect notifications or billing?      | No.                                                                                                                      |
| Why was the old table search replaced?          | The old search only looked at rows already on screen, which would be 25 after paging. The new search looks at all units. |
| Does sorting cover all pages?                   | Yes. The whole matching list is sorted first, then split into pages.                                                     |
| Can a user choose how many rows per page?       | Not in this change.                                                                                                      |

---

## Design Principle for the Next Phase

Keep the design small: reuse the app's existing paging approach (as in the KPI and access-rights lists) rather than a new component. Two risks need an explicit answer in design: (1) removing the table's browser paging so users do not see two sets of page controls, and (2) page links on the embedded lists targeting the correct section.
