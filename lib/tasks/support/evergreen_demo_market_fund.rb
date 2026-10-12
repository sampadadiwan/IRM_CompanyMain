# Builds a demo INR open-ended fund whose portfolio uses the fund market data features, for
# evergreen:seed_demo_fund PORTFOLIO=public|hybrid (PORTFOLIO=private is plain EvergreenDemoFund):
#
#   public — listed securities only (NSE/BSE) plus one USD share: daily Market prices and FX rates,
#            Cost / Manual / Market precedence, a fund-specific FX rate, price vs currency effect
#   hybrid — the private companies of the plain demo (monthly Manual valuations) next to listed
#            holdings (daily Market prices): pricing is per instrument, so both sit in one NAV
#
# Both add listed derivatives with ledger entries and a hedge, corporate action suggestions and feed
# run history. Everything else — settings, classes, investors, dealing, NAVs, fees — is
# EvergreenDemoFund's. Development / staging only. Isolation rules: lib/tasks/support/market_data_demo.rb.
class EvergreenDemoMarketFund < EvergreenDemoFund
  PORTFOLIOS = %w[public hybrid].freeze

  def initialize(entity:, execute:, portfolio: "public", out: $stdout)
    raise ArgumentError, "PORTFOLIO must be one of #{PORTFOLIOS.join(', ')}" unless PORTFOLIOS.include?(portfolio)

    @hybrid = portfolio == "hybrid"
    super(entity:, currency: "INR", execute:, out:)
    # Same price paths on a re-run for the same entity
    @rng = Random.new(entity.id)
    @nav_count = 0
    @instruments = {}  # holding name => [portfolio company, instrument]
    @paths = {}        # holding name => { date => price }
    @first_buy_on = nil
    @profile = portfolio_profile(@profile)
  end

  private

  # Holdings rows: listed ones are [name, sector, shares, cost at the starting price, spec (Array)];
  # private ones keep EvergreenDemoFund's [name, sector, shares, cost, monthly growth (Float)]
  def portfolio_profile(inr)
    row = ->(spec) { [spec[0], spec[1], spec[5], spec[4] * spec[5], spec] }
    if @hybrid
      # The plain demo's three private companies (and its late one) beside four listed holdings, a
      # quarter the size, so the first purchases still fit in the first money raised
      listed = MarketDataDemo::LISTED.values_at(0, 1, 3, 5).map { |spec| [spec[0], spec[1], spec[5] / 4, spec[4] * spec[5] / 4, spec] }
      return inr.merge(holdings: inr[:holdings] + listed)
    end

    usd = MarketDataDemo::USD_HOLDING
    usd_row = [usd[0], usd[1], usd[5], (usd[4] * usd[5] * MarketDataDemo::FX_START["USD"]).round, usd]
    inr.merge(holdings: MarketDataDemo::LISTED.map(&row) + [usd_row], late_holding: row.call(MarketDataDemo::LATE_LISTED))
  end

  def listed?(row)
    row[4].is_a?(Array)
  end

  def fund_name
    @fund_name ||= "Demo #{@hybrid ? 'Hybrid' : 'Market'} Fund (INR) #{Time.current.strftime('%Y-%m-%d %H:%M')}"
  end

  def print_plan
    super
    listed = (profile[:holdings] + [profile[:late_holding]]).count { |h| listed?(h) }
    if @hybrid
      say("  Hybrid: #{3 + 1} private companies on monthly Manual valuations, #{listed} NSE/BSE holdings on daily Demo Market prices,")
    else
      say("  Public: daily Demo prices for #{listed - 1} NSE/BSE holdings, weekly manual USD prices for Apple, a fund-specific USD→INR rate,")
    end
    say("    a manual TCS price, Market FX rates (currencies no other Market-accepting fund uses),") unless @hybrid
    say("    Market FX rates (currencies no other Market-accepting fund uses),") if @hybrid
    say("    3 listed derivatives (Infosys put hedging the Infosys holding, Nifty future closed at expiry, written Nifty call),")
    say("    corporate action suggestions and run history. Other funds of #{@entity.name} are not changed.")
  end

  # ---------- Build ----------

  def build
    enable_permissions
    MarketDataDemo.enable_entity!(@entity, method(:say))
    create_fund
    enable_fund_features
    @history = MarketDataDemo.weekdays(@fund.start_date, MarketDataFeedRunner.latest_weekday(@today))
    # NAV dates (the business day before each dealing date), known up front: the fee allocation run
    # before each NAV checks that rates and prices exist on its end date
    @nav_dates = past_dates(@fund.evergreen_fund_setting).map { |d| DealingCalendar.previous_business_day(d - 1.day) }
    create_fx_rates
    create_instruments_and_prices
    create_investors
    dates = past_dates(@fund.evergreen_fund_setting)
    red_plan = redemption_plan(dates)
    dates.each_with_index { |d, i| deal_past_date(d, i, red_plan[d]) }
    place_open_orders
    sync_cash!
    DealingDateGenerateJob.perform_now(@fund.id)
    create_derivatives
    create_corporate_actions
    MarketDataDemo.runs!(@entity, @history, "prices" => @paths.count { |name, _| @instruments[name][1].market_priced? }, "fx" => @fx_currencies.size)
    # Current fair values from the latest accepted prices and rates
    FundFairValueRecomputeJob.perform_now(@fund.id)
  end

  # This fund only: Manual + Market prices, Market + Derived + its own FX rates, derivatives; the LP
  # visibility switches go through the same flags
  def enable_fund_features
    %i[accept_market_rates accept_derived_rates accept_market_prices use_own_fx_rates enable_derivatives
       show_portfolios show_valuations show_fund_units].each { |f| @fund.features.set(f) }
    @fund.save!
    say("  Fund features: Manual + Market prices, Manual + Market + Derived + fund-specific FX rates, Derivatives")
  end

  # Market X→INR rates for every weekday — only for currencies no other Market-accepting fund uses
  def create_fx_rates
    @fx_paths = MarketDataDemo::FX_START.to_h { |cur, start| [cur, MarketDataDemo.walk(@rng, @history, start, 0.004)] }
    @fx_currencies, blockers = MarketDataDemo.safe_fx_currencies(@fund)
    MarketDataDemo.market_rates!(@entity, @fx_currencies, @fx_paths)
    say("  Market FX rates (#{@history.size} weekdays): #{@fx_currencies.map { |c| "#{c}→INR" }.join(', ').presence || 'none'}")
    skipped = MarketDataDemo::FX_START.keys - @fx_currencies
    say("    skipped #{skipped.join(', ')} — used by #{blockers.join(', ')}, which accept Market rates") if skipped.any?
    # Only the listed fund holds a USD share that needs a USD→INR rate
    return if @hybrid || @fx_currencies.include?("USD")

    # No Market USD rate allowed: the fund converts Apple with rates of its own instead — weekly, and on
    # each NAV date as an administrator prices the NAV
    @fx_paths["USD"].select { |d, _| d.friday? || d == @history.first || @nav_dates.include?(d) }.each do |d, rate|
      MarketDataDemo.own_rate!(@fund, "USD", d, rate, "#{MarketDataDemo::NOTE} — weekly fund rate")
    end
    say("    USD→INR: weekly fund-specific rates instead")
  end

  # Instruments for every listed holding (the late one too) and their full price history; private
  # companies get theirs from EvergreenDemoFund when they are bought
  def create_instruments_and_prices
    (profile[:holdings] + [profile[:late_holding]]).select { |h| listed?(h) }.each do |name, _sector, _shares, _cost, spec|
      usd = spec.equal?(MarketDataDemo::USD_HOLDING)
      pc = EvergreenDemoPortfolio.portfolio_company(@entity, name)
      instrument = MarketDataDemo.instrument!(@fund, pc, spec, currency: usd ? "USD" : "INR", pricing: usd ? "manual" : "market")
      path = MarketDataDemo.walk(@rng, @history, spec[4], usd ? 0.012 : 0.02)
      # The USD share has no feed: a manual price each Friday and on each NAV date, as an administrator enters it
      path = path.select { |d, _| d.friday? || d == @history.first || @nav_dates.include?(d) } if usd
      MarketDataDemo.prices!(instrument, pc, path, source: usd ? "manual" : "market", provider: usd ? nil : MarketDataDemo::PROVIDER)
      @instruments[name] = [pc, instrument]
      @paths[name] = path
    end
    say("  Instruments: #{@instruments.values.map { |_, i| "#{i.name} [#{i.ticker}]" }.join(', ')}")
  end

  # Listed buys at that day's price (the purchase records the usual Cost price); private ones as the
  # plain demo buys them. @holdings keeps only private rows — EvergreenDemoFund values those monthly.
  def buy_holdings(holdings, bought_on)
    @first_buy_on ||= bought_on
    listed, unlisted = holdings.partition { |h| listed?(h) }
    super(unlisted, bought_on) if unlisted.any?
    listed.each do |name, _sector, shares, _cost, _spec|
      pc, instrument = @instruments.fetch(name)
      price_on = MarketDataDemo.on_or_before(@paths[name].keys, bought_on)
      pi = MarketDataDemo.buy!(@fund, pc, instrument, shares:, price: @paths[name][price_on], bought_on:)
      @cash_moves << [bought_on, -pi.amount_cents.to_d]
      say("    bought #{instrument.name}: #{number_to_delimited(shares)} at #{instrument.currency} #{@paths[name][price_on].round(2)} = #{money(pi.amount_cents)}")
    end
  end

  # Listed prices already exist for every weekday; private companies get their monthly Manual
  # valuation (EvergreenDemoFund). The listed fund adds two overrides that show precedence: a Manual
  # TCS price (beats Market) and the fund's own USD→INR rate (beats the rest).
  def value_holdings(date)
    super
    @nav_count += 1
    return if @hybrid

    case @nav_count
    when 3
      pc, tcs = @instruments.fetch(MarketDataDemo::LISTED[2][0])
      market = @paths[MarketDataDemo::LISTED[2][0]][MarketDataDemo.on_or_before(@history, date)]
      MarketDataDemo.prices!(tcs, pc, { date => (market * 1.03).round(2) }, source: "manual", provider: "Valuation committee")
      say("    manual TCS price #{(market * 1.03).round(2)} on #{date} (Market #{market.round(2)}) — the NAV uses the manual one")
    when 4
      market = @fx_paths["USD"][MarketDataDemo.on_or_before(@history, date)]
      MarketDataDemo.own_rate!(@fund, "USD", date, market + 0.35, "#{MarketDataDemo::NOTE} — custodian rate for the NAV")
      say("    fund-specific USD→INR #{(market + 0.35).round(4)} on #{date} — the NAV converts Apple at it")
    end
  end

  # ---------- Derivatives ----------

  def create_derivatives
    t0 = MarketDataDemo.on_or_before(@history, @first_buy_on)
    fridays = @history.select { |d| d > t0 && d.friday? }
    nifty = MarketDataDemo.walk(@rng, @history, MarketDataDemo::NIFTY_START, 0.01)
    infy_name = MarketDataDemo::LISTED[0][0]
    infy = @paths[infy_name]
    say("  Derivatives:")

    # Infosys put, long, protecting the Infosys holding: value = intrinsic + time value that decays to expiry
    strike = (infy[t0] * 0.95).round(-1)
    expiry = (@today + 75).end_of_month.prev_occurring(:thursday)
    holding = AggregatePortfolioInvestment.find_by(fund_id: @fund.id, investment_instrument_id: @instruments[infy_name][1].id)
    put = MarketDataDemo.contract!(@fund, premium: 4 * 400 * 38, name: "Infosys #{strike.to_i} put (demo)", contract_type: "option", side: "long",
                                          option_type: "put", underlying_type: "instrument", underlying_instrument: @instruments[infy_name][1],
                                          strike:, lots: 4, lot_size: 400, trade_date: t0, expiry_date: expiry, hedge_of: holding)
    fridays.each do |d|
      time_value = 38 * Math.sqrt((expiry - d).to_f / (expiry - t0))
      per_unit = [strike - infy[d], 0].max + time_value
      MarketDataDemo.event!(put, "valuation", d, value_cents: (per_unit * 1_600 * 100).round, source: "market", provider: MarketDataDemo::PROVIDER)
    end
    say("    #{put.name}: hedges #{infy_name}, #{fridays.size} weekly valuations")

    # Nifty future, long, held to expiry mid-period: value = (Nifty now − Nifty at trade) × units
    f_expiry = MarketDataDemo.on_or_before(@history, (t0 + 60).end_of_month.prev_occurring(:thursday))
    future = MarketDataDemo.contract!(@fund, premium: 0, name: "Nifty future #{f_expiry.strftime('%b-%y')} (demo)", contract_type: "future", side: "long",
                                             underlying_type: "index", underlying_name: "NIFTY", lots: 2, lot_size: 75, trade_date: t0, expiry_date: f_expiry)
    units = 150
    fridays.select { |d| d < f_expiry }.each do |d|
      MarketDataDemo.event!(future, "valuation", d, value_cents: ((nifty[d] - nifty[t0]) * units * 100).round, source: "market", provider: MarketDataDemo::PROVIDER)
    end
    final = ((nifty[f_expiry] - nifty[t0]) * units * 100).round
    MarketDataDemo.event!(future, "expiry", f_expiry, amount_cents: final, notes: "Cash-settled at the final settlement price") if future.reload.status == "open"
    say("    #{future.name}: closed at expiry on #{f_expiry}, settled #{money(final)}")

    # Nifty call, short (written): premium received, valued as a liability
    c_strike = (nifty[t0] * 1.04).round(-2)
    call = MarketDataDemo.contract!(@fund, premium: 75 * 120, name: "Nifty #{c_strike.to_i} call written (demo)", contract_type: "option", side: "short",
                                           option_type: "call", underlying_type: "index", underlying_name: "NIFTY", strike: c_strike, lots: 1,
                                           lot_size: 75, trade_date: t0, expiry_date: expiry)
    fridays.each do |d|
      per_unit = [nifty[d] - c_strike, 0].max + (120 * Math.sqrt((expiry - d).to_f / (expiry - t0)))
      MarketDataDemo.event!(call, "valuation", d, value_cents: -(per_unit * 75 * 100).round, source: "market", provider: MarketDataDemo::PROVIDER)
    end
    say("    #{call.name}: premium received, valued as a liability")
  end

  # Pending suggestions to confirm or dismiss on screen, and one already dismissed. None is confirmed
  # here: a confirmed split or bonus would change the holding's quantity under the generated prices.
  def create_corporate_actions
    # The split goes on SBIN when the fund holds it (public), else on Reliance (hybrid); both hold ITC
    split_on = @instruments[MarketDataDemo::LISTED[4][0]] || @instruments.fetch(MarketDataDemo::LISTED[1][0])
    itc = @instruments.fetch(MarketDataDemo::LISTED[5][0])[1]
    MarketDataDemo.suggestion!(split_on[1], kind: "split", ratio: 5, ex_date: @today + 21, subject: "Sub-division of shares from Rs 1 to Rs 0.20")
    MarketDataDemo.suggestion!(itc, kind: "dividend", amount: 6.5, ex_date: @today + 10, subject: "Interim dividend - Rs 6.50 per share")
    MarketDataDemo.suggestion!(itc, kind: "dividend", amount: 7.85, ex_date: @fund.start_date + 30, subject: "Final dividend - Rs 7.85 per share",
                                    status: "dismissed", user: @user)
    say("  Corporate actions: #{split_on[1].ticker} split and ITC dividend pending; an older ITC dividend dismissed")
  end

  def print_summary
    super
    say("  Market data: #{@paths.size} instruments, #{@history.size} weekdays of prices; FX #{@fx_currencies.join(', ').presence || 'fund-specific only'}")
    say("  Derivatives: /funds/#{@fund.id}/derivative_contracts · Instruments: #{@instruments.values.map { |_, i| "/investment_instruments/#{i.id}" }.join(' ')}")
  end
end
