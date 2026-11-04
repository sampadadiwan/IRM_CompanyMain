# PR notes — Report Builder delivery (draft for the PR body)

Phase 5 of `docs/modules/reports/report_builder_usability_plan.md`. Design: `openspec/changes/report-builder-delivery/design.md`.

## What changes

- **Export progress:** Export XLSX reads *Preparing…* from the click, then **Download** + **Export again** when the job has saved the file, or **Export XLSX** again with "Couldn't export <name>: <reason>" on failure. The job replaces the button over the user's existing alert stream (`user_alert_<id>`), with no new channel.
- **Recent exports** on the report page: the last 5 "Generated" documents of the report that the user may open.
- **Schedule:**
  - one `ReportScheduleRecipients` checker, used before the popup and again on save
  - invalid addresses named under the field
  - an Immediate Actions popup for recipients outside the company; a save that skips the popup is refused (422)
  - time zone picker (new schedules default to IST; old ones keep UTC and say so)
  - **Send test to me**
  - "Last sent … · Next …"
- **Report page:**
  - the report's filters as chips
  - **Narrow down** (root filter fields, typed inputs, reader chips with ✕; saved filters win; export unchanged)
  - up to 4 headline cards equal to the totals row
- **BREAKING (internal):** Save as View removed — `PATCH /report_builder/:id/view_settings`, its JS handlers and the unused `WithReportBuilderViews` concern. The `reports.is_view/view_target/shared` columns stay.

## Found while building

- `ReportBuilderFilterField.describe`, `report_builder_parse_filter` and `ReportSpecValidator` read `category_not_eq` as `category_not` + `eq`, because the first matching suffix won. One `split_predicate` (longest operator first) now serves all three.
- `ransack(root_filters.merge(q))` let a URL `q` replace a saved filter; the report page now drops reader filters on saved fields.
- The scheduler set `last_run_at` at enqueue time; the job now also sets it after the email has gone.

## Deploy and rollback

- No migrations. One job signature gains `test_send:` (keyword, default false; old payloads still run).
- Rollback: revert. Schedules saved in IST keep that time zone, which `NextRunCalculator` already honoured.

## Tests

`delivery_export`, `delivery_schedule`, `delivery_reading`: 31 worked examples (H1–H12, E1–E14, X1–X5), tagged one-to-one. The full `features/core/report_builder/` run and the user guide lint pass.
