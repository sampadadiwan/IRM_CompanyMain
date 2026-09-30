# Design

## Context

See proposal.md for motivation and `specs/ui/datatable-layout/spec.md` for requirements. Current
state this design builds on:

- **`datatable` Stimulus controller** (`app/javascript/controllers/datatable_controller.js`):
  `connect()` walks every `.jqDataTable` on the page (a page-global selector, not scoped to the
  controller's element), skips any that `$.fn.dataTable.isDataTable` already reports as
  initialised, and calls `.DataTable({ responsive, ... })` on the rest. `responsive()` returns
  `{ details: ... }` unless the element opts out with `data-datatable-responsive-value="false"`
  (e.g. the deals screen), in which case Responsive is off for that table. Tables are destroyed
  on `turbo:before-cache`. Before this change the controller had no `disconnect()`.
- **DataTables versions:** the `modernize` layout loads DataTables 2.0.2 and Responsive 3.0.0,
  both pinned CDN URLs. The older `application` layout loads DataTables 1.13.7 without Responsive.
- **How Responsive picks columns to hide:** at init and on window resize, Responsive measures each
  column's minimum width (`s.columns[i].minWidth`, read from `offsetWidth`, so rounded to a whole
  pixel). `_columnsVisiblity(breakpoint)` then sums these in priority order and hides columns,
  lowest priority first, until the sum fits the container. Columns without `data-priority` are
  ranked right-to-left, so the last column (in our views, the Show / Edit `action-col`) is hidden
  first.
- **Action column markup:** index views mark the actions cell `td.action-col` and its header
  `th.action-col`. `responsive_table.scss` did not constrain wrapping, so a column sized too
  narrow stacked its buttons vertically.
- **Constraints:**
  - Tests are Cucumber only (see AGENTS.md); no RSpec.
  - The fault needs a real OS zoom level and a cold cache, which the headless Cucumber/Playwright
    runs don't reproduce (see Risks).

## Goals / Non-Goals

**Goals:**
- The row actions on the investments index, and on every other `datatable` table with an
  `action-col`, render on one line and stay visible on first load, without a reload.
- Tables that already fit at 100% zoom behave exactly as before, so there is no regression on
  the common setup.
- A single fix in the shared controller and stylesheet, not per-view workarounds.

**Non-Goals:**
- Upgrading DataTables or Responsive, or merging the two layouts' DataTables versions.
- Scoping `connect()`'s `$('.jqDataTable')` sweep to the controller's own element. This is a
  pre-existing behaviour that D5 has to work around, not something this change fixes.
- Fixing other pre-existing issues in `connect()`: the `turbo:before-cache` handler is
  re-registered on every connect, and `table.search(...)` is called on the `table` object map
  rather than on a DataTable instance.
- Making tables without an `action-col` keep any particular column visible.

## Decisions

All five landed in a single commit, `f51623d395` "Updated with fix for investments index table
rendering btns in multi line on initial load". The two symptoms have two separate causes
(proposal.md, Why). D1 and D2 limit the damage whichever cause is at work. D3 fixes the rounding
cause and D4 fixes the measured-too-early cause. D5 is how D4 is wired up.

### D1. `td.action-col { white-space: nowrap; }`

The narrowest the action column can be is now the width of all its buttons on one line. When
DataTables measures the column too early (D4's cause), Responsive can no longer make it narrow
enough for the buttons to stack. It has to either give the column its full width or hide it.

- **Why CSS rather than a fixed `columnDefs` width:** the number and labels of the buttons differ
  per view and per locale. `nowrap` gets the right width from the actual
  content, with nothing to keep in sync.
- **Trade-off:** since the column can no longer be squeezed, Responsive is a little more likely
  to hide it. D2 makes sure data columns are hidden before it.

### D2. The action column gets `data-priority="1"` unless it already has one

Before `.DataTable(...)`, `thead th.action-col:not([data-priority])` gets `data-priority="1"`.
Responsive hides the lowest priority (highest number) first, and unranked columns rank after
ranked ones. So all data columns are now hidden before the action column.

- **Why set the attribute in JS rather than add it to every view:** every `datatable` table gets
  it with no view edits, and it can't be forgotten on new tables. The `:not([data-priority])`
  guard means a view that deliberately ranks its action column keeps its own value.
- **Why the header rather than `columnDefs.responsivePriority`:** the controller doesn't know the
  action column's index (it is last by convention, not by contract), and Responsive reads
  `data-priority` straight off the `th`. The class is already on the markup.
- **Effect:** users of narrow tables will now see data columns (usually the rightmost data
  column) move into the ▶ child row where they used to see the actions move there. This is the
  intended behaviour: the actions are how users reach the record, and the data is still in the
  child row.

### D3. A global, fractional-zoom-only patch of `Responsive.prototype._columnsVisiblity`

`patchResponsiveZoomTolerance()` runs from every `connect()` and does nothing after the first
run (`_zoomTolerancePatched` flag on the prototype), or when Responsive isn't loaded. It wraps
`_columnsVisiblity`:

- If `window.devicePixelRatio` is a whole number, it calls the original method unchanged.
- Otherwise it takes 2px off each column's `minWidth` (never going below 1), calls the original
  method, and puts the saved widths back in a `finally`.

Chrome at 90% on Windows gives ratios like 0.9 or 1.125. There, each `offsetWidth` can be up to
about 1px off from the true width. Summed over about 10 columns, that is enough to make a table
that fits appear too wide by a few pixels, so Responsive hides the last column.

- **Why only at fractional ratios:** at whole-number ratios `offsetWidth` rounding is exact, so
  any slack there would only let tables overflow that really don't fit. Checking the ratio keeps
  100%-zoom behaviour identical to before (spec: "100% zoom").
- **Why 2px per column:** it covers rounding in both directions (the column width and the
  container width it is compared with) with some margin. Across a 10-column table the whole slack
  is about 20px, which a `.table-responsive` wrapper can absorb as horizontal scroll. It is a
  constant (`RESPONSIVE_ZOOM_TOLERANCE_PX`) so it can be tuned in one place.
- **Why change the inputs for the duration of the call, rather than copy the method:** the
  original method still makes the decision. Only its inputs change, and only for that call.
  `finally` restores them even if the method throws, so nothing else that reads `minWidth` sees
  the reduced values.
- **Alternative rejected:** CSS `zoom` compensation, or detecting zoom and adding padding to the
  container. Both work around the rounding from outside, would affect tables that fit, and don't
  touch the comparison that actually goes wrong.
- **Cost:** `_columnsVisiblity` is a private method, and its name is misspelled upstream. See
  Risks.

### D4. Re-measure once layout settles, then on every container width change

`scheduleRelayout(dt)` runs `dt.columns.adjust()` followed by `dt.responsive.recalc()` (when
Responsive is on) at each of these points:

1. The next animation frame, after the synchronous init has painted.
2. `document.fonts.ready`. Web fonts change text width, and on a cold load they usually arrive
   after `connect()`.
3. Window `load`, only if `document.readyState` isn't already `complete`. This is when late
   stylesheets and images, which can shift the sidebar and content width, are guaranteed to be
   in.
4. Any change to the controller element's rounded width (`ResizeObserver`). This covers the
   sidebar being toggled and anything else that changes the container's width without
   resizing the window.

Each relayout first checks `isDataTable(dt.table().node())`, so a table that
`turbo:before-cache` has destroyed is skipped rather than throwing.

- **Why several triggers rather than one delay:** there is no single "layout is final" event.
  A `setTimeout` would either be too early on slow cold loads (the case being fixed) or add a
  visible delay on warm ones. Each trigger is cheap, and all of them are idempotent once the
  layout is correct.
- **Why `columns.adjust()` before `responsive.recalc()`:** `recalc` decides visibility from the
  current column widths, so the widths have to be re-measured first.

### D5. One `ResizeObserver` per controller, fanning out to every table it initialised

Because `connect()` sweeps every `.jqDataTable` on the page (Context), one controller instance
can own several tables. `scheduleRelayout` therefore creates the observer lazily (`||=`) and
stores each table's `relayout` in `this.relayoutCallbacks`. On each observed width change it runs
all of them in one `requestAnimationFrame`, cancelling any frame that is still pending.
`disconnect()` disconnects the observer and clears it.

- **Why compare rounded widths:** `relayout` itself can change the height of the controller's
  subtree (for example by showing or hiding child-row toggles). Height-only changes, and sub-pixel
  width jitter, must not trigger another relayout. Otherwise the observer could loop.
- **Why observe `this.element` rather than each table:** the constraint that matters is the width
  of the container the tables sit in. Watching the tables themselves would also fire whenever a
  relayout changes their width, which is the loop the check above guards against.
- **Why one rAF for all callbacks:** during a drag-resize or sidebar animation the observer fires
  on every frame. Batching means at most one relayout per table per frame.

## Risks / Trade-offs

- [D3 patches a private, misspelled Responsive method (`_columnsVisiblity`) and depends on the
  shape of `this.s.columns[i].minWidth`. A Responsive upgrade could rename either one] → the
  Responsive CDN URL is pinned to 3.0.0 in `modernize.html.erb`. If the method is renamed,
  Responsive stops calling it, so the patch quietly does nothing and the 90% zoom bug returns. Anyone bumping Responsive should re-check the 90% zoom case in tasks.md 3.1.
- [D3's 2px/column slack can let a table that is really a few pixels too wide stay unhidden at
  fractional zoom] → the table sits in a `.table-responsive` wrapper, so the worst case is a few
  pixels of horizontal scroll instead of a hidden action column, which is the better failure.
- [D2 changes which column users see move into the child row on every `datatable` table with an
  `action-col`, not only the investments index] → intended (proposal.md, Impact). Views that
  already rank their action column are unaffected by the `:not([data-priority])` guard.
- [`relayoutCallbacks` isn't cleared in `disconnect()`. Stimulus reuses a controller instance if
  its element reconnects, so stale callbacks for destroyed tables can build up across reconnects]
  → each callback bails out on `isDataTable` for a destroyed table, so they are skipped, not run.
  Turbo navigation normally replaces the element (and the instance) anyway. Clearing the array in
  `disconnect()` is a safe follow-up.
- [With two `datatable` controllers on one page, the first one initialises every `.jqDataTable`
  (Context), so the second one's observer never gets any callbacks, and the first one's observer
  only watches its own element] → a table outside the first controller's element still gets the
  one-off relayouts (D4 steps 1-3) and Responsive's own window-resize handling, but not
  container-only resizes. Scoping the sweep to `this.element` is out of scope (Non-Goals).
- [No automated test covers this] → the fault depends on OS zoom, `devicePixelRatio` and cold-load
  timing, which headless Chrome in Cucumber/Playwright doesn't reproduce reliably. Covered by the
  manual checks in tasks.md section 3 instead.

## Migration Plan

1. **Deploy:** one JS file and one SCSS file. No schema, data or config changes. Browsers pick up
   the new assets on their next load.
2. **Rollback:** revert the commit. Nothing else depends on the patch, the injected
   `data-priority`, or the observer.

## Open Questions

- Whether to scope `connect()`'s `$('.jqDataTable')` sweep to `this.element`. That would make D5's
  "one controller, many tables" bookkeeping unnecessary and fix the two-controller gap in Risks,
  but it changes init order on every page that uses the controller. It needs its own change.
- Whether 2px is the right tolerance at more extreme fractional ratios (67%, 80%, 125%, 150%).
  The manual checks in tasks.md cover only 90% / 100% / 110%.
