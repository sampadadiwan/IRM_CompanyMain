# DataTable Action Column Layout

## Why

On the investments index, and other tables using the `datatable` Stimulus controller, the row
action buttons (Show / Edit / ...) could render badly on the first load:

- The buttons stacked on top of each other in a column that was too narrow.
- The whole action column was folded into the expandable ▶ child row.

Reloading fixed it. It was mostly seen on Windows at fractional browser zoom (90%, 110%). Two
causes:

- **Measured too early.** DataTables measures column widths once, at init. On a cold load that
  can happen before web fonts, stylesheets and the sidebar have settled.
- **Rounding at fractional zoom.** DataTables Responsive adds up each column's minimum width,
  rounded to whole pixels, and compares the sum to the container width. At a fractional
  `devicePixelRatio`, the rounding across ~10 columns can make a table that fits look too
  wide. Responsive then collapses the last column, which is the action column.

## What Changes

- **Action buttons stay on one line.** `td.action-col` gets `white-space: nowrap`, so the
  column's minimum width always fits all of its buttons.
- **The action column collapses last.** Before a table is initialised, its `th.action-col`
  gets `data-priority="1"` unless it already has a priority. Data columns then fold into the
  child row first.
- **Zoom tolerance.** Responsive's column-visibility check is patched once, globally. When
  `window.devicePixelRatio` is not a whole number, each column's minimum width is reduced by
  2px while the check runs, then restored. At whole-number ratios the original check runs
  unchanged.
- **Re-measure after layout settles.** After init, each table re-runs `columns.adjust()` and
  `responsive.recalc()`:
  - on the next animation frame
  - when web fonts are ready
  - on window `load`, if the page is still loading
  - when the controller element's width changes (`ResizeObserver`, one recalculation per frame)
- **Cleanup.** The observer is disconnected when the controller disconnects.

## Capabilities

### New Capabilities
- `ui/datatable-layout`: how tables managed by the `datatable` Stimulus controller keep their
  row action column visible and on one line.

### Modified Capabilities

(none — `openspec/specs/` has no UI specs yet)

## Impact

- **JavaScript:** `app/javascript/controllers/datatable_controller.js` (global Responsive patch,
  action column priority, relayout scheduling, `disconnect`).
- **CSS:** `app/assets/stylesheets/custom/responsive_table.scss` (`td.action-col` nowrap).
- **Scope:** every table using the `datatable` controller with an `action-col` column, not only
  the investments index. Tables that already set `data-priority` on the action column keep it.
- **Tests:** none automated. The fault depends on the OS, browser zoom and a cold cache, which
  the headless Cucumber/Playwright runs don't reproduce. Verified by hand (see tasks).
