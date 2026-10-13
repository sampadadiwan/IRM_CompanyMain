# Market data demo helpers for lib/tasks/evergreen_demo_market_fund.rake: switches, generated FX rates
# and prices (no network — provider "Demo"), listed instruments, derivatives and corporate action
# suggestions. Development / staging data only.
#
# Isolation — the demo must not change any other fund of the entity:
#   - entity features are only switched on; other funds stay Manual-only until someone ticks them
#   - Market Data settings: created when missing; an existing row only gains the price providers the
#     demo instruments need, and fund_defaults are never touched (so new funds don't inherit anything)
#   - instruments are the fund's own (tickers carry the fund id), so their prices reach no other fund
#     and the real NSE/BSE feed never re-prices them
#   - Market FX rates are entity-wide by design, so a currency is generated only when no other fund
#     that accepts Market rates holds or has folios in it; manual overrides are the fund's own rates
module MarketDataDemo
  PROVIDER = "Demo".freeze
  NOTE = "Demo data (evergreen:seed_demo_fund PORTFOLIO=public|hybrid)".freeze

  # name, sector, ticker, exchange, starting price, shares
  LISTED = [
    ["Infosys Ltd", "IT/ ITes", "INFY", "NSE", 1_450, 10_000],
    ["Reliance Industries Ltd", "Oil,Gas & Consumable Fuels", "RELIANCE", "NSE", 1_280, 10_000],
    ["Tata Consultancy Services Ltd", "IT/ ITes", "TCS", "NSE", 3_900, 3_000],
    ["HDFC Bank Ltd", "Banks", "HDFCBANK", "NSE", 1_650, 7_500],
    ["State Bank of India", "Banks", "SBIN", "NSE", 780, 15_000],
    ["ITC Ltd", "FMCG", "ITC", "BSE", 430, 25_000]
  ].freeze
  LATE_LISTED = ["Bharti Airtel Ltd", "Telecom - Services", "BHARTIARTL", "NSE", 1_550, 10_000].freeze
  # The one USD holding: listed on NASDAQ, which no free feed covers, so it is priced manually (weekly)
  USD_HOLDING = ["Apple Inc", "Hardware", "AAPL", "NASDAQ", 190, 1_000].freeze
  # Starting X→INR levels for the generated Market rates
  FX_START = { "USD" => 83.2, "EUR" => 90.5, "GBP" => 105.8, "SGD" => 61.9 }.freeze
  NIFTY_START = 24_500

  module_function

  def weekdays(from, to)
    (from..to).reject { |d| d.saturday? || d.sunday? }
  end

  # The latest date in `dates` on or before `date`
  def on_or_before(dates, date)
    dates.rfind { |d| d <= date }
  end

  # A daily random walk: { date => level }, moving by up to ±vol a day
  def walk(rng, dates, start, vol)
    level = start.to_f
    dates.each_with_object({}) do |d, path|
      path[d] = level.round(4)
      level *= 1 + (((rng.rand * 2) - 1) * vol)
    end
  end

  # ---------- Switches ----------

  # Entity features on (other funds are unaffected until they tick them); price providers the demo
  # instruments need. Returns the entity's settings row.
  def enable_entity!(entity, say)
    missing = %i[enable_market_rates enable_market_prices enable_derivatives].reject { |p| entity.permissions.send(:"#{p}?") }
    if missing.any?
      say.call("  Switching on #{missing.join(', ')} for #{entity.name} (other funds stay Manual-only)")
      missing.each { |p| entity.permissions.set(p) }
      entity.save!(validate: false)
    end

    setting = MarketDataSetting.for_entity(entity)
    if setting.new_record?
      setting.assign_attributes(fx_feed_enabled: true, fx_providers: %w[ecb], price_feed_enabled: true, price_providers: %w[nse bse])
    else
      setting.price_providers = (Array(setting.price_providers) | %w[nse bse])
      setting.price_feed_enabled = true
    end
    setting.save! if setting.changed?
    setting
  end

  # Currencies the demo may write entity-wide Market rates for: those no other Market-accepting fund
  # holds (instrument currency) or has folios in
  def safe_fx_currencies(fund)
    others = Fund.where(entity_id: fund.entity_id).where.not(id: fund.id).select { |f| f.feature_enabled?(:accept_market_rates) }
    return [FX_START.keys, []] if others.empty?

    ids = others.map(&:id)
    used = InvestmentInstrument.joins(:portfolio_investments).where(portfolio_investments: { fund_id: ids }).distinct.pluck(:currency)
    used |= CapitalCommitment.where(fund_id: ids).where.not(folio_currency: nil).distinct.pluck(:folio_currency)
    safe = FX_START.keys - used
    [safe, others.map(&:name)]
  end

  # ---------- FX ----------

  # Market rates X→INR on every date, newest first: only the newest of each pair is `latest`, so only
  # it starts the rate jobs (which recompute just the funds accepting Market rates)
  def market_rates!(entity, currencies, paths)
    currencies.each do |cur|
      paths[cur].keys.sort.reverse_each do |d|
        rate = ExchangeRate.find_or_initialize_by(entity_id: entity.id, from: cur, to: "INR", as_of: d, source: "market", owner_type: nil, owner_id: nil)
        rate.assign_attributes(rate: paths[cur][d], provider: PROVIDER, rate_type: "reference", notes: NOTE)
        rate.save! if rate.changed?
      end
    end
  end

  # A fund-specific (own) manual rate — reaches this fund only (E72). Upserts, so a NAV-date override
  # replaces a weekly rate already stored for that date
  def own_rate!(fund, from, as_of, rate, notes)
    r = ExchangeRate.find_or_initialize_by(entity_id: fund.entity_id, from:, to: fund.currency, as_of:, source: "manual", owner: fund)
    r.assign_attributes(rate: rate.round(4), rate_type: "reference", notes:)
    r.save! if r.changed?
    r
  end

  # ---------- Instruments and prices ----------

  # The fund's own instrument: the ticker carries the fund id (tickers are unique per entity and
  # exchange), so no other fund shares its prices and the real feed never matches it
  def instrument!(fund, pc, spec, currency:, pricing:)
    name, sector, ticker, exchange = spec
    InvestmentInstrument.find_or_create_by!(entity: fund.entity, portfolio_company: pc, name: "#{name} (F#{fund.id})") do |i|
      i.category = "Listed"
      i.sub_category = "Equity"
      i.sector = sector
      i.currency = currency
      i.ticker = "#{ticker}-F#{fund.id}"
      i.exchange = exchange
      i.pricing_method = pricing
    end
  end

  # Prices for one instrument on the given dates ({ date => price }), as the feed stores them
  def prices!(instrument, pc, path, source:, provider:)
    path.each do |d, price|
      v = Valuation.find_or_initialize_by(entity_id: instrument.entity_id, investment_instrument_id: instrument.id, owner: pc,
                                          valuation_date: d, source:)
      v.assign_attributes(per_share_value_cents: (price * 100).round(2), provider:, price_type: "close", category: "Listed", sub_category: "Equity")
      v.valuation_cents ||= 0
      v.skip_owner_update = true
      v.save! if v.changed?
    end
  end

  # A buy through the app's own service; returns the portfolio investment
  def buy!(fund, pc, instrument, shares:, price:, bought_on:)
    pi = PortfolioInvestment.new(entity: fund.entity, fund:, portfolio_company: pc, investment_instrument: instrument, investment_date: bought_on,
                                 quantity: shares, ex_expenses_base_amount_cents: (price * shares * 100).round, category: "Listed",
                                 sub_category: "Equity", sector: instrument.sector, notes: NOTE)
    result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
    raise "#{instrument.name}: #{pi.errors.full_messages.to_sentence.presence || result[:errors]}" unless result.success?

    pi
  end

  # One ok run per weekday and kind, so Market Data › Run history shows a working feed
  def runs!(entity, dates, loaded)
    loaded.each do |kind, count|
      dates.each do |d|
        MarketDataRun.find_or_create_by!(entity_id: entity.id, kind:, provider: "demo", run_date: d) do |r|
          r.status = "ok"
          r.loaded_count = count
          r.missing = []
          r.started_at = r.finished_at = d.in_time_zone.change(hour: 21, min: 30)
        end
      end
    end
  end

  # ---------- Derivatives ----------

  def contract!(fund, premium:, **attrs)
    existing = DerivativeContract.find_by(fund_id: fund.id, name: attrs[:name])
    return existing if existing

    contract = DerivativeContract.new({ fund:, entity_id: fund.entity_id, currency: fund.currency, settlement: "cash", listed: true,
                                        exchange: "NSE" }.merge(attrs))
    raise "#{attrs[:name]}: #{contract.errors.full_messages.to_sentence}" unless DerivativeContractCreator.call(contract:, premium: premium.to_s)

    contract
  end

  # An event through the app's own recorder (it posts the ledger entries); idempotent per date and type
  def event!(contract, type, date, **params)
    result = DerivativeEventRecorder.call(contract:, idempotency_key: "mdd:#{contract.id}:#{type}:#{date}",
                                          params: { event_type: type, event_date: date, **params })
    raise "#{contract.name} #{type} #{date}: #{result.errors.to_sentence}" unless result.success?

    result.event
  end

  # ---------- Corporate actions ----------

  def suggestion!(instrument, kind:, ex_date:, subject:, status: "pending", ratio: nil, amount: nil, user: nil)
    CorporateActionSuggestion.find_or_create_by!(entity_id: instrument.entity_id, provider_ref: "demo:#{instrument.id}:#{kind}:#{ex_date}") do |s|
      s.investment_instrument = instrument
      s.kind = kind
      s.ex_date = ex_date
      s.subject = subject
      s.provider = "demo"
      s.ratio = ratio
      s.amount_per_share_cents = amount && (amount * 100)
      s.currency = instrument.currency
      s.status = status
      s.resolved_by = user if status != "pending"
      s.resolved_at = Time.current if status != "pending"
    end
  end
end
