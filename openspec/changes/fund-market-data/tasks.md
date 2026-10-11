# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Where:** branch `market-data`, worktree `/home/thimmaiah/work/IRM-market-data` (from `main`).
> Phases 1–7 need nothing from open-ended funds. **Phase 8 starts only after `market-data` is merged
> into `open-ended-funds`** and is built there (design.md › Bridge to open-ended funds).

> **IDs:** every feature task lists the H/E/X IDs it covers from [business-rules.md](business-rules.md).
> Each scenario has a `# <ID> — <Happy path|Edge case|Error case>: …` comment directly above it and
> the feature header links to business-rules.md. Code comments name the IDs of the paths they
> implement as the code is written.

## 1. Switches: entity features, fund feature flags, Market Data settings

- [x] 1.1 Prepare the worktree for Cucumber: symlink the main checkout's `node_modules` and
      `config/credentials/{test,development}.key`; confirm Redis is up on 6379. Verify with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/exchange_rates.feature` passing.
- [x] 1.2 Append `enable_evergreen_funds` (reserved, bridge) then `enable_market_rates
      enable_market_prices enable_derivatives` to `flag :permissions` in `EntityEnabled`; show them in
      `EntityDashboard` (LLD › File Map ①, Schema Detail `entities`). Verify in the Rails console that
      an existing entity's earlier flags read unchanged and the new ones read false.
- [x] 1.3 Migration: add `funds.features` (bigint, default 0) and backfill from the six boolean
      columns in one UPDATE (LLD › Schema Detail `funds`, Migration safety); add `FundEnabled`
      (`flag :features`) to `Fund` with new-record defaults. Restore `schema.rb`/`schema_test.rb`
      per the local-migrate note and run `db:clean_schema`. Verify on the dev dump (port 33066) that
      flag counts equal the old column counts for each of the six. *(Apply note: the backfill mapping is
      covered by E4; the dev-DB run was rolled back at the user's request — the shared dev DB follows the
      open-ended-funds branch.)*
- [x] 1.4 Switch every reader and writer of the six booleans to the flags (policies, views,
      `FundsController#fund_params`, `ImportFund`, `FundDashboard`) per design card ① table; columns
      stay but are unused (LLD › File Map ①). Verify with `grep -rnw` that no app code reads the six
      columns, and that `features/core/access_rights_fund_models.feature`,
      `features/fund/fund_access.feature` and `features/fund/master_fund_portfolio_access.feature`
      pass.
- [x] 1.5 Create `market_data_settings` and `MarketDataSetting` (`for_entity`,
      `limits_for`), `MarketDataSettingPolicy`, `MarketData::SettingsController`
      (show/update), the entity Market Data card, and validations (at least one provider when a feed is on, 0–30 days, 1–100 %)
      (LLD › Method Contracts `MarketDataSetting`, Controllers). Verify by saving the card in dev and
      seeing the provider check refuse an empty selection.
- [x] 1.6 Add the fund form *Features* section (`funds/_features` partial: visibility, reporting,
      market data rows gated by entity flags, Manual shown always-on, Limits only when the fund has an
      evergreen setting) and `FundFeatureGuard` (LLD › Method Contracts `FundFeatureGuard`). Verify in
      dev that market-data rows appear only with the entity flag on and a crafted PATCH is refused.
- [x] 1.7 Add `SourcePolicy` (`for(fund)`, `for_entity(entity)`, `key`) (LLD › Method Contracts).
      Verify in the console: a fund with no flags returns rates `[manual]`, prices `[manual, cost]`;
      turning the entity flag off masks the fund flag.
- [x] 1.8 Write the user-guide section for entity Market Data settings and fund Features (with FAQ
      via the `user-guide-faqs` skill and a mermaid diagram). Verify with UserGuideLint.
- [x] 1.9 Write `features/market_data/fund_features.feature` covering **H1, H2, H3, E1–E10, X1–X5**
      (X4/X5 exercised on the entity defaults, since no fund on `main` is open-ended). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/fund_features.feature` and
      the three access features from 1.4 until green before starting phase 2.

## 2. FX sources and the rate resolver

- [x] 2.1 Migration: `exchange_rates.source/provider/rate_type/leg1_id/leg2_id`, backfill (`manual`;
      provider `Upload`/`User`), unique index `(entity_id, from, to, as_of, source)`; same columns in
      the `ExchangeRateSqlite` schema copy; uniqueness validation scoped by source; `latest` per
      (pair, source) (LLD › Schema Detail `exchange_rates`). Verify the migration on the dev dump
      reports zero duplicate violations.
- [x] 2.2 Implement `FxRateResolver` (direct, reverse, cross, precedence, `Resolution`, `MissingRate`
      message, derived row find-or-create with legs, `with_cache`, model parameter for SQLite) (LLD ›
      Method Contracts `FxRateResolver`, Queries). Verify in the console against the shared-setup rates
      that each of E18–E24 returns the business-rules value.
- [x] 2.3 Route every call site through the resolver with the right policy: `WithExchangeRate`
      (`convert_currency`, `get_exchange_rate`, `tracking_exchange_rate`), `ExchangeRateShared`
      (`get_rate`, `convert`, `setup_variable_exchange` with `policy:` default entity),
      `Valuation#per_share_value_in(…, fund:)` and its two callers, `KpiFxConverter`,
      `PortfolioInvestmentCreate` line 27 (design card ⑤ table; LLD › File Map ⑤). Verify with
      `features/fund/tracking_currency_job.feature`, `features/startup/kpi_currency_conversion.feature`
      and the fund ratio features passing unchanged.
- [x] 2.4 Make the rate hooks source-aware: skip jobs for `derived`; `ExchangeRatePortfolioInvestmentJob`
      recomputes only funds accepting the source; `ExchangeRateCommitmentAdjustmentJob` only for
      `manual`; delete unreferenced derived rows when a leg changes (design card ③). Verify by
      creating a Market rate in dev and seeing no CommitmentAdjustment and only accepting funds
      recomputed.
- [x] 2.5a Fund-specific rates: `exchange_rates.owner_type/owner_id` (in 2.1's migration), the
      `use_own_fx_rates` fund flag, resolver candidates incl. the fund's own rows (own > entity on
      the same date), owner-scoped jobs, rate form Fund select and upload *Fund* column (design card
      ③, ⑤). Verify H21 and E68 in the console.
- [x] 2.5 Recompute a fund's fair values when its rate/price flags change (`FundFairValueRecomputeJob`,
      `find_each`) and audit the change (design card ⑦). Verify booked commitment amounts are
      unchanged after toggling in dev.
- [x] 2.6 Gain split: `unrealized_price_effect_cents`, `realized_price_effect_cents` on
      `portfolio_investments` (+ API sums), computed in `PortfolioComputations` (currency effect =
      total − rounded price effect), shown on holding and API pages (LLD › Schema Detail). Verify the
      Nimbus figures (H9) on the holding page in dev.
- [x] 2.7 Exchange Rates screen: Source, Provider, Rate type columns and Source filter; dates via
      `l(...)`. Verify visually at desktop and narrow width.
- [x] 2.8 Update the user guide for exchange rates (sources, precedence, derived rates, corrections,
      gain split) with FAQ and a mermaid diagram. Verify with UserGuideLint.
- [x] 2.9 Write `features/market_data/fx_rate_sources.feature` covering **H5, H9, H21, E16–E33, E68–E72, X8–X10, X33, X34**
      (E28 compares a live conversion with an allocation-run conversion). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/fx_rate_sources.feature` and
      `features/core/exchange_rates.feature` until green before starting phase 3.

## 3. FX rate feed

- [x] 3.1 Create `market_data_runs`, `MarketDataRun`, `MarketData::FeedRunner` (weekday check,
      per-provider cache, upsert, status, missing list, `notified_at`) and the provider interface (LLD ›
      Method Contracts `FeedRunner`, Background Jobs). Verify a dry run in the console returns a run
      result without writing rows.
- [x] 3.2 Implement the ECB provider (`EcbProvider`; FBIL dropped — proposal L6) (confirm endpoints and formats; record
      fixture files under `features/support/fixtures/market_data/`), and `MarketData::PairsInUse` with
      `distinct.pluck` (LLD › External Integrations). Verify each provider parses its fixture to the
      expected pairs in the console.
- [x] 3.3 Add `MarketData::FxFeedJob` and its per-region cron entry in `config/initializers/sidekiq.rb`
      (inside `unless Rails.env.local?`) (LLD › Background Jobs). Verify the cron entry is listed in
      the Sidekiq cron page on staging.
- [x] 3.4 Add `MarketDataOpsNotifier` (`fx_feed_missing`) with mailer view using `l(date)`, recipients
      FundAccounting-tagged active entity users; send once per run (design › Notifications). Verify
      the email in letter_opener shows "FX feed: no rates loaded for Oct 29, 2026".
- [x] 3.5 Accept an optional Source column in `ImportExchangeRate` (Manual only; provider `Upload`)
      and fix the duplicated "Rate" header. Verify by uploading the sample file in dev.
- [x] 3.6 Entity Market Data card: pairs tracked, last run, Run history page (`MarketData::RunsController`).
      Verify in dev after a manual job run.
- [x] 3.7 Update the user guide (FX feed, failures, what to do) with FAQ. Verify with UserGuideLint.
- [x] 3.8 Write `features/market_data/fx_feed.feature` covering **H4, E11–E15, E73, X6, X7** with WebMock
      stubs. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/fx_feed.feature`
      until green before starting phase 4.

## 4. Instruments and price sources

- [x] 4.1 Migration: `investment_instruments.isin/ticker/exchange/pricing_method` with indexes and
      ISIN backfill from `json_fields["sebi_isin"]`; validations (ISIN check digit, Market needs
      identifiers and a covered exchange, unique ticker) (LLD › Schema Detail). Verify the backfill count on the dev dump
      equals the count of instruments with `sebi_isin`.
- [x] 4.2 Point `InformationOnInvestmentsJob` at `isin` with fallback to the json key. Verify the
      SEBI report output is byte-identical on a dev fund before/after.
- [x] 4.3 Migration: `valuations.source/provider/price_type`, backfill `manual`, extend
      `idx_latest_valuation` with `source`; uniqueness validation scoped by source; `ransackable_attributes`
      + `app/packs/ai/mcp_server/ontology/valuation.yml` gain `source` (LLD › Schema Detail, Project
      Rules). Verify `features/ai/mcp_server/mcp_ontology.feature` passes.
- [x] 4.4 Implement `PriceResolver` (precedence manual > market > cost, policy filter, `Resolution`,
      `MissingPrice`) and route `PortfolioComputations` and `AggregatePortfolioInvestment#fmv_on_date`
      through it, including `with_resolution:` (LLD › Method Contracts `PriceResolver`). Verify
      `features/fund/portfolio.feature` and `aggregate_portfolio_investments.feature` pass unchanged.
- [x] 4.5 `PortfolioInvestmentCreate#create_valuation` writes a `cost` row (find_or_initialize by
      source); `Valuation#update_owner` per source (design card ④). Verify E40 in the console.
- [x] 4.6 Instrument form/import fields (ISIN, ticker, exchange, pricing method, Market badge) and
      valuation screens/upload (Source, Price type). Verify visually and with a sample upload.
- [x] 4.7 Update the user guide for instruments and valuations with FAQ. Verify with UserGuideLint.
- [x] 4.8 Write `features/market_data/market_prices.feature` covering **H6, H7, E34–E41, X11–X14, X35**.
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/market_prices.feature` and
      `features/fund/investment_instrument_form.feature` until green before starting phase 5.

## 5. Price feed and corporate actions

- [x] 5.1 Implement `Providers::NseEquity`, `Providers::BseEquity`, `Providers::Amfi` (no vendor
      adapter — L4, per client), with fixtures (LLD › External Integrations). Verify each parses its
      fixture in the console.
- [x] 5.2 Add `MarketData::PriceFeedJob` (+ cron per market close), upserting Market valuations with
      `skip_owner_update` and enqueuing one `PortfolioInvestmentUpdate` per (company, instrument)
      after commit; `price_feed_missing` notification (design card ②). Verify in dev that a run over
      three instruments of one company enqueues one recompute each.
- [x] 5.3 *Test feed* (dry run) action and action-summary popup. Verify it stores nothing.
- [x] 5.4 Create `corporate_action_suggestions` + model (`confirm!` pre-fills Stock Adjustment /
      income form, `dismiss!`), provider parsing of corporate actions, `corporate_action_suggested`
      notification, Portfolio › Corporate actions tab (design card ②). Verify a confirmed split
      produces the same StockAdjustment as a hand-entered one.
- [x] 5.5 Update the user guide (price feed, test feed, corporate actions) with FAQ. Verify with
      UserGuideLint.
- [x] 5.6 Write `features/market_data/price_feed.feature` covering **H8, H10, E42–E47, X15**. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/price_feed.feature` until green
      before starting phase 6.

## 6. Derivatives — listed contracts and FX forwards

- [x] 6.1 Create `derivative_contracts` and `derivative_events` with models, type-dependent
      validations, `open_lots`, idempotency key, `value_on`/`open_on` (LLD › Schema Detail, Method
      Contracts). Verify in the console that a short option valued negative reads as a liability.
- [x] 6.2 `DerivativeContractPolicy`/`DerivativeEventPolicy` (entity flag AND fund flag AND fund
      access; entity scope) (design card ⑥ access table). Verify a read-only user and another
      entity's user are refused in dev.
- [x] 6.3 `Derivatives::EventRecorder` (lock, checks, idempotency), `Derivatives::LedgerPoster`
      (entry names, `parent: event`, idempotent), `Derivatives::Exerciser` (call buy / put sell via
      `PortfolioInvestmentCreate`, holding check, cash settlement) (LLD › Transactions). Verify the
      H15 purchase price and E49 realised amount in the console.
- [x] 6.4 Controllers, Derivatives tab (default Open filter, button row actions), contract page,
      event forms, hedge link (holding or unit type) and holding "Hedged by" line. Verify visually at
      desktop and narrow width.
- [x] 6.5 `Providers::NseFo` settlement prices → valuation events for listed contracts with
      `feed_symbol`; `ImportDerivativeValuation` for counterparty statements. Verify with fixtures.
- [x] 6.6 `MarketData::DerivativeExpiryJob` + `derivative_expiring` notification. Verify a single
      reminder in letter_opener.
- [x] 6.7 Update the user guide (derivatives, events, exercise, exposure, reminders) with FAQ and a
      mermaid diagram. Verify with UserGuideLint.
- [x] 6.8 Write `features/market_data/derivatives_listed.feature` covering **H11–H16, E48–E55, E57,
      X16–X25**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/derivatives_listed.feature`
      until green before starting phase 7.

## 7. Derivatives — OTC swaps

- [x] 7.1 Enable contract types interest-rate swap, cross-currency swap, total-return swap and
      credit-default swap with their required fields (notional, currency, maturity, counterparty,
      agreement) and periodic settlement events (net amount) (design card ⑥). Verify H17's −₹15,000
      in the console.
- [x] 7.2 Swap fields on the contract form and statement upload mapping. Verify visually.
- [x] 7.3 Update the user guide for swaps. Verify with UserGuideLint.
- [x] 7.4 Write `features/market_data/derivatives_otc.feature` covering **H17, X26**. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/derivatives_otc.feature`, then
      re-run phases 1–6 features, until green before starting phase 8.

## 8. Open-ended NAV checks (on `open-ended-funds`, after merging `market-data` into it)

- [ ] 8.1 Gate: with phases 1–7 green, merge `market-data` into `open-ended-funds` (the user runs or
      approves the merge; never auto-commit); resolve the expected conflicts (`entity_enabled.rb` identical line, `db/schema.rb` +
      `schema_test.rb`, `config/initializers/sidekiq.rb`) per LLD › Bridge (phase 8) detail. Verify by
      re-running every feature from phases 1–7 plus `features/fund/evergreen/nav.feature` and
      `nav_from_portfolio.feature` green.
- [ ] 8.2 Reconcile specs: restate the NAV requirements from `fx-rates`, `market-prices` and
      `derivative-contracts` as MODIFIED deltas of `openspec/specs/funds/fund-nav` and remove them
      from the ADDED capabilities. Verify `openspec validate fund-market-data --strict`.
- [ ] 8.3 `fund_navs.derivative_assets_cents`, `derivative_liabilities_cents`, `exceptions`; add
      both lines to `FundNav::ASSET_LINES`/`LIABILITY_LINES` and `EvergreenNavHelper::LINE_LABELS`;
      `NavInputs#derivative_assets_cents`/`#derivative_liabilities_cents` via `DerivativeContract.value_on`;
      `FundNavBuilder#gather_inputs` rescues `MissingRate`/`MissingPrice`/missing contract value into
      `ctx[:errors]` (design card ⑧). Verify H18's NAV of ₹4,33,75,000 in dev.
- [ ] 8.4 `NavExceptions` (move > threshold strictly, ages in Mon–Fri business days, carry-over of
      acceptances), accept action (approver, note), `FundNavApprove` guard, NAV draft panel and
      source/age per line. Verify E58–E64 in the console.
- [ ] 8.5 `NavStaleness.common_parts` gains `MarketData::Fingerprint.rates` and `.derivatives`.
      Verify H20 and E66 mark the NAV "Inputs changed".
- [ ] 8.6 Limits group (rate age, price age, move threshold) on the fund form for funds with an
      evergreen setting; `nav_exceptions_open` key in `EvergreenFundSetting::NOTIFICATIONS` sent via
      `EvergreenOpsNotifier`. Verify the email in letter_opener.
- [ ] 8.7 Update the open-ended funds user guide (NAV lines, exceptions, staleness) with FAQ. Verify
      with UserGuideLint.
- [ ] 8.8 Write `features/fund/evergreen/nav_market_data.feature` covering **H18–H20, E58–E67,
      X27–X31**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/nav_market_data.feature`
      and the existing `features/fund/evergreen/` NAV features until green before starting phase 9.

## 9. Derivative exposure limits (separate, later phase)

> Nothing in phases 1–8 depends on this phase; it can ship in a later release.

- [ ] 9.1 Verify the SEBI preset figures (Cat III leverage 2× NAV, Cat I/II hedging only) against the
      current SEBI AIF circulars and record the circular references in the design. Verify the
      references are in design.md card ⑥.
- [ ] 9.2 Migration: exposure profile columns on `market_data_settings`,
      `derivative_contracts.counterparty_kind`, `exposure_alerts` (LLD › Schema Detail). Verify on the
      dev dump.
- [ ] 9.3 `ExposureReport` (gross / commitment, delta, short puts, hedge and opposite-position
      netting) and the exposure report screen. Verify E74, E75 and E77 figures in the console.
- [ ] 9.4 `Derivatives::LimitPresets` + profile form (preset select, "(customised)" label, extra
      limits) on the fund's Derivatives tab. Verify H22 and E76 in dev.
- [ ] 9.5 `Derivatives::HardRules` in `EventRecorder` (hedging only, hedge ≤ covered, naked short
      calls). Verify X36–X38 messages in dev.
- [ ] 9.6 `Derivatives::LimitCheck` (% of latest approved NAV, amber/red, counterparty by kind,
      single underlying), `NavExceptions` integration, `exposure_breach` notification via
      `exposure_alerts`, pre-trade confirm popup. Verify X32 and E88 in dev.
- [ ] 9.7 Update the derivatives user guide (exposure, presets, hard rules) with FAQ and a mermaid
      diagram. Verify with UserGuideLint.
- [ ] 9.8 Write `features/market_data/exposure_limits.feature` covering **H22, H23, E56, E74–E88,
      X32, X36–X38**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/market_data/exposure_limits.feature`
      until green before starting phase 10.

## 10. Coverage, clean-up and QA

- [ ] 10.1 Coverage: list every H/E/X ID in business-rules.md and every ID comment in the features
      above; confirm the two sets are equal (no ID without a scenario, no scenario without an ID).
      Any edge case found during apply gets a business-rules.md row and a scenario.
- [x] 10.2 Run `bundle exec rubocop` on changed files (including `IRM/RelationBlankPresent`) and fix
      everything. Verify a clean run.
- [ ] 10.3 Benchmark `TrackingCurrencyJob` on one large fund from the dev dump before/after the
      resolver; record the numbers in the PR. Verify the slowdown is under 10 %, or add the memo where
      it is missing.
- [ ] 10.4 Open a follow-up OpenSpec change to drop the six old fund boolean columns after one release.
      Verify the change exists in `openspec/changes/`.
- [ ] 10.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build that
      includes `open-ended-funds` and record the sign-off.
