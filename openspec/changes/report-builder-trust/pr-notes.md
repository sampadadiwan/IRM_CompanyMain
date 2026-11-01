# PR notes — Report Builder you can trust (draft for the PR body)

Phase 1 of `docs/modules/reports/report_builder_usability_plan.md`. Design: `openspec/changes/report-builder-trust/design.md`.

## What changes

- Related data that came out blank now has values: parent and one-to-one records (a commitment's fund, a payment's call), data two steps away (an investor's funds through their commitments), and polymorphic documents (only the record's own).
- Columns the grids show through decorators ("Investing Entity", "Instrument", KPI "For"/"User", KYC "Expired") show plain-text values; filter-only fields are offered as filters, not columns.
- Every related column gets a default total by type, saved when added and applied to older reports; unknown totals are refused (422). The wizard's Summarize step saves the "Sum" it shows.
- Formulas run on plain numbers; formula and pivot columns keep their dragged position; pivot headers name their related data; new "Only … that have …" switch per related data.
- One formatter for preview, report page and Excel (Indian grouping for INR); a totals row everywhere (formulas recalculated from totals); sortable headers on the report page; the report name on the Reports list opens the report page.
- Builder save messages are truthful (green only on success, red with the reason and the control reverted); Apply Template asks first with the Immediate Actions popup.

**BREAKING (minor):** Excel exports no longer have a separate "Totals" sheet — totals are the bold last row of the "Data" sheet.

## Bugs found and fixed while building

- The report page ignored `per_page`: Pagy 9 takes `limit:` and silently ignores the old `items:`, so every report page showed 20 rows instead of 100.
- Aggregators built model objects from a partial `SELECT`; `Document`'s `after_initialize` read an unselected column, the error was swallowed and document columns came out blank. Aggregates are now read as plain rows (also lighter on large tables).

## Deploy and rollback

- Code only — no migrations, no feature flag, no cron changes.
- **Rollback:** formula and pivot positions are new `grid_view_preferences` rows with keys starting `formula:` / `pivot:`. The previous code would show them as blank columns, so on revert delete them:
  `GridViewPreference.where(owner_type: "Report").where("`key` LIKE 'formula:%' OR `key` LIKE 'pivot:%'").delete_all`

## Tests

`features/core/report_builder/` — 154 scenarios (all 64 worked examples H/E/X tagged one-to-one), including the `@javascript` `builder_ui.feature`. User guide lint passes. RuboCop clean on every touched file.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
