# Runs one feed for one entity, kind and provider on a date: fetches quotes, upserts Market rows
# (this entity's only — market data is never shared between entities, E73), records the run and
# emails Fund accounting once when something could not be loaded.
#
# A dry run (the Test feed button) fetches and reports but stores nothing (E45).
# Worked examples H4, E11–E14, E73, X6, X7 — openspec/changes/fund-market-data/business-rules.md
class MarketDataFeedRunner
  Result = Struct.new(:run, :found, :missing, keyword_init: true)

  # The most recent weekday on or before the date (Test feed uses it for "today")
  def self.latest_weekday(date = Time.zone.today)
    date -= 1 while date.saturday? || date.sunday?
    date
  end

  def self.call(entity:, kind:, provider:, run_date:, dry_run: false)
    new(entity:, kind:, provider:, run_date:, dry_run:).call
  end

  def initialize(entity:, kind:, provider:, run_date:, dry_run:)
    @entity = entity
    @kind = kind
    @provider_key = provider
    @run_date = run_date
    @dry_run = dry_run
  end

  def call
    keys = keys_for_kind
    # Nothing for this provider to price (e.g. no AMFI holdings) → no request, no run row
    return Result.new(run: MarketDataRun.new(entity_id: @entity.id, kind: @kind, provider: @provider_key, run_date: @run_date, status: "ok"), found: [], missing: []) if keys.empty?

    run = find_or_build_run
    begin
      quotes = MarketDataProvider.for(@provider_key).fetch(keys, @run_date)
    rescue MarketDataProvider::Error => e
      # X6 — Error case: provider down after retries
      return finish(run, status: "failed", loaded: 0, missing: keys.map { |k| { "key" => k, "reason" => "provider unavailable" } }, error: e.message)
    end

    # X7 — Error case: a value of zero or less is not stored and is listed as missing
    valid, invalid = quotes.partition { |_key, quote| quote.value.to_d.positive? }.map(&:to_h)
    missing = (keys - quotes.keys).map { |k| missing_item(k, not_found_reason) } +
              invalid.keys.map { |k| missing_item(k, "invalid value") }
    store(valid) unless @dry_run

    status = if valid.empty? then "empty"
             elsif missing.any? then "partial"
             else "ok"
             end
    finish(run, status:, loaded: valid.size, missing:, found: valid.keys)
  end

  private

  def keys_for_kind
    case @kind
    when "fx" then MarketDataPairsInUse.for(@entity)
    when "prices" then instruments_by_key.keys
    else raise ArgumentError, "Unknown feed kind #{@kind}"
    end
  end

  # Market instruments this provider prices, keyed by ticker (NSE/BSE) or ISIN (AMFI)
  def instruments_by_key
    @instruments_by_key ||= begin
      scope = InvestmentInstrument.where(entity_id: @entity.id, pricing_method: "market")
      if @provider_key == "amfi"
        scope.where(exchange: nil).where.not(isin: nil).index_by(&:isin)
      else
        scope.where(exchange: InvestmentInstrument::PROVIDER_EXCHANGES.fetch(@provider_key)).where.not(ticker: nil).index_by(&:ticker)
      end
    end
  end

  # X15 — the email names the instrument and why it is missing
  def missing_item(key, reason)
    item = { "key" => key, "reason" => reason }
    item["name"] = instruments_by_key[key]&.name if @kind == "prices"
    item
  end

  def not_found_reason
    if @kind == "prices"
      @provider_key == "amfi" ? "ISIN not found at AMFI" : "ticker not found at #{@provider_key.upcase}"
    else
      "not published"
    end
  end

  def find_or_build_run
    attrs = { entity_id: @entity.id, kind: @kind, provider: @provider_key, run_date: @run_date }
    run = @dry_run ? MarketDataRun.new(attrs) : MarketDataRun.find_or_initialize_by(attrs)
    run.assign_attributes(status: "running", started_at: Time.current, finished_at: nil, error_message: nil)
    run.save! unless @dry_run
    run
  end

  def store(quotes)
    @kind == "prices" ? store_prices(quotes) : store_rates(quotes)
  end

  # Upsert this entity's Market prices, then recompute each affected holding once (E43, E44)
  def store_prices(quotes)
    touched = []
    Valuation.transaction do
      quotes.each do |key, quote|
        instrument = instruments_by_key[key]
        valuation = Valuation.find_or_initialize_by(entity_id: @entity.id, investment_instrument_id: instrument.id,
                                                    owner: instrument.portfolio_company, valuation_date: @run_date, source: "market")
        valuation.assign_attributes(per_share_value_cents: quote.value * 100, provider: quote.label, price_type: "close")
        valuation.valuation_cents ||= 0
        valuation.skip_owner_update = true
        next unless valuation.changed?

        valuation.save!
        touched << instrument
      end
    end
    recompute_holdings(touched.uniq)
  end

  # One PortfolioInvestmentUpdate per holding of each instrument that got a new price (E43)
  def recompute_holdings(instruments)
    return if instruments.empty?

    FxRateResolver.with_cache do
      # Each batch's sold/transferred quantities in two grouped queries, not two SUMs per holding
      PortfolioInvestment.find_each_with_buy_quantities(PortfolioInvestment.where(entity_id: @entity.id, investment_instrument_id: instruments.map(&:id))) do |pi|
        PortfolioInvestmentUpdate.call(portfolio_investment: pi)
      end
    end
  end

  # Upsert this entity's Market rates for the date (E11 — Edge case: a re-run updates, never duplicates)
  def store_rates(quotes)
    ExchangeRate.transaction do
      quotes.each do |key, quote|
        from, to = key.split("/")
        rate = ExchangeRate.find_or_initialize_by(entity_id: @entity.id, from:, to:, as_of: @run_date,
                                                  source: "market", owner_type: nil, owner_id: nil)
        rate.assign_attributes(rate: quote.value, provider: quote.label, rate_type: "reference")
        rate.save! if rate.changed?
      end
    end
  end

  def finish(run, status:, loaded:, missing:, error: nil, found: [])
    run.assign_attributes(status:, loaded_count: loaded, missing:, error_message: error, finished_at: Time.current)
    unless @dry_run
      run.save!
      notify(run)
    end
    Result.new(run:, found:, missing:)
  end

  # Fund accounting is emailed once per run date when something is missing (X6, X7, E14)
  def notify(run)
    return unless run.needs_attention?
    return if run.notified_at.present?

    recipients = User.where(entity_id: @entity.id, active: true).with_tag("FundAccounting")
    MarketDataOpsNotifier.with(record: run, entity_id: @entity.id, email_method: "#{@kind}_feed_missing").deliver_later(recipients.to_a) if recipients.exists?
    run.update_columns(notified_at: Time.current)
  end
end
