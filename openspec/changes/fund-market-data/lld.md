# Fund Market Data — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Business rules](business-rules.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This adds to [design.md](design.md); it links to its boxes
> ①–⑧ and to the H/E/X IDs in [business-rules.md](business-rules.md) rather than repeating them.

> Paths are in the `market-data` worktree (branched from `main`). Files marked **(OEF)** arrive with
> `open-ended-funds` and are touched only in phase 8.

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
  - [Bridge (phase 8) detail](#bridge-phase-8-detail)
- [Test Plumbing](#test-plumbing)
- [Phase 9 Detail — Exposure Limits](#phase-9-detail--exposure-limits)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Pack placement:** `app/packs/funds` depends on `app/packs/core`, never the reverse. Resolvers
  (`SourcePolicy`, `FxRateResolver`, `PriceResolver`) and `MarketDataSetting` live in **core** and take
  the fund as a duck-typed argument (`fund.features`, `fund.entity_id`), so `ExchangeRateShared` and
  `Valuation` (core) can call them. Feeds and derivatives live in **funds**. See [File Map](#file-map).
- **Entity bit reservation:** `enable_evergreen_funds` is appended at bit 35 exactly as on
  `open-ended-funds`, then the three new flags at 36–38. See [Schema Detail](#schema-detail).
- **Six fund booleans → `funds.features`** with a single backfill `UPDATE` and readers switched in the
  same release; columns dropped by a later change. See [Configuration and Rollout](#configuration-and-rollout).
- **`exchange_rates` uniqueness moves to the DB** (`entity_id, from, to, as_of, source`); a pre-check
  query must show zero duplicates before the migration runs. `valuations` keeps a Ruby uniqueness
  (soft delete prevents a DB key).
- **Derived rates are rows** created by `FxRateResolver` with `insert … on duplicate key` semantics and
  never trigger `ensure_latest` jobs. See [Method Contracts](#method-contracts).
- **Fund-specific (owner) rates:** `exchange_rates.owner_type/owner_id` (Fund only in this change;
  null = entity-wide). They are visible only to the owning fund, and only while its
  `use_own_fx_rates` flag is on. They are always `manual`, and the feed never writes them. On the
  same date the tie-break is fund-own manual > entity manual > market > derived. The DB unique key
  can't cover entity-wide rows (MySQL NULLs), so the Ruby validation stays. See
  [Schema Detail](#schema-detail) and [Queries and Indexes](#queries-and-indexes).
- **Feed recompute batching:** feed upserts bypass `Valuation#update_owner`; one
  `PortfolioInvestmentUpdate` per (portfolio company, instrument) after commit. See
  [Background Jobs](#background-jobs).

---

## File Map

| Box | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/entities/models/concerns/entity_enabled.rb` | Modified | Append `enable_evergreen_funds enable_market_rates enable_market_prices enable_derivatives` |
| ① | `app/packs/funds/funds/models/concerns/fund_enabled.rb` | New | `flag :features, %i[… enable_derivatives use_own_fx_rates]` (order fixed, append-only comment), defaults on new records |
| ① | `app/packs/funds/funds/models/fund.rb` | Modified | `include FundEnabled`; `has_one :market_data_setting`; `after_commit` enqueue recompute when rate/price flags change |
| ① | `app/packs/core/entities/models/market_data_setting.rb` | New | Entity row + fund rows; `.for_entity`, `.limits_for` |
| ① | `app/packs/core/entities/policies/market_data_setting_policy.rb` | New | Edit = `EntityPolicy#update?`; show = entity users |
| ① | `app/packs/core/entities/controllers/market_data/settings_controller.rb` | New | show / update / test_feed |
| ① | `app/packs/core/entities/views/market_data/settings/{show,_form,_test_feed_popup}.html.erb` | New | Entity Market Data card, action-summary popup |
| ① | `app/packs/funds/funds/services/fund_feature_guard.rb` | New | Strips flags whose entity feature is off |
| ① | `app/packs/funds/funds/views/funds/_features.html.erb` | New | Features section (visibility, reporting, market data, limits) |
| ① | `app/packs/funds/funds/views/funds/_form.html.erb` | Modified | Renders `_features`; old checkboxes removed |
| ① | `app/packs/funds/funds/controllers/funds_controller.rb` | Modified | `features: []`, `market_data_setting_attributes`; old params removed |
| ① | `app/packs/funds/funds/policies/{fund_policy,fund_ratio_policy,fund_unit_policy}.rb` | Modified | Read `features.*?` / `where_features` |
| ① | `app/packs/funds/portfolios/policies/{portfolio_investment_policy,aggregate_portfolio_investment_policy}.rb` | Modified | Same |
| ① | Views: `funds/_show`, `funds/_show2`, `funds/_investor_fund_details`, `capital_commitments/_card`, `capital_commitments/_investor_details`, `capital_remittances/_details`, `aggregate_portfolio_investments/_index`, `account_entry_reports/_commentary` | Modified | `fund.features.x?` |
| ① | `app/packs/funds/funds/services/import_fund.rb` | Modified | Same two columns → flags |
| ① | `app/packs/funds/dashboards/fund_dashboard.rb`, `app/packs/core/dashboards/entity_dashboard.rb` | Modified | `ActiveFlagField` for `features`; entity flags listed |
| ② | `app/packs/funds/market_data/services/feed_runner.rb` | New | One (entity, kind, provider, date) run |
| ② | `app/packs/funds/market_data/services/pairs_in_use.rb` | New | Distinct currency pairs per entity |
| ② | `app/packs/funds/market_data/providers/{base,ecb,nse_equity,bse_equity,amfi,nse_fo}.rb` | New | `fetch(keys, date)` adapters |
| ② | `app/packs/funds/market_data/jobs/{fx_feed_job,price_feed_job,derivative_expiry_job,fund_fair_value_recompute_job}.rb` | New | Cron / async |
| ② | `app/packs/funds/market_data/models/{market_data_run,corporate_action_suggestion}.rb` | New | Run log; suggestions |
| ② | `app/packs/funds/market_data/mailers/{market_data_ops_notifier,market_data_ops_mailer}.rb` + views | New | Internal emails |
| ② | `app/packs/funds/market_data/controllers/{runs_controller,corporate_action_suggestions_controller}.rb` + views + policies | New | Run history; confirm/dismiss |
| ② | `config/initializers/sidekiq.rb` | Modified | 3 cron entries per region |
| ③ | `app/packs/core/entities/models/concerns/exchange_rate_shared.rb` | Modified | Uniqueness incl. owner + source; `latest` per (owner, pair, source); `get_rate/convert/setup_variable_exchange` delegate to resolver |
| ③ | `app/packs/core/entities/models/exchange_rate.rb` | Modified | Enums, legs, `belongs_to :owner, polymorphic: true, optional: true` (Fund only, validated), owner ⇒ source manual, source/owner-aware `ensure_latest` |
| ③ | `app/packs/core/entities/controllers/exchange_rates_controller.rb` | Modified | Permits `owner_id` (fund); index Fund filter |
| ③ | `app/packs/core/entities/views/exchange_rates/{_form,index,_exchange_rate}.html.erb` | Modified | Optional Fund select (only funds with `use_own_fx_rates`); Fund column + filter |
| ③ | `app/packs/core/entities/policies/exchange_rate_policy.rb` | Modified | create with owner requires `FundPolicy#update?` on that fund |
| ③ | `app/packs/core/entities/models/exchange_rate_sqlite.rb` | Modified | Same columns |
| ③ | `app/packs/core/entities/services/import_exchange_rate.rb` | Modified | Headers fixed (`From, To, Rate, As Of, Notes`, optional `Rate Type`, optional `Fund`); source manual; `Fund` must name a fund of the entity with `use_own_fx_rates` |
| ③ | `app/packs/core/entities/jobs/exchange_rate_portfolio_investment_job.rb` | Modified | Filter funds by source acceptance |
| ③ | `app/packs/core/entities/jobs/exchange_rate_commitment_adjustment_job.rb` | Modified | Manual rates only |
| ③ | `app/packs/core/entities/views/exchange_rates/*` | Modified | Source, Provider, Rate type columns + filter |
| ④ | `app/packs/core/valuations/models/valuation.rb` | Modified | source/provider/price_type; uniqueness incl. source; `per_share_value_in(ccy, date, fund: nil)`; `update_owner` per source; `skip_owner_update` attr |
| ④ | `app/packs/core/valuations/services/import_valuation.rb` | Modified | Optional `Price Type` |
| ④ | `app/packs/funds/portfolios/models/investment_instrument.rb` | Modified | isin/ticker/exchange/pricing_method + validations, ISIN check digit |
| ④ | `app/packs/funds/portfolios/services/portfolio_investment_create.rb` | Modified | Cost-source valuation; line 27 unscoped rate query → resolver |
| ④ | `app/packs/funds/fund_reports/jobs/information_on_investments_job.rb` | Modified | Read `isin` with json fallback |
| ④ | `app/packs/ai/mcp_server/ontology/valuation.yml` | Modified | `source` filter + latest-row note |
| ⑤ | `app/packs/core/entities/services/source_policy.rb` | New | Value object |
| ⑤ | `app/packs/core/entities/services/fx_rate_resolver.rb` | New | Rate resolution, derivation, memo |
| ⑤ | `app/packs/core/valuations/services/price_resolver.rb` | New | Price resolution |
| ⑥ | `app/packs/funds/derivatives/models/{derivative_contract,derivative_event}.rb` | New | Records |
| ⑥ | `app/packs/funds/derivatives/services/{event_recorder,ledger_poster,exerciser,exposure_report,import_derivative_valuation}.rb` | New | Operations |
| ⑥ | `app/packs/funds/derivatives/controllers/{derivative_contracts_controller,derivative_events_controller}.rb` + views | New | UI |
| ⑥ | `app/packs/funds/derivatives/policies/{derivative_contract_policy,derivative_event_policy}.rb` | New | Access |
| ⑦ | `app/packs/funds/funds/models/concerns/with_exchange_rate.rb` | Modified | Pass `SourcePolicy.for(fund)` |
| ⑦ | `app/packs/funds/portfolios/models/concerns/portfolio_computations.rb` | Modified | Price via resolver; price-effect columns |
| ⑦ | `app/packs/funds/portfolios/models/{aggregate_portfolio_investment,aggregate_portfolio_investment_sqlite}.rb` | Modified | `fmv_on_date(date, with_resolution: false)` via resolvers |
| ⑦ | `app/packs/startups/kpis/services/kpi_fx_converter.rb`, `app/packs/core/investors/services/portfolio_company_calc.rb`, `app/packs/funds/portfolios/services/portfolio_investment_as_of_report.rb`, `app/packs/funds/funds/services/fund_ratio_multi_fund_calcs.rb` | Modified | Entity default policy (explicit) |
| ⑧ (OEF) | `app/packs/funds/evergreen/services/{nav_inputs,fund_nav_builder,nav_staleness,fund_nav_approve}.rb` | Modified | Lines, rescue, fingerprint parts, approve guard |
| ⑧ (OEF) | `app/packs/funds/evergreen/services/nav_exceptions.rb` | New | Exceptions |
| ⑧ (OEF) | `app/packs/funds/evergreen/models/{fund_nav,evergreen_fund_setting}.rb` | Modified | `ASSET_LINES`/`LIABILITY_LINES`, `NOTIFICATIONS` key |
| ⑧ (OEF) | `app/packs/funds/evergreen/controllers/evergreen/navs_controller.rb`, `views/evergreen/navs/show.html.erb` | Modified | accept_exception; panel; source/age |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here
- [ ] No file under `app/packs/core` references a constant defined only in `app/packs/funds`
- [ ] `ExchangeRateSqlite` and `AggregatePortfolioInvestmentSqlite` are changed alongside their live twins

---

## Schema Detail

**`entities`** (existing): new feature bits.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `permissions` | Bits 35–38 used | bigint | — | — | unchanged | — | Bit 35 reserved name `enable_evergreen_funds` (same as OEF); 36–38 new features. No migration — bits only |

**`funds`** (existing): flag set.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `features` | Added | bigint | — | no | 0 | — | `active_flag` needs an integer column; bigint leaves room to append |
| six booleans | Unchanged, unused after this release | boolean | — | — | — | — | Rollback safety; dropped by a follow-up change |

**`market_data_settings`** (new): entity feeds/defaults and fund limit overrides.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK, UK part | Tenant |
| `fund_id` | Added | bigint | — | yes | null | FK, UK part | null = entity row |
| `fx_feed_enabled` | Added | boolean | — | no | false | — | Off until admin turns on |
| `fx_providers` | Added | json | — | yes | `[]` | — | Ordered provider keys |
| `price_feed_enabled` | Added | boolean | — | no | false | — | Same |
| `price_providers` | Added | json | — | yes | `[]` | — | Same |
| `pivot_currency` | Added | string | 5 | no | "USD" | — | Matches `exchange_rates.from/to` limit |
| `fund_defaults` | Added | json | — | yes | `{}` | — | Flag names → bool; read on fund create |
| `max_rate_age_days` | Added | integer | — | yes | null | — | null on fund row = entity default; entity row seeded 3 |
| `max_price_age_days` | Added | integer | — | yes | null | — | Same |
| `price_move_threshold_pct` | Added | decimal | 5,2 | yes | null | — | 1.00–100.00 |
| `exposure_limit_multiple` | Added (phase 9) | decimal | 5,2 | yes | null | — | 0.10–10.00; null = no limit |
| `(entity_id, fund_id)` | Added | UK | — | — | — | UK | One row each. MySQL allows many NULL `fund_id`s in a UK → entity-row uniqueness also validated in Ruby |

**`exchange_rates`** (existing, small per entity).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `source` | Added | string | 10 | no | "manual" | UK part | Backfill by default; policy filter |
| `provider` | Added | string | 40 | yes | null | — | Backfill "Upload" where `import_upload_id`, else "User" |
| `rate_type` | Added | string | 10 | no | "reference" | — | Reference/closing |
| `leg1_id`, `leg2_id` | Added | bigint | — | yes | null | index each | Derived legs; find derived rows when a leg changes |
| `owner_type` | Added | string | 20 | yes | null | in UK and owner idx | Polymorphic so portfolio-company rates (L5) need no migration; validated to `"Fund"` in this change |
| `owner_id` | Added | bigint | — | yes | null | in UK and owner idx | Owning fund; null = entity-wide (default, all existing rows) |
| `(entity_id, owner_type, owner_id, from, to, as_of, source)` | New UK | — | — | — | — | UK | One row per owner per source per date. **MySQL treats NULLs as distinct, so the key does not stop duplicate entity-wide rows.** The Ruby `validates_uniqueness_of :as_of, scope: %i[from to entity_id owner_type owner_id source]` stays authoritative for those; the key covers owner rows and acts as the race backstop |
| `(owner_type, owner_id, from, to, as_of)` | New index | — | — | — | — | — | Resolver's fund-own candidate query |
| existing `(entity_id, from, to, as_of desc)` | Kept | — | — | — | — | — | Still used for `latest` |

**`valuations`** (existing, moderate).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `source` | Added | string | 10 | no | "manual" | in idx | manual/market/cost |
| `provider` | Added | string | 40 | yes | null | — | NSE, AMFI, Upload, User, Purchase |
| `price_type` | Added | string | 10 | no | "close" | — | close/bid/mid |
| `idx_latest_valuation` | Changed from `(instrument, deleted_at, synthetic, valuation_date)` to `(instrument, deleted_at, synthetic, source, valuation_date)` | — | — | — | — | — | Resolver filters by source then orders by date |

**`investment_instruments`** (existing).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `isin` | Added | string | 12 | yes | null | `(entity_id, isin)` | ISO 6166 length |
| `ticker` | Added | string | 30 | yes | null | UK part | NSE/NASDAQ symbols ≤ 20; headroom |
| `exchange` | Added | string | 10 | yes | null | UK part | Exchange code |
| `pricing_method` | Added | string | 10 | no | "manual" | — | Backfill by default |
| `(entity_id, exchange, ticker)` | New UK | — | — | — | — | UK | NULL tickers don't collide in MySQL |

**`portfolio_investments`** / **`aggregate_portfolio_investments`** (existing).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `unrealized_price_effect_cents` | Added | decimal | 20,2 | no | 0 | — | Matches existing `*_cents` precision |
| `realized_price_effect_cents` | Added | decimal | 20,2 | no | 0 | — | Same |

**`market_data_runs`** (new).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK, UK part | Tenant |
| `kind` | Added | string | 15 | no | — | UK part | fx / prices / fno / corp_actions |
| `provider` | Added | string | 20 | no | — | UK part | Adapter key |
| `run_date` | Added | date | — | no | — | UK part | Idempotent re-run |
| `status` | Added | string | 10 | no | "running" | — | Lifecycle |
| `loaded_count` | Added | integer | — | no | 0 | — | Card "2 rates, 41 prices" |
| `missing` | Added | json | — | yes | `[]` | — | `[{key, reason}]` for the email |
| `error_message` | Added | text | — | yes | null | — | Provider error |
| `notified_at` | Added | datetime | — | yes | null | — | Send once |
| `started_at`, `finished_at` | Added | datetime | — | yes | null | — | Duration in run history |

**`corporate_action_suggestions`** (new).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK, UK part | Tenant |
| `investment_instrument_id` | Added | bigint | — | no | — | FK | Instrument |
| `kind` | Added | string | 10 | no | — | — | split / bonus / dividend |
| `ex_date` | Added | date | — | no | — | — | Effective date |
| `ratio` | Added | decimal | 12,8 | yes | — | — | Matches `stock_adjustments.adjustment` |
| `amount_per_share_cents` | Added | decimal | 20,2 | yes | — | — | Dividend |
| `currency` | Added | string | 5 | yes | — | — | Dividend currency |
| `provider` | Added | string | 20 | no | — | — | Source |
| `provider_ref` | Added | string | 100 | no | — | UK part | `provider:ticker:kind:ex_date` — never suggest twice |
| `status` | Added | string | 10 | no | "pending" | — | Lifecycle |
| `resolved_by_id`, `resolved_at` | Added | bigint / datetime | — | yes | — | FK users | Audit |
| `stock_adjustment_id`, `portfolio_cashflow_id` | Added | bigint | — | yes | — | FK | Link to created record |

**`derivative_contracts`** (new).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id`, `fund_id` | Added | bigint | — | no | — | FK; `(fund_id, status)` | Tenant, list |
| `contract_type` | Added | string | 20 | no | — | — | option/warrant/future/forward/fx_forward/irs/ccs/trs/cds |
| `listed` | Added | boolean | — | no | false | — | Feed vs upload |
| `exchange` | Added | string | 10 | yes | — | — | Listed |
| `feed_symbol` | Added | string | 60 | yes | — | — | F&O key (symbol+expiry+strike+type) |
| `counterparty_name` | Added | string | 100 | yes | — | — | OTC (required when not listed) |
| `agreement_document_id` | Added | bigint | — | yes | — | FK documents | ISDA/CSA; required for swaps |
| `underlying_type` | Added | string | 15 | no | — | — | instrument / currency_pair / index |
| `underlying_instrument_id` | Added | bigint | — | yes | — | FK | Exercise target |
| `underlying_name` | Added | string | 30 | yes | — | — | "NIFTY", "USD/INR" |
| `side` | Added | string | 5 | no | — | — | long/short |
| `option_type` | Added | string | 4 | yes | — | — | call/put |
| `strike`, `forward_rate` | Added | decimal | 20,8 | yes | — | — | Rates need 8 dp (like `exchange_rates.rate`) |
| `lots`, `open_lots`, `lot_size` | Added | decimal | 24,8 | yes | — | — | Matches `portfolio_investments.quantity` |
| `notional_cents` | Added | decimal | 20,2 | yes | — | — | Forwards/swaps |
| `currency` | Added | string | 5 | no | — | — | Contract currency |
| `trade_date`, `expiry_date` | Added | date | — | no / no | — | `(expiry_date, status)` | Reminder job |
| `settlement` | Added | string | 10 | no | "cash" | — | physical/cash |
| `status` | Added | string | 10 | no | "open" | — | Lifecycle |
| `hedge_of_type`, `hedge_of_id` | Added | string / bigint | — | yes | — | polymorphic idx | Hedged holding (API) |
| `hedge_unit_type` | Added | string | 40 | yes | — | — | Hedged class |
| `expiry_reminded_at` | Added | datetime | — | yes | — | — | Send once |
| `json_fields` | Added | json | — | yes | — | — | Custom fields, house style |

**`derivative_events`** (new).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `derivative_contract_id`, `entity_id`, `fund_id` | Added | bigint | — | no | — | FK; `(contract, event_date)` | Lookup latest valuation |
| `event_type` | Added | string | 15 | no | — | — | trade/valuation/settlement/margin/exercise/expiry/close_out |
| `event_date` | Added | date | — | no | — | — | ≥ trade_date |
| `lots` | Added | decimal | 24,8 | yes | — | — | Exercise/close-out |
| `amount_cents` | Added | decimal | 20,2 | yes | — | — | Cash (+received / −paid) |
| `value_cents` | Added | decimal | 20,2 | yes | — | — | Valuation, signed, contract currency |
| `delta` | Added | decimal | 10,6 | yes | — | — | Exposure |
| `source`, `provider` | Added | string | 10 / 40 | yes | — | — | market/upload/manual |
| `idempotency_key` | Added | string | 64 | no | — | UK | Double submit (form token / feed key) |
| `portfolio_investment_id` | Added | bigint | — | yes | — | FK | Exercise result |
| `import_upload_id` | Added | bigint | — | yes | — | FK | Upload trace |
| `notes` | Added | text | — | yes | — | — | |

**`fund_navs`** (OEF, phase 8): `derivative_assets_cents`, `derivative_liabilities_cents` decimal(20,2)
default 0 not null (match other line columns); `exceptions` json default `[]`.

**Migration safety:**
- `exchange_rates`/`valuations`/`investment_instruments`: add columns with defaults (MySQL 8 instant
  ADD COLUMN); provider backfill one `UPDATE … WHERE import_upload_id IS NOT NULL`. Before adding the
  `exchange_rates` UK run `SELECT entity_id, from, to, as_of, COUNT(*) … HAVING COUNT(*) > 1` on the
  prod dump (port 33066); abort the migration with a clear message if any rows return.
- `funds.features` backfill: one statement —
  `UPDATE funds SET features = (show_fund_ratios<<0) | (show_fund_units<<1) | (show_portfolios<<2) | (show_valuations<<3) | (enable_ai_commentary<<4) | (editable_formulas<<5)`
  (NULLs coalesced to 0; bit order = `FundEnabled` order). Small table.
- ISIN backfill: `find_each` over instruments with `json_fields->>'$.sebi_isin'` present.
- `valuations` index change: drop/add on a moderate table — run off-hours.
- Reversible: every migration has a `down`; the backfills are no-ops on `down`.
- `db/schema.rb` and `db/schema_test.rb` both updated (see the local-migrate drift note in memory:
  restore schema files after `db:migrate`, hand-insert additions, `db:clean_schema`).

**Reviewer checks**
- [ ] Every new or changed column and index has a "why"
- [ ] Every FK has an index; every uniqueness rule is a UK except `valuations` (soft delete) and the entity row of `market_data_settings`
- [ ] Column limits match validation limits (ISIN 12, pivot 5, ticker 30)
- [ ] The duplicate pre-check exists in the `exchange_rates` UK migration
- [ ] The `funds.features` bit order in the backfill equals the `FundEnabled` flag order

---

## Method Contracts

**`SourcePolicy`** (Value, core)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for(fund)` | fund (duck: `entity`, `features`) | policy | — | none | Yes |
| `.for_entity(entity)` | Entity | policy from `MarketDataSetting.for_entity(entity).fund_defaults` | — | none | Yes |
| `#rate_sources` | — | `%w[manual]` + `market` (entity `enable_market_rates?` && fund `accept_market_rates?`) + `derived` (fund `accept_derived_rates?`) | — | — | Yes |
| `#own_fund_id` | — | `fund.id` when `fund.features.use_own_fx_rates?` (no entity feature needed), else nil; always nil for `.for_entity` | — | — | Yes |
| `#price_sources` | — | `%w[manual cost]` + `market` (entity && fund flag) | — | — | Yes |
| `#key` | — | `"r:manual+market+derived/p:manual+cost+market/own:42"` (`own:-` when off) — the memo key, so two funds never share a cached rate | — | — | Yes |
| `#label_for_rates` | — | "Manual", "Manual, Derived", … (used in messages) | — | — | Yes |

**`FxRateResolver`** (Service, core)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.resolve(entity_id:, from:, to:, as_of:, policy:, model: ExchangeRate)` | strings, Date, `SourcePolicy`, AR class (`ExchangeRateSqlite` in allocation) | `Resolution` | `MissingRate` | may insert a `derived` row | Yes (UK on derived row) |
| `.with_cache { }` | block | block value | — | thread-local memo keyed `[model, entity_id, policy.key, from, to, as_of]`; cleared after block | Yes |
| `Resolution` | Struct `rate, source, provider, as_of, row_id, kind (:direct/:reverse/:cross), legs, owner_fund_id` (set when a fund-own row or leg was used) | — | — | — | — |
| Candidate set / tie-break | — | Direct candidates = entity-wide rows in `rate_sources` ∪ (when `own_fund_id`) that fund's own manual rows. Latest `as_of` wins; same date: fund-own manual > entity manual > market > derived (and direct > reverse > cross). Reverse and cross legs may use fund-own rows. A derived row built from a fund-own leg is stored with `owner = fund` so no other fund or entity conversion sees it | — | — | — | — |
| `MissingRate#message` | — | "No {FROM}→{TO} rate on or before {date} in this fund's accepted sources ({label}). Enter a manual rate, or accept derived rates for this fund." | — | — | — |

**`PriceResolver`** (Service, core)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.resolve(instrument:, owner:, as_of:, policy:)` | records, Date, policy | `Resolution(value_cents, source, provider, as_of, valuation_id, previous_market_value_cents)` | `MissingPrice` ("No price for {instrument} on or before {date}") | none | Yes |

**`MarketDataSetting`** (Model, core)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_entity(entity)` | Entity | entity row (built, unsaved, with defaults if absent) | — | none | Yes |
| `.limits_for(fund)` | fund | `Limits(max_rate_age, max_price_age, threshold_pct, exposure_limit)` fund row ?? entity row ?? `3/3/10/nil` | — | none | Yes |

**`FundFeatureGuard`** (Service, funds)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund, requested)` | Fund, array of flag names | `[allowed, refused]` | — | none; controller returns 422 when `refused` non-empty | Yes |

**`MarketData::FeedRunner`** (Service, funds)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(entity:, kind:, provider:, run_date:, dry_run: false)` | | `MarketDataRun` (or unsaved for dry run) | — (provider errors captured into run) | upserts market rows; enqueues recompute; notifies | Yes (UKs) |

**`MarketData::Providers::Base`** (Interface)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#fetch(keys, date)` | array of pair/ticker/ISIN/feed_symbol, Date | `{key => BigDecimal}` (missing keys omitted) | `ProviderError` (HTTP/parse) | HTTP GET; cached per (provider, date) in `Rails.cache` 12 h | Yes |
| `#corporate_actions(tickers, date)` (NSE/BSE only) | | `[{ticker, kind, ex_date, ratio/amount, ref}]` | `ProviderError` | HTTP | Yes |

**Jobs** — see [Background Jobs](#background-jobs) for queue/retry.

| Job | `perform` args | Does |
|---|---|---|
| `MarketData::FxFeedJob` | `run_date = Date.current` | weekday guard; each entity with `enable_market_rates?` and `fx_feed_enabled`; each provider → `FeedRunner` |
| `MarketData::PriceFeedJob` | `run_date, market` (`"IN"`/`"US"`) | same for prices + `NseFo` + corporate actions |
| `MarketData::DerivativeExpiryJob` | `run_date` | reminders |
| `MarketData::FundFairValueRecomputeJob` | `fund_id` | `PortfolioInvestmentUpdate` over fund PIs `find_each` |

**`CorporateActionSuggestion`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#confirm!(user)` | User | created `StockAdjustment` / `PortfolioCashflow` | `InvalidTransition` if not pending | creates record via existing services; status confirmed | No (guarded by status) |
| `#dismiss!(user)` | User | self | `InvalidTransition` | status dismissed | No (guarded) |

**`DerivativeContract`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#value_on(date)` | Date | `value_cents` (contract ccy) of latest valuation event ≤ date, or nil | — | none | Yes |
| `.open_on(fund, date)` | Fund, Date | contracts with `trade_date ≤ date` and (open, or closed by an event dated > date) | — | none | Yes |
| `.value_on(fund, date)` | Fund, Date | `{assets_cents:, liabilities_cents:, missing: [contracts]}` in fund ccy via `FxRateResolver` | `MissingRate` | none | Yes |

**`Derivatives::EventRecorder`** (Trailblazer Operation)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(contract:, params:, idempotency_key:, current_user:)` | | Result with `:event` or `:errors` | — | lock contract; insert event; `LedgerPoster.post`; `Exerciser` for exercise/physical settlement; update `open_lots`/`status` | Yes (UK on key → returns existing event) |

**`Derivatives::LedgerPoster`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.post(event)` | DerivativeEvent | AccountEntry array | `ActiveRecord::RecordInvalid` | `AccountEntry.find_or_create_by!(fund_id:, parent: event, name:, reporting_date: event_date)` with `entry_type: "Derivatives"`, amount in fund ccy | Yes |

**`Derivatives::Exerciser`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.exercise(event)` | exercise event | `PortfolioInvestment` or nil (cash) | `InsufficientHolding` ("Fund holds only {n} shares of {instrument}") | `PortfolioInvestmentCreate.call` buy (call) / sell (put) | Via EventRecorder key |

**`Derivatives::ExposureReport`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.new(fund, date)` / `#rows` / `#total_cents` / `#multiple_of_nav` | | rows `{contract, basis (:notional/:delta/:full_notional), exposure_cents}`; multiple only when an approved NAV exists (phase 8) | `MissingRate`, `MissingPrice` (underlying) | none | Yes |

**`NavExceptions`** (Service, OEF, phase 8) and **`NavInputs`** additions

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `NavExceptions.call(fund_nav, inputs, previous:)` | FundNav, NavInputs, previous exceptions | array of `{key, kind (:move/:stale_price/:stale_rate), item, value, detail, accepted_by_id, accepted_at, note}` | — | none (builder saves) | Yes |
| `NavInputs#investment_resolutions` | — | per API `[price Resolution, rate Resolution]` from `fmv_on_date(with_resolution: true)` | `MissingPrice`, `MissingRate` | — | Yes |
| `NavInputs#derivative_assets_cents` / `#derivative_liabilities_cents` | — | from `DerivativeContract.value_on(fund, nav_date)` | `MissingDerivativeValue` | — | Yes |

**Reviewer checks**
- [ ] Every raised error is rescued by a caller or listed in Error Mapping
- [ ] `EventRecorder`, `FeedRunner`, `LedgerPoster` are safe to repeat
- [ ] `FxRateResolver.with_cache` memo is cleared at the end of each job/request (no cross-request leak)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `MarketData::SettingsController#show` | — | `MarketDataSettingPolicy#show?` | HTML | 403 |
| `#update` | `market_data_setting: [:fx_feed_enabled, :price_feed_enabled, :pivot_currency, :max_rate_age_days, :max_price_age_days, :price_move_threshold_pct, { fx_providers: [] }, { price_providers: [] }, { fund_defaults: {} }]` (blank `vendor_api_key` = keep) | `update?` | redirect + flash | 422 form |
| `#test_feed` | — | `update?` | turbo_stream popup | turbo_stream error |
| `MarketData::RunsController#index` | `page` | `MarketDataRunPolicy::Scope` | HTML | — |
| `ExchangeRatesController#create` (existing) | + `owner_id` (fund id; `owner_type` set server-side to `"Fund"`) | `create?` + `FundPolicy#update?` for the owner | existing | 422 if the fund lacks `use_own_fx_rates` or belongs to another entity |
| `ExchangeRatesController#index` (existing) | + `q[owner_id_eq]` | existing scope | HTML | — |
| `CorporateActionSuggestionsController#confirm` / `#dismiss` | — | `update?` (entity + fund portfolio write) | redirect to pre-filled Stock Adjustment form / list | 422 |
| `FundsController#update` (existing) | + `features: []`, `market_data_setting_attributes: [:id, :max_rate_age_days, :max_price_age_days, :price_move_threshold_pct, :exposure_limit_multiple]` | existing `update?` + `FundFeatureGuard` | existing | 422 with refused flags named |
| `DerivativeContractsController#index/show/new/create/edit/update/exposure` | `derivative_contract: [:contract_type, :listed, :exchange, :feed_symbol, :counterparty_name, :agreement_document_id, :underlying_type, :underlying_instrument_id, :underlying_name, :side, :option_type, :strike, :forward_rate, :lots, :lot_size, :notional, :currency, :trade_date, :expiry_date, :settlement, :hedge_of_type, :hedge_of_id, :hedge_unit_type, :premium]` | `DerivativeContractPolicy` | HTML / redirect | 422 |
| `DerivativeEventsController#create` | `derivative_event: [:event_type, :event_date, :lots, :amount, :value, :delta, :notes]`, `idempotency_key` (hidden form token) | `DerivativeEventPolicy#create?` | turbo_stream | 422 turbo_stream |
| `Evergreen::NavsController#accept_exception` (OEF) | `key`, `note` (required) | `FundNavPolicy#approve?` | turbo_stream | 403 / 422 |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Params never set `entity_id`, `fund_id` (taken from the parent), `status`, `open_lots`, `source`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `FxRateResolver` direct | `model.where(entity_id:, from:, to:).where(owner_type: nil, source: policy.rate_sources_direct).or(model.where(owner_type: "Fund", owner_id: policy.own_fund_id, source: "manual")).where(as_of: ..d).order(as_of: :desc, owner_rank, source_rank).limit(3)`; the `.or` branch is omitted when `own_fund_id` is nil | `(entity_id, from, to, as_of)`; `(owner_type, owner_id, from, to, as_of)` | ≤ 3 | memo |
| reverse | same with `from: to, to: from` | same | ≤ 2 | memo |
| cross legs | two direct queries via pivot | same | ≤ 2 each | memo |
| derived row lookup / insert | `find_or_create_by!(entity_id:, from:, to:, as_of:, source: "derived")` (rescue `RecordNotUnique` → find) | UK | 1 | — |
| leg change → derived rows | `ExchangeRate.where(source: "derived").where("leg1_id = :id OR leg2_id = :id")` | `leg1_id`, `leg2_id` | few | — |
| `PriceResolver` | `Valuation.where(investment_instrument_id:, owner:, synthetic: false, source: policy.price_sources).where(valuation_date: ..d).order(valuation_date: :desc, source_rank).first` | extended `idx_latest_valuation` | 1 | memo per (instrument, owner, date, policy) |
| previous Market price | same, `source: "market"`, `valuation_date: ...current.valuation_date`, `.first` | same | 1 | phase 8 only |
| `PairsInUse` | `Fund.where(entity_id:).distinct.pluck(:currency)`, `InvestmentInstrument…distinct.pluck(:currency)`, `CapitalCommitment.where(entity_id:).distinct.pluck(:folio_currency)`, `DerivativeContract…distinct.pluck(:currency)` | entity_id indexes | tens | `distinct.pluck` |
| Funds accepting a source | `Fund.where(entity_id:).where_features(:accept_market_rates)` | full scan of entity's funds (small) | ≤ 100 | — |
| `ExchangeRatePortfolioInvestmentJob` | existing PI query, `.where(fund_id: accepting_fund_ids)` | existing | existing | `find_each` |
| `DerivativeContract.value_on(fund, d)` | open contracts by `(fund_id, status)`; latest valuation per contract via `derivative_events (contract, event_date)` — one query with `MAX(event_date)` grouped, then fetch | indexes listed | tens | — |
| Expiry job | `DerivativeContract.where(status: "open", expiry_reminded_at: nil, expiry_date: d..target)` | `(expiry_date, status)` | few | `find_each` |
| Fingerprint parts (phase 8) | `ExchangeRate.where(entity_id:, as_of: ..d).pick(COUNT, MAX(updated_at))`; `DerivativeEvent.where(fund_id:, event_date: ..d).pick(...)` | entity / contract indexes | aggregate | — |

`owner_rank`: `CASE WHEN owner_id IS NULL THEN 1 ELSE 0 END` (fund-own first on ties).
`source_rank`: `FIELD(source, 'manual', 'market', 'derived')` for rates and
`FIELD(source, 'manual', 'market', 'cost')` for prices (SQLite: `CASE` expression — the resolver
builds the order clause per adapter).

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` (or by a fund/instrument already scoped)
- [ ] No unbounded loads; recompute and backfills use `find_each`
- [ ] The `FIELD`/`CASE` ordering is covered for both MySQL and SQLite (E28)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Feed upsert batch | one per (entity, provider) | none (UK upsert) | concurrent re-run | `market_data_runs` UK; row UKs |
| Recompute enqueue | after commit | — | recompute seeing uncommitted rows | `(company, instrument)` set per run |
| Derived row creation | own short transaction | UK | two requests deriving the same rate | UK `(entity, from, to, as_of, source)` |
| `EventRecorder` | contract + event + ledger + exercise PI | `contract.lock!` | double exercise exceeding open lots | `derivative_events.idempotency_key` UK |
| `CorporateActionSuggestion#confirm!` | suggestion + created record | `lock!` | double confirm | status check under lock |
| Fund flag change → recompute | save; enqueue after commit | — | — | job dedupe by `fund_id` (sidekiq unique args 10 min) |
| Accept exception (phase 8) | fund_nav update | `fund_nav.lock!` | concurrent accept/approve | key in exceptions json |
| Approve (phase 8) | existing `FundNavApprove` | existing | approve with open exception | re-check inside lock |

**Reviewer checks**
- [ ] No HTTP call or email inside a transaction (feed fetch happens before the upsert transaction; notifiers after commit)
- [ ] Lock order: contract before PI everywhere

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `MarketData::FxFeedJob` | `:low` | cron daily: IN `30 13 * * 1-5` UTC (19:00 IST, after ECB via EUR); US `0 22 * * 1-5` UTC | job `retry: 1`; provider fetch 3 tries, 2/8/30 s | — | run UK; `sidekiq_options lock: :until_executed` | 15 min |
| `MarketData::PriceFeedJob` | `:low` | cron: IN `0 13 * * 1-5` UTC (18:30 IST) with `market: "IN"`; US `30 22 * * 1-5` UTC with `market: "US"` | same | — | same | 30 min |
| `MarketData::DerivativeExpiryJob` | `:low` | cron daily `30 3 * * *` UTC | `retry: 3` | `RecordNotFound` | `expiry_reminded_at` | 5 min |
| `MarketData::FundFairValueRecomputeJob` | `:low` | fund flag change | `retry: 3` | `RecordNotFound` | unique by fund 10 min | 30 min |
| `ExchangeRatePortfolioInvestmentJob` (existing) | existing | rate commit (manual/market only); an owner rate recomputes **only its fund** (and only while the fund's `use_own_fx_rates` is on) | existing | — | existing | existing |
| `ExchangeRateCommitmentAdjustmentJob` (existing) | existing | manual rate commit; an owner rate adjusts **only that fund's** commitments; entity-wide manual rates skip funds whose own rate for the pair and date takes precedence | existing | — | existing | existing |

Cron strings follow the existing per-region pattern in `config/initializers/sidekiq.rb` (`in_region ?
… : …`, inside `unless Rails.env.local?`), e.g.
`Sidekiq::Cron::Job.create(name: 'MarketData::FxFeedJob', cron: fx_feed_cron, class: 'MarketData::FxFeedJob')`.
Exact UTC times are to be confirmed against provider publication times in phase 3.

**Reviewer checks**
- [ ] Running any job twice or out of order is harmless
- [ ] Cron entries are registered in the non-local block, per region (IN and US independent)

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| ECB via EUR rates | GET — endpoint to confirm in phase 3 | none | 5 s open / 20 s read | 3 tries | non-2xx / parse → `ProviderError` |
| ECB euro rates | via `eu_central_bank` gem (`update_rates` daily XML) | none | gem default + `Timeout` 20 s | 3 tries | `ProviderError` |
| NSE equity bhavcopy | GET daily archive — to confirm in phase 3 (needs browser-like headers) | none | 10 s / 60 s | 3 tries; 403 retried with backoff | `ProviderError` |
| BSE equity bhavcopy | GET — to confirm in phase 3 | none | 10 s / 60 s | 3 tries | `ProviderError` |
| AMFI NAV file | GET NAVAll text file — to confirm in phase 3 | none | 10 s / 60 s | 3 tries | `ProviderError` |
| NSE F&O bhavcopy | GET — to confirm in phase 3 | none | 10 s / 60 s | 3 tries | `ProviderError` |

**Reviewer checks**
- [ ] Every non-2xx and every parse failure maps to `ProviderError` with provider + date

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `FxRateResolver::MissingRate` | resolver (request) | `WithExchangeRate#convert_currency` adds to `errors[:base]` (today raises `RecordInvalid` — same path) | proposal message (X9) | info with entity, fund, pair |
| `MissingRate` (job: tracking currency, recompute) | resolver | existing job error handling | — | Sentry, unchanged behaviour |
| `MissingRate` / `PriceResolver::MissingPrice` / `MissingDerivativeValue` (NAV) | `NavInputs` | `FundNavBuilder#gather_inputs` → `ctx[:errors]` | X27/X28/X29 messages | — |
| `MarketData::ProviderError` | provider | `FeedRunner` → run failed/partial | run history; email | warn log with provider/date |
| `Derivatives::Exerciser::InsufficientHolding` | exerciser | `EventRecorder` → `ctx[:errors]` | X24 message | — |
| `ActiveRecord::RecordNotUnique` on derived row / event key | resolver / recorder | rescued → re-find existing | nothing | debug |
| `CorporateActionSuggestion::InvalidTransition` | model | controller → flash | "Already resolved" | — |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors
- [ ] Log lines include entity_id, fund_id and the provider/pair/instrument

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `MarketDataSettingPolicy` (edit via `EntityPolicy#update?`), `MarketDataRunPolicy`, `CorporateActionSuggestionPolicy`, `DerivativeContractPolicy`/`DerivativeEventPolicy` (entity flag && fund flag && `FundPolicy` show?/update?), `FundNavPolicy#approve?` for accept |
| Tenant isolation | Every new table has `entity_id`; scopes `where(entity_id: user.entity_id)`; feed jobs write per entity; resolver queries filter by `entity_id` |
| Secrets | None in this change — all providers are free public files. A per-client vendor adapter (L4) will add an encrypted key with masking, `filter_parameters` and `audited except:` |
| Input / output sanitisation | Provider files parsed as CSV/XML into BigDecimal; rejected if ≤ 0 or non-numeric; no provider text rendered unescaped |
| Mass assignment | Permitted params above; `FundFeatureGuard` re-checks flags server-side |

**Reviewer checks**
- [ ] A user from another entity cannot reach any contract, run, suggestion or setting by any route, job or MCP tool
- [ ] A fund-own rate is never returned for another fund or for an entity-level conversion (resolver `.or` branch keyed on `own_fund_id`; memo key carries `own:<fund_id>`)
- [ ] Investors/advisors get no access to any new screen

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None. IN and US independent (separate DBs, separate cron) |
| Feature flag | Entity flags `enable_market_rates`, `enable_market_prices`, `enable_derivatives` (off by default) |
| Cron / schedules | See [Background Jobs](#background-jobs) |
| Deploy order | Migrations (columns, tables, backfills, UK after pre-check) → code → cron entries register on boot |
| Rollback | Code rollback is safe: old code ignores new columns; the six booleans still hold their values (not written after deploy — **note:** fund edits made after deploy and before rollback would be lost from the booleans; acceptable, documented); market rows remain but old code would treat them as entity rates → before rolling back, delete `source IN ('market','derived')` rows (rake `market_data:purge_non_manual`, dry-run + `EXECUTE=1`) |
| Follow-up | Separate change drops the six fund booleans after one release |

### Bridge (phase 8) detail

1. Confirm phases 1–7 are green on `market-data`.
2. On `open-ended-funds`, `git merge market-data` (fallback: if `open-ended-funds` reached `main`
   first, `git merge main` on `market-data` instead). Expected conflicts:
   - `app/packs/core/entities/models/concerns/entity_enabled.rb` — identical flag line → take either.
   - `db/schema.rb`, `db/schema_test.rb` — both add tables/columns → keep both, re-run `db:clean_schema`.
   - `config/initializers/sidekiq.rb` — both add cron entries → keep both.
   - `openspec/changes/open-ended-market-data/` (from `cbdf9d381`) — superseded by `fund-market-data`; left as is.
3. Re-run phases 1–7 feature files (`features/market_data/*.feature`) and the OEF NAV features
   (`features/fund/evergreen/nav*.feature`) green before touching ⑧.
4. Move this change's Part 4 requirements into a `specs/funds/fund-nav/spec.md` MODIFIED delta;
   remove them from `fx-rates`, `market-prices`, `derivative-contracts`; `openspec validate --strict`.
5. Implement phase 8 (files marked OEF in the File Map).

**Reviewer checks**
- [ ] Safe to deploy with every entity flag off (no behaviour change; E1, E16, E36)
- [ ] Rollback rake exists and was dry-run on the prod dump
- [ ] Bridge step 2 conflict list matches the actual merge

---

### Apply-time notes (found while implementing)

| # | Finding | Decision |
|---|---|---|
| A1 | Every directory under `app/packs` is a Zeitwerk root (`config/application.rb`), so a file in `market_data/jobs/` defines a top-level constant | New non-controller classes use flat names: `FxFeedJob`, `PriceFeedJob`, `DerivativeExpiryJob`, `FundFairValueRecomputeJob`, `MarketDataFeedRunner`, `FbilProvider`/`EcbProvider`/`NseEquityProvider`/…, `DerivativeEventRecorder`, `DerivativeLedgerPoster`, `DerivativeExerciser`. Controllers keep `MarketData::` under `controllers/market_data/` |
| A2 | `Trackable` makes models `acts_as_paranoid`, so every new table needs `deleted_at` | Added `deleted_at` + index to every new table |
| A3 | The allocation engine's scratch SQLite is filled by `script/load_sqlite3_from_mysql.sh`, which lists columns per table | Phase 2 adds `funds.features` and the new `exchange_rates` columns to `COLS_*`/`SCHEMA_*` there, and `FundSqlite` includes `FundEnabled`'s flag definition so `SourcePolicy.for(fund_sqlite)` works |
| A4 | `AllocateMasterFundAccountEntries#get_exchange_rate` queries `exchange_rates` directly | Phase 2 routes it through `FxRateResolver` with the feeder fund's policy |
| A5 | The fund edit form is a two-step wizard; the Features section is on step 2 | Steps click **Next** before ticking features |
| A7 | FBIL publishes no machine-readable feed | ECB only (`EcbProvider`); non-EUR pairs computed from the same day's ECB table, provider "ECB via EUR" (proposal L6) |
| A8 | Real file formats confirmed 11 Oct 2026 | NSE/BSE cash and NSE F&O use the UDiFF common bhavcopy (`TckrSymb`, `ClsPric`, `SttlmPric`, `FinInstrmNm`); AMFI is `portal.amfiindia.com/spages/NAVAll.txt`; corporate actions from the nseindia.com JSON API (needs the site cookie — best-effort) |
| A9 | Turbo ignores a non-redirect response to a form post | Test feed posts with Turbo off and renders a results card on the settings page (not a popup) |
| A10 | Upload types dispatch by naming convention | Counterparty valuations upload as `import_type: "DerivativeEvent"` (`ImportDerivativeEvent` + `ImportDerivativeEventService`); single valuations via **Add event** on the contract page |
| A11 | Exposure report moved to phase 9 | `ExposureReport` not built in phase 6; no pricing models — delta is stored only when a statement gives one |
| A12 | The prod dump has 10 duplicate (entity, pair, date) exchange-rate groups despite the old Ruby uniqueness check | No DB unique key on `exchange_rates`; the model validation (per pair, date, source, owner) stays authoritative; `idx_exchange_rates_source` is non-unique. The migration is re-runnable (MySQL DDL is not transactional) |
| A6 | `open-ended-funds` declares `... enable_workflow_templates enable_evergreen_funds]`; this branch appends three flags after it, so the merge shows a one-line textual conflict (not an identical line) | Resolve by taking this branch's line; bit positions are identical. Entity 157 in the dev DB already had bit 35 set, confirming the reservation |

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/market_data/fund_features.feature` | — | `:market_data_setting` | `market_data_steps.rb`: entity features, fund features, migration backfill |
| `features/market_data/fx_rate_sources.feature` | — | `:exchange_rate` with `source` and `:fund_owned` traits | resolver/FMV assertions; allocation (SQLite) comparison; fund-own rate steps (H21, E68–E72, X33–X34) |
| `features/market_data/fx_feed.feature` (`@sync-http`) | WebMock + `features/support/fixtures/market_data/ecb_*.xml` | second entity (E73) | "the FX feed runs for …", email assertions, "entity {name} lists only its own market rates" (E73) |
| `features/market_data/market_prices.feature` | — | `:investment_instrument` `:market` trait, `:valuation` source traits | |
| `features/market_data/price_feed.feature` (`@sync-http`) | fixtures `nse_bhavcopy_*.csv`, `amfi_navall_*.txt`, `nse_corp_actions_*.csv` | — | recompute-count assertion via job spy |
| `features/market_data/derivatives_listed.feature` (`@sync-http` for F&O) | fixture `nse_fo_*.csv` | `:derivative_contract`, `:derivative_event` | `derivative_steps.rb` |
| `features/market_data/derivatives_otc.feature` | upload xlsx fixture | same | |
| `features/fund/evergreen/nav_market_data.feature` (OEF) | reuse NAV fixtures | reuse | extends `evergreen_nav_steps.rb` |

Each scenario carries `# <ID> — <Happy path|Edge case|Error case>: …` and the file header links to
`openspec/changes/fund-market-data/business-rules.md`. Runs: `TEST_ENV_NUMBER=$RANDOM`, Redis on 6379;
the worktree needs symlinked `node_modules` and credentials keys.

---

## Phase 9 Detail — Exposure Limits

Separate, later phase; nothing in phases 1–8 calls these. Design: card ⑥ "Exposure limits — phase 9".

**Schema (phase 9 migration)**

| Table.column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `market_data_settings.exposure_preset` | Added | string | 20 | yes | null | — | `sebi_cat12`/`sebi_cat3`/`ucits`/`us40act`/`custom`; "(customised)" derived by diff with `LimitPresets` |
| `market_data_settings.exposure_method` | Added | string | 12 | no | `commitment` | — | `gross`/`commitment` |
| `market_data_settings.hedging_only` | Added | boolean | — | no | false | — | Cat I/II hard rule |
| `market_data_settings.counterparty_bank_limit_pct` / `counterparty_other_limit_pct` | Added | decimal | 5,2 | yes | null | — | UCITS-style caps; null = off |
| `market_data_settings.single_underlying_limit_pct` | Added | decimal | 5,2 | yes | null | — | Concentration cap; null = off |
| `market_data_settings.allow_naked_short_calls` | Added | boolean | — | no | false | — | Hard rule switch |
| `market_data_settings.exclude_ccy_ir_hedges` | Added | boolean | — | no | false | — | '40 Act preset exclusion |
| `derivative_contracts.counterparty_kind` | Added | string | 10 | yes | null | — | `bank`/`other` for counterparty caps; required when a counterparty cap is set |
| `exposure_alerts` (new) | Added | — | — | — | — | UK `(fund_id, limit_key, as_of)`; FK fund, entity | Send-once breach email; history of red limits |

**Method contracts**

| Class | Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|---|
| `Derivatives::LimitPresets` | `.for(key)` | preset key | `{method:, leverage:, hedging_only:, cp_bank:, cp_other:, us40act_pct:, exclude_ccy_ir_hedges:, allow_naked_short_calls:}` | `KeyError` | none | Yes |
| `Derivatives::ExposureReport` | `.new(fund, date, method:)`, `#rows`, `#total_cents` | fund, date | rows `{contract, gross_cents, counted_cents, basis}` | `MissingRate` (conversion) | none | Yes |
| `Derivatives::HardRules` | `.check!(fund, contract_attrs)` | fund, attrs | nil | `HardRuleError` (message per rule) | none | Yes |
| `Derivatives::LimitCheck` | `.call(fund, date, proposed: nil)` | fund, date, unsaved contract | `[LimitResult(key, value, limit, level)]` (`:green/:amber/:red/:not_checked`) | — | none | Yes |
| `Derivatives::BreachNotifier` | `.notify(fund, results, as_of)` | fund, red results | count sent | — | inserts `exposure_alerts` (insert-ignore on UK) then `MarketDataOpsNotifier` `exposure_breach` after commit | Yes (UK) |

**Rules a reviewer must check**

| Rule | Decision |
|---|---|
| Amber / red thresholds | amber: `value ≥ 0.9 × limit`; red: `value > limit` (equal = amber) |
| NAV denominator | latest **approved** `FundNav` on or before the date (sum of classes); none → every % result `:not_checked` |
| Counterparty exposure | sum of positive latest OTC `value_cents` per `counterparty_name`; negatives count 0 |
| Commitment netting | hedge-linked contract offsets up to the hedged holding's FMV (or class NAV); same underlying + expiry long/short pairs net by notional |
| Pre-trade | controller runs `LimitCheck` with `proposed:`; any new `:red` → render confirm (action-summary card); `confirmed=1` param records |

**Reviewer checks**
- [ ] No phase 1–8 code path calls a phase 9 class
- [ ] Equal-to-limit is amber (E82); negative counterparty values count 0 (E84)
- [ ] Breach email is send-once via the `exposure_alerts` UK (E87)
- [ ] SEBI preset figures carry circular references before release (task 9.1)

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Resolver uses `.first`/`.limit`; guards use `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | `PairsInUse`; recompute and backfills `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` | Applies | `LedgerPoster` writes only; no `account_entries` reads added |
| Screen dates via `l(...)`; emails `Mon dd, yyyy` via `EmailDateLocalization` | Applies | Run history, contract pages, NAV ages use `l`; notifier views use bare `l(date)` |
| Date inputs `f.date_field` / `date_field_tag` | Applies | Contract and event forms |
| Every query entity-scoped; `authorize`/`policy_scope` everywhere | Applies | Security Review |
| MCP tool surfaces via ontology YAML | Applies | `valuation.yml` gains `source`; run `features/ai/mcp_server/mcp_ontology.feature` |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | Test Plumbing |
| `bundle exec rubocop` clean incl. `IRM/RelationBlankPresent` | Applies | Every phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
