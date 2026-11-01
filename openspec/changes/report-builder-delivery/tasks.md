# Tasks — Report Builder delivery

## 1. Export progress and recent exports (design ①②③, LLD §1, §4, §7)

- [x] 1.1 Add `_export_button` partial and `report_export_controller.js`; use them on the report page and builder header; remove `startExport`/`exportBtn` — verify the page renders the button with id `rb_export_<id>`
- [x] 1.2 `download` answers turbo-stream requests with an empty stream (idle button on enqueue error) — verify the HTML redirect is unchanged
- [x] 1.3 `ReportBuilderRecentExports` + `_recent_exports` partial on the report page — verify the list renders for a report with exports
- [x] 1.4 Export job: `test_send` argument, broadcasts of ① and ③ for non-scheduled runs, reworded failure alert with idle button, `last_run_at` after a scheduled mail — verify `scheduling.feature` and `mailer.feature` stay green
- [x] 1.5 Write `features/core/report_builder/delivery_export.feature` (H1, H2, H3, E1, E2, X1) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/delivery_export.feature` until green before phase 2

## 2. Schedule (design ④⑤, LLD §2, §3, §5)

- [x] 2.1 `ReportScheduleRecipients` — verify via the phase's feature
- [x] 2.2 `ReportBuilder::Delivery` concern: `update_schedule` (moved, with checks and time zone), `schedule_check`, `schedule_test`; routes — verify `bin/rails routes | grep schedule`
- [x] 2.3 Helper wording (`report_schedule_label`, `report_schedule_history`, frequency options, outsider summary) and the rewritten `_tab_delivery` — verify the tab renders
- [x] 2.4 `saveSchedule` / `toggleSchedule` in `report_builder_controller.js` with the hidden form and `confirm#popup`
- [x] 2.5 Write `features/core/report_builder/delivery_schedule.feature` (H4–H8, E3–E7, X2–X5) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/delivery_schedule.feature` until green before phase 3

## 3. Reading and Save as View (design ⑥⑦⑧, LLD §1, §2)

- [x] 3.1 Extract `_filter_value_input` from `_filter_row` — verify `editor_filters.feature` stays green
- [x] 3.2 `ReportBuilderReaderFilters`, `_view_filters` (saved chips, reader chips, Narrow down), `report_view_filter_controller.js`; `view` merges `nf/nop/nv` and passes `applied` to the engine — verify by the phase's feature
- [x] 3.3 `_headline_totals` with `NumberStatsComponent` — verify by the phase's feature
- [x] 3.4 Remove Save as View: action, route, JS handlers and value, `edit.html.erb` attribute, `WithReportBuilderViews` — verify `grep -rn "view_settings\|WithReportBuilderViews" app config` is empty
- [x] 3.5 Write `features/core/report_builder/delivery_reading.feature` (H9–H12, E8–E14) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/delivery_reading.feature` until green before phase 4

## 4. Docs and full run

- [x] 4.1 Update `docs/user_guides/report_builder_user_guide.md` (Exporting, Scheduling, Reading a report, FAQs) — verify `features/user_guide_lint.feature` is green
- [x] 4.2 RuboCop on touched Ruby files; screenshots of the report page, Delivery tab, popup and export states reviewed against the UI checklist
- [x] 4.3 Run all of `features/core/report_builder/` with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/` until green; check every H/E/X ID is tagged exactly once
- [ ] 4.4 QA: run qa-checklist.md on a deployed build and record the sign-off (QA, not the apply agent)
