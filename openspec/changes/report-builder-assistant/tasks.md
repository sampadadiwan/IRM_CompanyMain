# Tasks — Report Builder assistant

## 1. Drafting (design ①–⑥, LLD §1–§7)

- [x] 1.1 `ReportSpecApplier` `replace:` option — verify `templates.feature` and `duplicate.feature` stay green
- [x] 1.2 `ReportSpecPruner` — verify via the phase feature
- [x] 1.3 `ReportDraftGenerator` (two steps, parse, retry, `available?`) — verify via the phase feature with the stubbed AI
- [x] 1.4 `ReportDraftJob`, draft privacy in `ReportPolicy`, `ReportBuilder::Assistant` actions, routes, Describe page, draft page, New report menu, Draft badge — verify the pages render
- [x] 1.5 `ReportDraftCleanupJob` + sidekiq-cron entry — verify via the phase feature
- [x] 1.6 Write `features/core/report_builder/assistant.feature` (H1–H4, H6, H9, E1–E5, E7–E10, X1–X7) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/assistant.feature` until green before phase 2

## 2. Charts (design ⑧)

- [x] 2.1 `ReportBuilderChartSuggestion`; chart section on the draft page (type, No chart, Describe a chart); `template.chart`
- [x] 2.2 Chart above the table on the report page with Hide chart
- [x] 2.3 Write `features/core/report_builder/assistant_chart.feature` (H5, H7, H8, E6, E11, E12) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/assistant_chart.feature` until green before phase 3

## 3. Docs and full run

- [x] 3.1 User guide: Describe it section and FAQs — verify `features/core/user_guide_lint.feature` is green
- [x] 3.2 RuboCop on touched Ruby files; screenshots of Describe, draft page and report chart reviewed
- [x] 3.3 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/ features/core/user_guide_lint.feature` until green; every H/E/X ID tagged exactly once
- [ ] 3.4 QA: run qa-checklist.md on a deployed build and record the sign-off (QA, not the apply agent)
