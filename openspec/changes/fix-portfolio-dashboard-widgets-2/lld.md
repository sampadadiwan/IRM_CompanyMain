# Fix Portfolio Dashboard Widgets (second batch) — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **The fund `_stats.html.erb` cache key and defaults.** The fund's Portfolio Investments page shares this template. With all new locals nil, output must equal today's. See [Method Contracts](#method-contracts) and design [card ④⑤](design.md#-company-stats-and--fund-stats).
- **The select2 → Stimulus bridge.** select2 fires jQuery `change`, which native `data-action` listeners don't see. The bridge is bound in `fieldTargetConnected`. See [Method Contracts](#method-contracts).
- **`fields` stays a comma-separated string.** No change to the metadata format; the multi-select joins with `", "`. Design [decision 2](design.md#design-decisions).
- **No-match fallback to default cards** also changes the company widget: today a widget whose fields match nothing renders an empty row. See `stats_cards`.
- **Company Default currency** is one more step in the existing currency choice, validated against `entity.currency_list`. Saved `currency` values start taking effect, so the clean-up script prints them as `REVIEW`. See [Method Contracts › Company](#method-contracts).
- **Run message only for `NoteSummarizerAgent`.** One `if` in `SupportAgentsController#run`'s targeted turbo_stream branch.
- **Clean-up script.** Removes dead keys and prints `REVIEW` for fund-level stats widgets whose saved settings start to take effect. See [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/base/models/dashboard_widget.rb` | Modified | `metadata_help` for Portfolio Stats (×2), Fund Portfolio Stats, Data Card; `LP_STARTER_METADATA`; hint rows for `fields`, `field_names` (stats) and `fields` (Data Card) |
| ① | `app/packs/core/base/helpers/dashboard_widgets_helper.rb` | Modified | `metadata_choices(:stats_fields, _)` |
| ② | `app/packs/core/base/views/dashboard_widgets/_metadata_fields.html.erb` | Modified | Multi-select branch for `field_hint[:multiple]` |
| ② | `app/javascript/controllers/metadata_form_controller.js` | Modified | select2 init, jQuery change bridge, read/restore multiple selects |
| ③ | `app/packs/funds/portfolios/helpers/aggregate_portfolio_investments_helper.rb` | Modified | `stats_cards`, `stats_card_layout` |
| ④ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/_stats_for_portfolio_company.html.erb` | Modified | Cache key; fields through `stats_cards`; layout through `stats_card_layout` |
| ⑤ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/_stats.html.erb` | Modified | New locals; Sold + FMV card; units/decimals; cache key; `stats_cards` and `stats_card_layout` |
| ⑤ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/widgets/_stats.html.erb` | Modified | Pass `field_names`, `per_row` to the fund partial |
| ⑥ | `app/packs/ai/support_agents/services/note_summarizer_agent.rb` | Modified | `self.summary_period`; `initialize_agent` uses it |
| ⑦ | `app/packs/core/notes/views/notes/_index.html.erb` | Modified | Compute period text; pass `period_notice` to the modal |
| ⑦ | `app/packs/ai/support_agents/views/support_agents/_agent_run_modal.html.erb` | Modified | Optional `period_notice` local |
| ⑦ | `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | Modified | Page alert for NoteSummarizerAgent in `run` |
| ⑧ | `app/packs/ai/support_agents/views/support_agents/_note_summary_detail.html.erb` | Modified | Empty-period alert; Period start date with year (`:abbr_month_day_year`) |
| Rollout | `docs/operations/dashboard_widget_metadata_cleanup_2.md` | New | One-off console script (dry run / apply / REVIEW) |
| Docs | `docs/user_guides/dashboard_widgets_user_guide.md` | Modified | Stats Fields picker, fund stats settings, Data Card help, summariser period |
| Tests | `features/core/dashboard_widget_metadata.feature`, `features/step_definitions/dashboard_widget_metadata_steps.rb` | Modified | Form rows |
| Tests | `features/fund/portfolio_stats_widget_settings.feature`, `features/step_definitions/portfolio_stats_widget_settings_steps.rb` | New | Render rows |
| Tests | `features/ai/support_agents/note_summarizer_run_feedback.feature`, `features/ai/support_agents/note_summarizer_run_feedback_steps.rb` | New | Summariser rows |

**Reviewer checks**
- [ ] Every class in the design's [class diagram](design.md#class-diagram) has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout and Packwerk boundaries (the core form helper only reads `PortfolioCompanyStats::FIELDS`; if Packwerk flags `core → funds`, inline the six names in the hint instead)
- [ ] New feature and step file names don't already exist (checked: none do)

---

## Schema Detail

N/A: no tables or columns change.

---

## Method Contracts

**`DashboardWidget`** (Model)

| Method / constant | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `METADATA_FIELD_HINTS["Portfolio Stats"]`, `["Fund Portfolio Stats"]` | — | `{"fields" => {label: "Fields", choices: :stats_fields, multiple: true, hint: "Pick the cards to show, in order."}, "field_names" => {label: "Field names", hint: "List the names in the same order as the Fields you picked, separated by commas. E.g. Bought Amount, Sold Amount, FMV → Buy, Sell, Fair value"}}`, plus optional labels for `force_units` ("Units"), `per_row` ("Cards per row", `integer: true`), `tracking_currency` | — | — | — |
| `METADATA_FIELD_HINTS["Portfolio Stats"]["currency"]` (company only; the Portfolio Dashboard's widget doesn't offer the key) | — | `{label: "Default currency", choices: :entity_currencies, hint: "Order: picked on page > Tracking currency (if ON) > Default currency > firm's currency"}` | — | — | — |
| `METADATA_FIELD_HINTS["Data Card"]` | — | `{"fields" => {label: "Fields", hint: <proposal US-4 text>}}` | — | — | — |
| `.field_hint(widget_name, key)` | unchanged | hash incl. new `:multiple` | — | — | Yes |

**`DashboardWidgetsHelper`** (Helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `metadata_choices(source, entity)` | `:stats_fields`, entity (unused) | `PortfolioCompanyStats::FIELDS.map { [it, it] }` | — | — | Yes |
| `metadata_choices(source, entity)` | `:entity_currencies`, the widget's entity | `entity.currency_list.map { [it, it] }`; `[]` when entity is nil | — | One `exchange_rates.pluck(:from)` query | Yes |

**`AggregatePortfolioInvestmentsHelper`** (Helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `stats_cards(fields, field_names, available:, defaults: available)` | `fields`: `Array<String>` or nil; `field_names`: `Array<String>` or nil; `available`: card names the template can render; `defaults`: names when fields blank or unmatched | `Array<{subtitle: String, label: String}>`, in order | — | — | Yes |
| `stats_card_layout(count, per_row, default_class: "")` | card count; `per_row` (String/Integer/nil, clamped 1..12); class used when `per_row` blank | `[classes Array<String>, styles Array<String>]` | — | — | Yes |

Matching: `available.find { it.casecmp?(field.strip) }`, then `compact.uniq`. Labels: `field_names[i].presence || subtitle`. `stats_card_layout` is the company template's existing block, moved without change. The company template passes its count-based class as `default_class`: it calls the helper once per row size, or keeps its `case` and only delegates the `per_row` branch, whichever keeps the diff smallest.

**`_stats.html.erb` (fund) locals**

| Local | Type | Default | Effect when default |
|---|---|---|---|
| `fields` | `Array<String>` | `nil` | Five cards: Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income |
| `field_names` | `Array<String>` | `nil` | Card names |
| `force_units` | String | `nil` | `fund.default_currency_units` |
| `decimals` | Integer | `nil` | `money_to_currency` default (2) |
| `per_row` | String/Integer | `nil` | No `css_class` on cards (as today) |

Cache key: `cache_key(["api_stats", fund, fields, field_names, force_units, decimals, per_row])`. The widget wrapper currently passes `decimals: args[:decimals]&.to_i || 2`, so an unconfigured widget passes `2`, not nil. Its key therefore differs from the Portfolio Investments page's (`nil`), and both render 2 decimals. Fine.

**Company `_stats_for_portfolio_company.html.erb`**

| Change | Detail |
|---|---|
| Cache key | Add `field_names`, `decimals`, `per_row`, `tracking_currency`, `currency` |
| Default currency | New local `currency` (nil default), passed by `widgets/_stats.html.erb`. Target currency: picked (`params[:display_currency] \|\| params[:currency]`, if in `entity.currency_list`) → tracking (unchanged) → **`currency` if `portfolio_company.entity.currency_list.include?(currency)`** → `entity.currency` |
| Drop-down options | `[base_currency, target_currency, *entity.currency_list].uniq`, with `target_currency` selected: the same list as the metadata editor (E21). `base_currency` is unchanged; it is what the controller falls back to |
| Fields | `matched = stats_cards(fields, field_names, available: PortfolioCompanyStats::FIELDS)`; pass `matched.map { it[:subtitle] }` to `stats.cents` |
| Cards | Built from `matched` order; `subtitle:` = label |

**`NoteSummarizerAgent`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.summary_period(support_agent, today: Time.zone.today)` | `SupportAgent`, `Date` | `{label: "Quarter" \| "Month" \| configured string, start: Date, end: Date}` | — | — | Yes |
| `#initialize_agent` | unchanged | unchanged | unchanged | Sets `ctx[:period_label/start/end]` from `.summary_period` | Yes |

`label` keeps today's value: `json_fields["summary_period"].presence || "Quarter"`. The window text uses `label.downcase` ("quarter"/"month"); any other configured value falls into the quarter branch, as today.

**`metadata_form_controller.js`** (Stimulus)

| Method | Change |
|---|---|
| `fieldTargetConnected(field)` | If `field.multiple`: `initSelect2(field.parentElement)` (import from `custom/select2_handler`) when not yet initialised; restore; bind `$(field).on("change", () => this.debounceUpdate())` |
| `updateMetadata()` | `SELECT` with `multiple`: `Array.from(field.selectedOptions).map(o => o.value)` in DOM order; skip when empty; value joined `", "` (string) |
| `syncFieldFromMetadata(field)` | `multiple`: split saved string on `,`, trim; for each, find the option, set `selected`, append in that order before unselected options; then `$(field).trigger("change.select2")` |

**Reviewer checks**
- [ ] With all fund locals nil, the rendered HTML equals today's, apart from the cache key
- [ ] `stats_cards` never returns an empty list when `defaults` is non-empty
- [ ] `initialize_agent` sets the same three ctx keys and values as before for Month, Quarter and blank
- [ ] The multiple-select value is a string, so `toRubyHash` quotes it and `metadata_must_be_literal` accepts it

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SupportAgentsController#run` (unchanged signature) | unchanged | `authorize @support_agent` with `run_target` (unchanged) | turbo_stream: two progress-panel replaces (unchanged); **plus** for `NoteSummarizerAgent`, `turbo_stream.update("user_alert", partial: "layouts/alerts", locals: { notice: run message })` | unchanged |
| `DashboardWidgetsController#create/update` | unchanged; `metadata` string | unchanged | unchanged | unchanged (`metadata_must_be_literal`) |

The run message is built in the controller from `NoteSummarizerAgent.summary_period(@support_agent)` and `l(period[:end])`.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope` (no new actions)
- [ ] The page alert is added only when `@support_agent.agent_type == "NoteSummarizerAgent"`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `notes/_index` (owner present) | `SupportAgent.find_by(agent_type: "NoteSummarizerAgent", entity_id: current_user.entity_id)` | existing on `support_agents.entity_id` | ≤ 1 | — |
| Fund `_stats` | unchanged sums on `aggregate_portfolio_investments`, `portfolio_investments`, `portfolio_cashflows` | existing | — | Sold + FMV reuses the sold and FMV sums |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by the fund / company
- [ ] No new query runs per card

---

## Transactions, Locking and Concurrency

N/A: no multi-row writes. The summariser's note upsert is unchanged.

---

## Background Jobs

N/A: no new jobs. `SupportAgentJob` arguments unchanged.

---

## External Integrations

N/A: the LLM call in `generate_summary` is unchanged.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Any error computing company stats | `_stats_for_portfolio_company` | existing `rescue → ErrorReport.notify` | existing red alert | unchanged |
| `Date::Error` parsing `period_start/end` in ⑧ | `_note_summary_detail` | guard: show the empty-period alert only when both dates are present | today's behaviour | none |

**Reviewer checks**
- [ ] No new bare `rescue`
- [ ] ⑧ never raises on old reports without period fields

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | No new actions; `run` keeps `authorize` with `run_target` |
| Tenant isolation | Stats remain scoped by fund/company; LP narrowing (`LpPortfolioVisibility`) runs before cards are chosen; agent lookup by `current_user.entity_id` |
| Secrets | None |
| Input / output sanitisation | `field_names` labels rendered by `NumberStatsComponent` with default escaping; period text built from dates; metadata stays literal-only (C1) |
| Mass assignment | Unchanged permitted params |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool (no new routes)
- [ ] An LP's fund stats never include holdings outside their folio, whatever the settings (E7)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None |
| Cron / schedules | None |
| Deploy order | 1) Run `docs/operations/dashboard_widget_metadata_cleanup_2.md` dry run on production; support reviews `REVIEW` lines. 2) Apply. 3) Deploy code |
| Rollback | Revert the code. Removed keys did nothing before, so nothing needs restoring. Cache fragments rebuild |

Clean-up script (same shape as `dashboard_widget_metadata_cleanup.md`, keyed by `[dashboard_name, widget_name]`):

| Dashboard | Widget | Remove | Print `REVIEW` if saved |
|---|---|---|---|
| Portfolio Company Dashboard | Data Card | `cols`, `field_names` | — |
| Portfolio Company Dashboard | Portfolio Stats | — | `currency` (it starts to take effect) |
| Portfolio Dashboard | Portfolio Stats | `currency`, `tracking_currency`, `show_currency_filter` | `fields`, `field_names`, `force_units`, `decimals`, `per_row` |
| Fund Dashboard | Fund Portfolio Stats | `currency`, `tracking_currency`, `show_currency_filter` | `fields`, `field_names`, `force_units`, `decimals`, `per_row` |

`REVIEW` lines also flag saved `fields` that match none of the six cards (case-insensitive), since those will show all cards.

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] The script skips non-literal metadata and verifies the round-trip, as the first script does

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/dashboard_widget_metadata.feature` | `@javascript` for select2 rows (H1, H2, E11, E17, E18) | existing | `When I pick {string} in the multi-select {string}`, `When I remove {string} from the multi-select {string}`, `Then the multi-select {string} should show {string}` (comma list, in order); `When I choose the widget name {string}` if missing |
| `features/fund/portfolio_stats_widget_settings.feature` | Cache on (`Rails.cache` memory store) for H4/E4/E5; USD→INR exchange rates for Golden Angels, reusing the setup in `features/step_definitions/currency_dropdown_steps.rb` where it fits (H13, E19, E20, X3); LP visibility setup reused from `features/funds/lp_portfolio` steps for E7 | `:portfolio_investment`, `:aggregate_portfolio_investment`, fund, investor | `Given the {string} widget on {string} has settings {string}`, `Then the stats cards should read {string}` (label=amount list, in order), `Then the stats cards should be laid out {int} per row` |
| `features/ai/support_agents/note_summarizer_run_feedback.feature` | `travel_to` the scenario date; `allow(LlmService).to receive(:ruby_llm_chat).and_return(chat)` where `chat.ask` returns `double(content: "Two updates.")` or raises (X2); run the agent directly via `NoteSummarizerAgent` / `SupportAgentJob.perform_now` | `:note`, investor; agent via `Given Golden Angels has the "NoteSummarizerAgent" agent "Note Summariser" with chat on` or `there is a support agent` | `Given today is {string}`, `Given notes on {string} dated {string}`, `When the note summariser runs for {string}`, `Then the run window should say {string}`, `Then the Note Summaries entry should show {string}` |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `fields`/`field_names` are arrays, not relations; no relation predicates added |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies (script) | Clean-up script uses `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No account entries read |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Period dates use `l(date, format: :abbr_month_day_year)` ("Jul 01, 2026"), the format ⑧ already uses for the period end; the summary note's date uses `l(date)` ("30/09/2026"), as in the Notes list. No new locale key |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | No new actions; agent lookup by entity |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP surface |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Three feature files above |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on modified Ruby files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
