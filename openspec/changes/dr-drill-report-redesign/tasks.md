# Tasks

> Each phase ends with UI review, N+1 check and a green Cucumber run before the next starts.
> Every run: fresh `TEST_ENV_NUMBER`, Redis on 6379, background + `wait $pid`.

## 1. Catalog and model

- [x] 1.1 `lib/dr/report_catalog.rb`: `GROUPS`, `STEPS` (9), `CHECKS` (every `dr:verify` label incl. drill-only and the new search/backup checks) with name, group, proves/does, if_fails, optional `keep_suffix`; `OTHER`; `check(label)`, `step(title)`. Help texts from the approved mock. Verify: `bin/rails runner 'p Dr::ReportCatalog.check("Primary mysqld (10.0.3.88)")'` shows the Database servers entry and "Primary MySQL (10.0.3.88)".
- [x] 1.2 `lib/dr/report_model.rb`: `build(**kw)` → `Model` per lld.md (tiles, plain words, attention merge, steps with pct, groups, scope, evidence, glossary). Verify: runner with the 1039 figures gives tiles `44 / 46`, 1 attention item.
- [x] 1.3 UI review: no screens in this phase. N+1 check: not applicable — no queries.
- [x] 1.4 Write `features/misc/dr_drill_report.feature` + steps for H1, H2, H3, E1, E2, E3, E4, E5, E6, X1, X2, X4 (model and catalog), and run it green.

## 2. Renderers and writer

- [x] 2.1 `lib/tasks/dr_report/report.html.erb` (from the approved mock: light only, inline CSS and icons, `<details>` help, everything escaped) and `report.md.erb` (same sections; help as bullets); `lib/dr/report_render.rb` (`html`, `markdown`). Verify: render the 1039 model to `tmp/dr_report_mock/rendered.html` and screenshot beside the mock.
- [x] 2.2 `AwsUtils#write_dr_report`: build the model once, write both renderers' output; delete `write_dr_report_html` and `DR_REPORT_CSS`; pass `drill`, `teardown`, `executed_by`. Verify: `ruby -c`; `grep -n write_dr_report_html lib` is empty.
- [x] 2.3 UI review: screenshot the rendered HTML in dark-OS mode beside the mock; fix differences. N+1 check: not applicable — no queries.
- [x] 2.4 Add H4, H5, X3 to `features/misc/dr_drill_report.feature` (HTML light, no external URLs; MD same section order; escaping) and run the whole feature green, together with the three other DR features.

- [x] 2.5 (2026-11-08, user: "the report does not talk about RPO, RTO") Recovery point read from the restore's backup chain (`AwsUtils#parse_recovery_point`); `Dr::ReportCatalog::PROMISES` (security questionnaire H3/H4: RPO 30 min, RTO ~10 min); new section "Recovery point and time vs what we promise clients"; tiles labelled RTO / RPO; missed promises in Needs attention and plain words. Feature rows H6, E7, E8, X5.

## 3. Docs and cleanup

- [x] 3.1 `dr_guide.md` §7 and `dr_drills.md` header: describe the report's sections; `gap_review_2026_11.md` G22 fixed in code. Verify: mermaid lint passes.
- [x] 3.2 `bundle exec rubocop` on new files plus changed lines: clean.
- [x] 3.3 UI review: done in 2.3. N+1 check: not applicable.
- [x] 3.4 Run all four DR features green. The real report is checked in the batch staging drill (qa-checklist).
