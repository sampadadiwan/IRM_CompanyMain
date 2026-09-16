# AG Grid Fixed-Layout Guardrails

This codebase now applies three AG Grid fixes from one shared place for grids that use fixed sizing:

1. Scroll stability (Turbo/lazy-frame + AG layout stabilization)
2. First row not hidden behind header
3. Pagination text forced to single-line display

## Where the shared logic lives

- `app/javascript/controllers/base_ag_grid.js`
- `app/javascript/controllers/adhoc_ag_controller.js`
- `app/assets/stylesheets/custom/scaffolds.scss`

## How activation works

The shared controllers automatically enable fixed-layout handling when a grid container has explicit inline fixed sizing (for example `height` or `min-height` set in style attributes).

When enabled, controllers add the class:

- `ag-fixed-layout-managed`

The shared pagination CSS is scoped to this class.

## Styling requirement for all tables and grids

Use stylesheet-driven classes for table/grid presentation and sizing. Do not add inline `style="..."` attributes on table or AG-grid containers for layout/styling.

Required pattern:

1. Add semantic class names in ERB/HTML (example: `deals-grid-scroll-container`, `deals-list-grid`)
2. Define sizing/overflow/visual rules in SCSS files
3. For fixed-layout AG grids styled via CSS (no inline size), add `data-ag-fixed-layout="true"` on the grid container so shared fixed-layout guardrails activate

This keeps table styling consistent, reusable, and reviewable across the platform.

## Optional explicit opt-in (future)

If a grid uses fixed sizing from external CSS (not inline style), set one of these on the AG grid container:

- `data-ag-fixed-layout="true"` (preferred)
- `data-fixed-header-offset="true"` (legacy compatibility)

## Scope safety

These fixes are intentionally scoped to fixed-layout AG grids only. Grids without fixed sizing or explicit opt-in are left unchanged.

## Report Builder Note

`/report_builder/:id/edit` is the configuration UI for generated report output. Its preview currently renders as a standard HTML table, not an AG Grid, so the fixed-layout AG rules do not apply there directly.

The actual AG Grid paths that benefit from this mechanism are the generated table views that render through `BaseAgGrid` or `adhoc_ag_controller`.

For portfolio investments, the `template=index_group` AG-grid path now auto-enables the shared fixed-layout mode so generated report-style grids use the same scroll/header/pagination behavior without needing a per-page hack.

## Example applied in Deals

The Deals investors AG grid now follows this policy:

- Markup uses classes in `app/packs/startups/deals/views/deals/_list_view_grid.html.erb`
- Sizing and overflow are defined in `app/assets/stylesheets/custom/_deals_list_view.scss`
- Fixed-layout shared behavior is enabled with `data-ag-fixed-layout="true"`
