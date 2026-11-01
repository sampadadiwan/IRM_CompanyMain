# Report Builder delivery — Low-level design

> **Audience:** Reviewing developer. Additive to [design.md](design.md); worked examples in [business-rules.md](business-rules.md).

## Contents

- [1. Files](#1-files)
- [2. Method contracts](#2-method-contracts)
- [3. Routes and controller](#3-routes-and-controller)
- [4. Streams and DOM ids](#4-streams-and-dom-ids)
- [5. Messages](#5-messages)
- [6. Schema](#6-schema)
- [7. Jobs](#7-jobs)
- [8. Front end](#8-front-end)
- [9. Tests](#9-tests)
- [Project rules checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

## 1. Files

| File | New / changed | Box |
|---|---|---|
| `app/packs/core/base/models/report_schedule_recipients.rb` | New | ⑤ |
| `app/packs/core/base/models/report_builder_reader_filters.rb` | New | ⑥ |
| `app/packs/core/base/models/report_builder_recent_exports.rb` | New | ③ |
| `app/packs/core/base/controllers/concerns/report_builder/delivery.rb` | New concern: `update_schedule`, `schedule_check`, `schedule_test` (moved out of the controller) | ④ |
| `app/packs/core/base/controllers/report_builder_controller.rb` | `download` turbo-stream branch; `view` reader filters + `nf/nop/nv` redirect; `update_view_settings` and `update_schedule` removed (schedule moved to the concern) | ①⑥⑧ |
| `app/packs/core/base/jobs/report_builder_export_job.rb` | `test_send`, broadcasts, `last_run_at`, failure wording | ② |
| `app/packs/core/base/helpers/report_builder_helper.rb` | `report_schedule_label`, `report_schedule_history`, `schedule_frequency_options`, `schedule_outsiders_summary` | ④ |
| `app/packs/core/base/views/report_builder/_export_button.html.erb` | New | ① |
| `app/packs/core/base/views/report_builder/_recent_exports.html.erb` | New | ③ |
| `app/packs/core/base/views/report_builder/_view_filters.html.erb` | New (chips + Narrow down) | ⑥ |
| `app/packs/core/base/views/report_builder/_filter_value_input.html.erb` | New, extracted from `_filter_row` | ⑥ |
| `app/packs/core/base/views/report_builder/_headline_totals.html.erb` | New | ⑦ |
| `app/packs/core/base/views/report_builder/_tab_delivery.html.erb` | Rewritten | ④ |
| `app/packs/core/base/views/report_builder/view.html.erb`, `_builder_header.html.erb`, `edit.html.erb`, `_filter_row.html.erb` | Changed | ①⑥⑦⑧ |
| `app/javascript/controllers/report_export_controller.js` | New | ① |
| `app/javascript/controllers/report_view_filter_controller.js` | New: submit on field change | ⑥ |
| `app/javascript/controllers/report_builder_controller.js` | `saveSchedule`, `toggleSchedule`; removed `startExport`, view handlers | ④⑧ |
| `app/packs/core/base/controllers/concerns/with_report_builder_views.rb` | Deleted | ⑧ |
| `config/routes/core.rb` | + `schedule_check`, `schedule_test`; − `view_settings` | ④⑧ |
| `docs/user_guides/report_builder_user_guide.md` | Exporting, Scheduling, Reading sections + FAQs | — |

**Reviewer checks**
- [ ] No change to `ReportSchedule`, `Report`, `Document` or `User` models.
- [ ] `with_report_builder_views.rb` has no remaining references (`grep -rn WithReportBuilderViews app`).

## 2. Method contracts

| Signature | Returns | Notes |
|---|---|---|
| `ReportScheduleRecipients.new(text, entity:)` | — | `text` String or Array |
| `#emails` | `Array<String>` | `text.to_s.split(/[\s,;]+/)`, `strip.downcase`, `compact_blank.uniq` |
| `#invalid` | `Array<String>` | not `URI::MailTo::EMAIL_REGEXP` or domain without `.` |
| `#outsiders` | `Array<String>` | valid emails with no `User` of `entity` (one `pluck`, `LOWER(email) IN (?)`) |
| `#error` | `String \| nil` | blank → "Add at least one email"; 1 invalid → "x isn't an email address"; n → "x and y aren't email addresses" (`to_sentence`) |
| `ReportBuilderReaderFilters.new(config:, entity:, q:)` | — | `q` may be nil / `ActionController::Parameters` |
| `#applied` | `Hash{String=>String\|Array}` | passed to the engine as `external_filters` |
| `#chips` | `Array<{text:, key:}>` | `ReportBuilderFilterField.describe` |
| `#dropped` | `Array<String>` | "Category is already set by the report" |
| `ReportBuilderRecentExports.for(report, user, limit: 5)` | `Array<Document>` | see design ③ |
| `report_schedule_label(schedule)` | "weekly on Monday at 09:00 IST" | zone abbr = `ActiveSupport::TimeZone[tz].now.strftime("%Z")` |
| `report_schedule_history(schedule)` | "Last sent 02 Nov 2026 09:00 IST · Next 09 Nov 2026 09:00 IST" | `l(t.in_time_zone(tz), format: :abbr_date_time)` |

**Reviewer checks**
- [ ] `emails` keeps input order (first occurrence wins), so messages list addresses as typed.
- [ ] `applied` never contains a key whose field is in `config.root_filters`' fields.

## 3. Routes and controller

| Route | Action | `authorize` | `set_report` | `drop_undo` |
|---|---|---|---|---|
| `post ':id/schedule_check'` | `schedule_check` | `update?` | yes | no |
| `post ':id/schedule_test'` | `schedule_test` | `update?` | yes | no |
| `patch ':id/schedule'` | `update_schedule` (now in `ReportBuilder::Delivery`) | `update?` | yes | no |
| ~~`patch ':id/view_settings'`~~ | removed | — | — | — |

`update_schedule` order: `enabled == "false"` → disable (if persisted) and answer "Schedule turned off" → else `ReportScheduleRecipients` → `error` → 422 → `outsiders.any? && outsiders_ok != "1"` → 422 → save with `timezone` (permitted only if in `CURATED_TIMEZONES`, else keep current / `Asia/Kolkata`).

On refusal in a builder request: `@schedule_draft = { recipients:, frequency:, timezone:, error: }` so `_tab_delivery` re-renders what was typed.

**Reviewer checks**
- [ ] A non-builder PATCH still gets JSON (`{ ok: true }` / `{ errors: [...] }`).
- [ ] An unknown time zone can't be stored (validation in `Schedulable` would also reject it).

## 4. Streams and DOM ids

| DOM id | Replaced by | Partial / locals |
|---|---|---|
| `rb_export_<report.id>` | job (ready / idle), `download` (idle on enqueue error) | `_export_button` `report:, state:, document:, size:` |
| `rb_recent_exports_<report.id>` | job (non-scheduled runs) | `_recent_exports` `report:, user:` |

Stream: `"user_alert_#{user.id}"` via `Turbo::StreamsChannel.broadcast_replace_to`. Both the page and the header render `_export_button` with the same id; only one is on any page.

**Reviewer checks**
- [ ] Broadcast partials don't touch `current_user` or `params` (rendered outside a request).

## 5. Messages

| Where | Text |
|---|---|
| Save ok | "Schedule saved — weekly on Monday at 09:00 IST to 2 people" (`pluralize`) |
| Off | "Schedule turned off" |
| Invalid / empty | "Schedule wasn't saved — <error>" (toast) and `<error>` under the field |
| Outsider unconfirmed | "Confirm sending to people outside <entity name> first" |
| Popup cards | red `ti-mail-forward` "Emails N person/people outside <entity>" / the addresses · grey `ti-calendar-event` "<label>" / "Sends the full report as Excel" |
| Test | "A test is on its way to <email>" (toast); alert "A test of <b>name</b> was emailed to <email>" |
| Export failed | alert "Couldn't export <b>name</b>: <message>" |
| Recent exports empty | "No exports yet — Export XLSX makes one." |
| Narrow down note | "Doesn't change the report or its export" |
| Never sent | "Not sent yet · Next …" |

## 6. Schema

N/A — no migrations. Columns listed in [design § Data model](design.md#data-model-and-schema-changes).

## 7. Jobs

| Decision | Value |
|---|---|
| Argument | `perform(report_id, user_id, schedule_id = nil, test_send: false)` |
| Retry | Unchanged (job rescues and alerts) |
| `last_run_at` | `update_columns` after `deliver_now`, scheduled runs only |
| Broadcast | When `schedule.nil?` (on-demand and test) |

**Reviewer checks**
- [ ] Failure broadcast also happens when `report` is nil? No: skip the button replace when `report` couldn't be loaded.

## 8. Front end

| Controller | Action | Behaviour |
|---|---|---|
| `report-export` | `prepare` | `classList.add("disabled")`, `aria-disabled`, inner HTML spinner + "Preparing…"; ignores a second click |
| `report-view-filter` | `pick` | `this.element.requestSubmit()` on field change (no `apply`) |
| `report-builder` | `saveSchedule` | `fetch(schedule_check)` with CSRF → field error / popup / `requestSubmit()` |
| `report-builder` | `toggleSchedule` | show/hide; off + persisted → submit hidden form with `enabled=false` |

**Reviewer checks**
- [ ] `prepare` doesn't `preventDefault` (Turbo must still send the GET).

## 9. Tests

| Feature | Scenarios | Notes |
|---|---|---|
| `delivery_export.feature` | H1, H2, H3, E1, E2, X1 | `@javascript` for stream rows |
| `delivery_schedule.feature` | H4–H8, E3–E7, X2–X5 | `@javascript` for popup rows |
| `delivery_reading.feature` | H9–H12, E8–E14 | rack |

## Project rules checklist

| Rule | Applies | How |
|---|---|---|
| Large-table hygiene | Applies | No new row queries; value lists via `ReportBuilderFilterField` |
| Date formatting (`l(...)`) | Applies | `abbr_date_time` |
| Tenant scoping | Applies | `set_report` entity scope; recipients vs the report's entity |
| MySQL `DISTINCT` / order | N/A | No new DISTINCT |
| MCP ontology | N/A | No MCP changes |
| Cucumber only | Applies | Three features |
| Reuse UI styling | Applies | `NumberStatsComponent`, badges, Immediate Actions |
| No model changes | Applies | Additive classes only |

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
