## 1. CSS

- [x] 1.1 Add `td.action-col { white-space: nowrap; }` to `app/assets/stylesheets/custom/responsive_table.scss`. Verify: the investments index action buttons stay on one line in a narrow window.

## 2. DataTable controller

- [x] 2.1 Add `patchResponsiveZoomTolerance()`: patch `Responsive.prototype._columnsVisiblity` once, reducing each column's `minWidth` by 2px only at a fractional `devicePixelRatio` and restoring it afterwards. Verify: at 90% zoom the investments index keeps every column; at 100% the behaviour is unchanged.
- [x] 2.2 Set `data-priority="1"` on `thead th.action-col` without a priority before init. Verify: at 110% zoom data columns fold first and Show / Edit stay visible.
- [x] 2.3 Add `scheduleRelayout(dt)`: `columns.adjust()` and `responsive.recalc()` on the next frame, on `document.fonts.ready` and on window `load`, plus a shared `ResizeObserver` on the controller element that runs once per width change. Verify: toggling the sidebar re-lays out the table without a reload.
- [x] 2.4 Add `disconnect()` to release the `ResizeObserver`. Verify: no observer callbacks run after Turbo navigates away (DevTools).

## 3. Verification

- [ ] 3.1 Manual check on Windows Chrome at 90%, 100% and 110% zoom with a cold cache (DevTools "Disable cache"): the investments index shows the Show / Edit buttons on one line with nothing folded unnecessarily. Automated Cucumber/Playwright coverage is not practical because the fault depends on OS zoom and cold-load timing.
- [ ] 3.2 Spot-check another `datatable` table with an action column (e.g. the investors list) for the same behaviour.
