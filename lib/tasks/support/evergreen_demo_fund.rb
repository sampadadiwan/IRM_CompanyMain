# Builds a complete demo open-ended (evergreen) fund for an existing entity, through the same services
# the screens use, so every part of the fund has data: settings and two unit classes, investors with
# approved KYCs, folios, a portfolio with valuations, the cash and fee ledger, approved NAVs, confirmed
# dealing dates with settled subscriptions and redemptions (early-redemption fee, and a gate on USD),
# and open orders on the next dates. Run by lib/tasks/evergreen_demo_fund.rake. Development / staging only.
#
# Not one transaction: allotment runs from after-commit hooks (EvergreenSettlementHooks →
# DealingSettlementSyncJob), and later redemptions need those units. A failure part-way leaves the
# fund as far as it got; the error names the fund so it can be deleted.
class EvergreenDemoFund
  include ActiveSupport::NumberHelper

  # Per currency: the settings preset, prices, minimums, investors, holdings and amounts.
  # Amounts are in major units of the currency.
  PROFILES = {
    "USD" => {
      preset: "us_tender_offer", category: nil, initial_price: 10, min_initial: 100_000, min_additional: 25_000,
      class_i_min_initial: 1_000_000, top_up: { "A" => 100_000, "I" => 500_000 }, amount_redemption: 300_000,
      other_assets: 25_000, other_liabilities: 15_000,
      # name, class, individual?, first subscription
      investors: [
        ["Harbor Family Office", "A", false, 750_000],
        ["Pinecrest Endowment", "A", false, 500_000],
        ["Meridian Pension Trust", "I", false, 2_500_000],
        ["Alder Ridge Capital LLC", "I", false, 1_500_000],
        ["Sophia Turner", "A", true, 250_000],
        ["Northgate Partners LP", "I", false, 1_000_000]
      ],
      # name, sector, shares, cost, monthly growth
      holdings: [
        ["Northwind Robotics Inc", "Tech", 150_000, 1_800_000, 0.012],
        ["Bluefin Health Inc", "Healthcare", 80_000, 1_600_000, 0.006],
        ["Cobalt Payments Inc", "Fintech", 200_000, 1_200_000, -0.004]
      ],
      late_holding: ["Delta Climate Systems Inc", "Climate", 50_000, 1_000_000, 0.018]
    },
    "INR" => {
      preset: "cat_iii_aif", category: "Category III", initial_price: 1_000, min_initial: 10_000_000, min_additional: 1_000_000,
      class_i_min_initial: 25_000_000, top_up: { "A" => 2_500_000, "I" => 10_000_000 }, amount_redemption: 10_000_000,
      other_assets: 1_500_000, other_liabilities: 1_000_000,
      investors: [
        ["Kapoor Family Trust", "A", false, 20_000_000],
        ["Mehta Holdings Pvt Ltd", "A", false, 15_000_000],
        ["Sundaram Investments LLP", "I", false, 60_000_000],
        ["Rao Family Office", "I", false, 40_000_000],
        ["Anita Desai", "A", true, 10_000_000],
        ["Vardhan Capital", "I", false, 30_000_000]
      ],
      holdings: [
        ["Saffron Agritech Pvt Ltd", "Agri", 45_000, 45_000_000, 0.012],
        ["Indus Logistics Ltd", "Logistics", 20_000, 40_000_000, 0.006],
        ["Lotus Fintech Pvt Ltd", "Fintech", 30_000, 30_000_000, -0.004]
      ],
      late_holding: ["Kaveri Clean Energy Pvt Ltd", "Climate", 25_000, 25_000_000, 0.018]
    }
  }.freeze

  CLASSES = %w[A I].freeze
  # Annual management fee by class (FundUnitSetting#management_fee), booked per NAV period by the
  # "Management Fee on NAV" formula in an allocation run
  MGMT_FEE_PCT = { "A" => 2.0, "I" => 1.25 }.freeze
  HISTORY_MONTHS = 6
  NOTE = "Demo data (evergreen:seed_demo_fund)".freeze

  def initialize(entity:, currency:, execute:, out: $stdout)
    @entity = entity
    @currency = currency
    @profile = PROFILES.fetch(currency) { raise ArgumentError, "CURR must be one of #{PROFILES.keys.join(', ')}" }
    @execute = execute
    @out = out
    @today = Time.zone.today
    @cash_moves = []   # [date, cents] — rewritten as dated "Cash In Hand" balances before each NAV
    @fees_owed = 0.to_d
    @folios = {}       # investor index => folio
    @holdings = []     # [pc, instrument, shares, cost_per_share_cents, growth, bought_on]
  end

  def run
    @user = @entity.employees.with_role(:approver).order(:id).first
    raise "No user of #{@entity.name} has the approver role — NAVs can't be approved" unless @user

    @setting_values = setting_values
    print_plan
    return say("DRY RUN — nothing created. Set EXECUTE=1 to build it.") unless @execute

    quietly { build }
    print_summary
  rescue StandardError
    say("FAILED#{" — fund #{@fund.id} (#{@fund.name}) is part-built; delete it from the funds list" if @fund&.persisted?}")
    raise
  end

  private

  attr_reader :profile

  # ---------- Plan ----------

  def fund_name
    @fund_name ||= "Demo Evergreen Fund (#{@currency}) #{Time.current.strftime('%Y-%m-%d %H:%M')}"
  end

  def setting_values
    values = EvergreenPresets.values(profile[:preset]).symbolize_keys
    values.merge(
      preset: profile[:preset], order_journeys: "off", redemption_forms: EvergreenFundSetting::REDEMPTION_FORMS.dup,
      min_initial_subscription: profile[:min_initial].to_s, min_additional_subscription: profile[:min_additional].to_s,
      # Demo data must not email anyone: every notification off (mail delivery is also off while seeding)
      notifications: EvergreenFundSetting::NOTIFICATIONS.keys.index_with { false }
    )
  end

  # Dealing dates from an unsaved setting (DealingCalendar is pure), so the dry run shows them too
  def past_dates(setting)
    from = @today - HISTORY_MONTHS.months
    DealingCalendar.all_dates(setting, from:, to: @today - 1.day)
  end

  def redemption_date?(setting, date)
    DealingCalendar.dealing_date?(setting, :redemption, date)
  end

  def print_plan
    setting = EvergreenFundSetting.new(@setting_values.except(:notifications))
    dates = past_dates(setting)
    say("#{@execute ? 'EXECUTE' : 'DRY RUN'}: #{fund_name} for #{@entity.name} (#{@entity.id}), approver #{@user.email}")
    say("  Preset #{profile[:preset]}; classes #{CLASSES.join(', ')} at #{money(profile[:initial_price] * 100)} a unit; journeys off; notifications off")
    say("  Investors: #{profile[:investors].map(&:first).join(', ')}")
    say("  Portfolio: #{(profile[:holdings] + [profile[:late_holding]]).map { |h| "#{h[0]} (#{money(h[3] * 100)})" }.join(', ')}")
    say("  Past dealing dates (NAV on the business day before, approved; then confirm and settle):")
    dates.each_with_index { |d, i| say("    #{d} #{redemption_date?(setting, d) ? 'subscriptions + redemptions' : 'subscriptions'}#{' — first subscriptions' if i.zero?}") }
    say("  Then open orders on the next subscription and redemption dates, and the dealing calendar for a year")
    raise "Fewer than 3 past dealing dates in #{HISTORY_MONTHS} months — check the preset's calendar" if dates.size < 3
  end

  # ---------- Build ----------

  # Runs jobs now like :inline, but drops delayed ones instead of raising: outside development every
  # notification is delayed (email_delay, config/initializers/noticed.rb), and the other delayed jobs on
  # this path are paid third-party checks (PAN, bank, AML) — none of which demo data should trigger.
  class InlineDropDelayedAdapter < ActiveJob::QueueAdapters::InlineAdapter
    def initialize(log)
      super()
      @log = log
    end

    def enqueue_at(job, _timestamp)
      # Not run, only noted, so a skipped job is visible in the task output
      @log.call("  skipped delayed #{job.class.name}")
      nil
    end
  end

  # Jobs run inline (allotment must happen before later redemptions); delayed jobs and mail are dropped
  def quietly
    adapter = ActiveJob::Base.queue_adapter
    deliveries = ActionMailer::Base.perform_deliveries
    ActiveJob::Base.queue_adapter = InlineDropDelayedAdapter.new(method(:say))
    ActionMailer::Base.perform_deliveries = false
    yield
  ensure
    ActiveJob::Base.queue_adapter = adapter
    ActionMailer::Base.perform_deliveries = deliveries
  end

  def build
    enable_permissions
    create_fund
    create_investors
    dates = past_dates(@fund.evergreen_fund_setting)
    red_plan = redemption_plan(dates)
    dates.each_with_index { |d, i| deal_past_date(d, i, red_plan[d]) }
    place_open_orders
    sync_cash!
    # The dealing calendar a year ahead, as the daily job keeps it
    DealingDateGenerateJob.perform_now(@fund.id)
  end

  # The entity needs evergreen funds and units switched on (as New Fund's Fund type choice requires)
  def enable_permissions
    missing = %i[enable_evergreen_funds enable_units].reject { |p| @entity.permissions.send(:"#{p}?") }
    return if missing.empty?

    say("  Switching on #{missing.join(', ')} for #{@entity.name}")
    missing.each { |p| @entity.permissions.set(p) }
    @entity.save!(validate: false)
  end

  def create_fund
    fund = Fund.new(entity: @entity, name: fund_name, currency: @currency, unit_types: CLASSES.join(","), category: profile[:category],
                    start_date: @today - HISTORY_MONTHS.months, first_close_date: @today - HISTORY_MONTHS.months)
    class_terms = CLASSES.map do |ut|
      term = { unit_type: ut, initial_price: profile[:initial_price].to_s }
      # Class I: institutional — higher minimum, performance fee over a 6% hurdle with a high-water mark
      term.merge!(min_initial_subscription: profile[:class_i_min_initial].to_s, perf_fee_model: "class_hwm", perf_fee_pct: 10, hurdle_pct: 6) if ut == "I"
      term
    end
    result = EvergreenFundCreate.call(fund:, setting_params: @setting_values.merge(class_terms:), current_user: @user)
    raise "Fund not created: #{Array(result[:errors]).to_sentence}" unless result.success?

    @fund = fund.reload.tap(&:reset_evergreen_cache)
    say("  Fund #{@fund.id} created")
    setup_management_fee
  end

  # The management fee as a GP sets it up: each class's fee % on its unit setting (the Fees tab reads
  # it) and the ready-made "Management Fee on NAV" formula, which allocation runs use to book the fee
  def setup_management_fee
    MGMT_FEE_PCT.each do |unit_type, pct|
      FundUnitSetting.find_or_initialize_by(fund_id: @fund.id, name: unit_type).update!(entity_id: @entity.id, management_fee: pct)
    end
    EvergreenFeeFormulaSeed.call(@fund)
    say("  Management fee: #{MGMT_FEE_PCT.map { |ut, pct| "#{ut} #{pct}%" }.join(', ')} a year on NAV (\"#{EvergreenFeeFormulaSeed::NAME}\" formula)")
  end

  # Investors of the entity (reused by name), each with fund access and an approved KYC
  def create_investors
    @investors = profile[:investors].map do |name, _ut, individual, _amount|
      inv = @entity.investors.find_by(investor_name: name) || new_investor(name)
      AccessRight.find_or_create_by!(owner: @fund, access_type: "Fund", metadata: "Investor", access_to_investor_id: inv.id, entity_id: @entity.id)
      [inv, approved_kyc(inv, individual)]
    end
  end

  def new_investor(name)
    # Short and stable: the investor-entity email lock name (MySQL GET_LOCK) is capped at 64 characters
    email = "demo+#{Digest::MD5.hexdigest(name).first(10)}@example.com"
    investor_entity = Entity.find_by(primary_email: email) || Entity.create!(name:, entity_type: "Investor", primary_email: email)
    @entity.investors.create!(investor_name: name, investor_entity:, category: "LP", primary_email: email, city: @currency == "USD" ? "New York" : "Mumbai")
  end

  def approved_kyc(inv, individual)
    existing = InvestorKyc.where(entity_id: @entity.id, investor_id: inv.id, verified: true).order(:id).first
    return existing if existing

    tax_id = Digest::MD5.hexdigest(inv.investor_name)[0, 10].upcase
    kyc = InvestorKyc.new(entity: @entity, investor: inv, full_name: inv.investor_name, kyc_type: individual ? "individual" : "non_individual",
                          residency: "domestic", PAN: tax_id, address: "1 Demo Street, #{inv.city}", corr_address: "1 Demo Street, #{inv.city}",
                          bank_name: "Demo Bank", bank_branch: inv.city, bank_account_type: "Current", bank_account_number: tax_id.to_i(16).to_s.first(12),
                          ifsc_code: "DEMO0000001", birth_date: Date.new(1975, 1, 1), verified: true, submission_status: "verified")
    kyc.skip_cf_before_save = true if kyc.respond_to?(:skip_cf_before_save=)
    kyc.save!
    kyc
  end

  # Redemptions go on the first two redemption dates whose notice period starts after the first
  # dealing date (so the units exist): a part redemption in units, then an amount redemption — plus,
  # when the fund has a gate, a large one the gate cuts back and carries forward.
  def redemption_plan(dates)
    setting = @fund.evergreen_fund_setting
    eligible = dates.drop(1).select do |d|
      redemption_date?(setting, d) && (d - (setting.notice_days + 2).days) > dates.first
    end
    plan = {}
    plan[eligible[0]] = [{ inv: 1, units_pct: 20 }] if eligible[0]
    if eligible[1]
      # An investor not also subscribing that day (and not the gated redeemer below)
      subscribing = subscriptions_for(dates.index(eligible[1])).map(&:first)
      plan[eligible[1]] = [{ inv: ([3, 5, 1] - subscribing).first, amount: profile[:amount_redemption] }]
      plan[eligible[1]] << { inv: 2, units_pct: 30 } if setting.gate_pct.positive?
    end
    plan
  end

  # One past dealing date: orders and payments, fees, valuations, cash, NAV, confirm, settle
  def deal_past_date(date, index, redemptions)
    setting = @fund.evergreen_fund_setting
    say("  #{date}:")
    sub_received = (date - (setting.subscription_cutoff_days + 3).days).in_time_zone.change(hour: 10)
    subscriptions_for(index).each { |inv, amount| subscribe(inv, amount, sub_received, pay: true) }
    red_received = (date - (setting.notice_days + 2).days).in_time_zone.change(hour: 10)
    Array(redemptions).each { |r| redeem(r, red_received) }

    # The NAV is struck on the business day before the dealing date (a month-end), as NavInputs expects:
    # money paid for orders dealing after the NAV date is set aside as dealing in progress, so the
    # subscriptions being dealt don't inflate the price they buy at
    nav_date = DealingCalendar.previous_business_day(date - 1.day)
    accrue_fees(@last_nav_date + 1.day, nav_date) if @last_nav_date
    pay_fees(nav_date) if index.positive? && redemption_date?(setting, date)
    other_balances(nav_date) if index == 1
    value_holdings(nav_date)
    sync_cash!
    approve_navs(nav_date)
    @last_nav_date = nav_date
    confirm(date)
    pay_redemptions(date)

    # The portfolio: the first money raised is invested a week later; one more company after the 4th date
    buy_holdings(profile[:holdings], date + 7.days) if index.zero?
    buy_holdings([profile[:late_holding]], date + 7.days) if index == 3
  end

  # [[investor index, amount]] for the nth dealing date
  def subscriptions_for(index)
    firsts = profile[:investors].each_with_index.map { |(_, _, _, amount), i| [i, amount] }
    case index
    when 0 then firsts.first(4)
    when 1 then [top_up(0), firsts[4]]
    when 2 then [firsts[5], top_up(2)]
    else [top_up(index % 6)]
    end
  end

  def top_up(inv)
    [inv, profile[:top_up].fetch(profile[:investors][inv][1])]
  end

  def subscribe(inv, amount, received_at, pay:)
    investor, kyc = @investors[inv]
    unit_type = profile[:investors][inv][1]
    order = place_order(kind: "subscription", unit_type:, investor_id: investor.id, investor_kyc_id: kyc.id,
                        capital_commitment_id: @folios[inv]&.id, amount: amount.to_s, received_at: received_at.iso8601)
    @folios[inv] ||= order.reload.capital_commitment
    say("    subscription #{investor.investor_name} #{unit_type} #{money(amount * 100)} → #{order.dealing_date.date}#{' (paid)' if pay}")
    return order unless pay

    # The day after the order, never in the future (open orders are placed today)
    paid_on = [received_at.to_date + 1.day, @today].min
    ok, error = EvergreenPayments.record_subscription_payment(order.capital_remittance, amount: nil, payment_date: paid_on,
                                                                                        reference: "DEMO-SUB-#{order.id}", user: @user)
    raise "Payment for order #{order.id}: #{error}" unless ok

    @cash_moves << [paid_on, amount * 100]
    order
  end

  def redeem(plan, received_at)
    investor, = @investors[plan[:inv]]
    folio = @folios.fetch(plan[:inv])
    params = { kind: "redemption", unit_type: folio.unit_type, investor_id: investor.id, capital_commitment_id: folio.id, received_at: received_at.iso8601 }
    if plan[:units_pct]
      held = FundUnit.where(capital_commitment_id: folio.id).sum(:quantity).to_d
      params[:units] = (held * plan[:units_pct] / 100).floor.to_s
    else
      params[:amount] = plan[:amount].to_s
    end
    order = place_order(**params)
    say("    redemption #{investor.investor_name} #{params[:units] ? "#{params[:units]} units" : money(plan[:amount] * 100)} → #{order.dealing_date.date}")
    order
  end

  def place_order(**params)
    result = DealingOrderCreate.call(fund: @fund, params:, current_user: @user, source: "admin")
    raise "Order #{params.inspect} refused: #{result[:errors]}" unless result.success?

    result[:order]
  end

  # Management fee for the NAV period (day after the previous NAV .. this NAV date), booked the way a GP
  # books it: an allocation run over the period, in which the "Management Fee on NAV" formula writes one
  # "Management Fees" entry per folio dated the period end (NAV per unit at the start × units × class
  # fee % × days ÷ 365). So the NAV's fee lines and the Fees tab read real formula output.
  def accrue_fees(start_date, end_date)
    run = AllocationRun.create!(fund: @fund, entity_id: @entity.id, start_date:, end_date:, run_allocations: true, user_id: @user.id)
    AccountEntryAllocationJob.perform_now(@fund.id, start_date, end_date, rule_for: "", tag_list: nil, run_allocations: true, explain: true,
                                                                          user_id: @user.id, generate_soa: false, template_id: nil, fund_ratios: false,
                                                                          sample: false, allocation_run_id: run.id)
    # Folio entries only: the run also writes a fund-level cumulative total with no folio
    booked = AccountEntry.where(fund_id: @fund.id, entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE, reporting_date: end_date)
                         .where.not(capital_commitment_id: nil).sum(:amount_cents).to_d
    @fees_owed += booked
    say("    management fee #{start_date}..#{end_date}: #{money(booked)} (allocation run #{run.id})")
  end

  # The fee owed is paid on redemption dates (quarterly for USD, monthly for INR), out of the fund's cash
  def pay_fees(date)
    return unless @fees_owed.positive?

    name = @fund.evergreen_fund_setting.mgmt_fee_paid_entry_name
    AccountEntry.create!(entity: @entity, fund: @fund, name:, entry_type: name, reporting_date: date, amount_cents: @fees_owed, notes: NOTE)
    @cash_moves << [date, -@fees_owed]
    say("    #{name} #{money(@fees_owed)}")
    @fees_owed = 0.to_d
  end

  # Receivables and an audit-fee payable, so the NAV's other assets / other liabilities lines show
  def other_balances(date)
    setting = @fund.evergreen_fund_setting
    { setting.other_assets_entry_name => profile[:other_assets], setting.other_liabilities_entry_name => profile[:other_liabilities] }.each do |name, amount|
      AccountEntry.create!(entity: @entity, fund: @fund, name:, entry_type: name, reporting_date: date, amount_cents: amount * 100, notes: NOTE)
    end
  end

  def buy_holdings(holdings, bought_on)
    holdings.each do |name, sector, shares, cost, growth|
      # Its own instrument per demo fund: valuations are keyed by company + instrument, so two demo funds
      # holding the same company (runs on different days, different price paths) never mix valuations
      pc, instrument = EvergreenDemoPortfolio.buy(@fund, name:, shares:, bought_on:, cost_cents: cost * 100, sector:, notes: NOTE,
                                                         instrument_name: "#{name} Equity (F#{@fund.id})")
      @holdings << [pc, instrument, shares, (cost * 100).to_d / shares, growth, bought_on]
      @cash_moves << [bought_on, -cost * 100]
      say("    bought #{name}: #{number_to_delimited(shares)} shares for #{money(cost * 100)} on #{bought_on}")
    end
  end

  # Each holding valued on the date: cost per share grown by its monthly rate (some up, one down)
  def value_holdings(date)
    @holdings.each do |pc, instrument, shares, cost_ps, growth, bought_on|
      next unless date > bought_on

      months = (date - bought_on).to_d / 30.4
      per_share = (cost_ps * ((1 + growth)**months.to_f)).round(2)
      EvergreenDemoPortfolio.value(@fund, pc, instrument, date:, per_share_cents: per_share, shares:)
    end
  end

  # "Cash In Hand" is a dated balance: one entry per date with money moving, holding the running total
  def sync_cash!
    name = @fund.evergreen_fund_setting.cash_entry_name
    running = 0.to_d
    @cash_moves.group_by(&:first).sort.each do |date, moves|
      running += moves.sum(&:last)
      entry = AccountEntry.find_or_initialize_by(entity_id: @entity.id, fund_id: @fund.id, capital_commitment_id: nil, name:, reporting_date: date)
      entry.update!(entry_type: name, amount_cents: running, notes: NOTE)
    end
  end

  # Draft every class's NAV from the portfolio and ledger, then approve it
  def approve_navs(date)
    result = FundNavBuilder.call(fund: @fund, nav_date: date, current_user: @user)
    raise "NAV on #{date}: #{result[:errors]}" unless result.success?

    result[:fund_navs].each do |nav|
      approved = FundNavApprove.call(fund_nav: nav.reload, current_user: @user)
      raise "Approve NAV #{nav.unit_type} on #{date}: #{approved[:errors]}" unless approved.success?
    end
    say("    NAV #{date} approved: #{result[:fund_navs].map { |n| "#{n.unit_type} #{money(n.nav_per_unit_cents)}" }.join(', ')}")
  end

  def confirm(date)
    dealing_date = DealingDate.for(@fund, date)
    preview = DealingPricer.preview(dealing_date)
    preview.unready.each { |row| say("    not ready: #{row.order} — #{row.reason}") }
    result = DealingConfirm.call(dealing_date:, current_user: @user, preview_hash: preview.hash_key)
    raise "Confirm #{date}: #{result[:errors]}" unless result.success?

    say("    confirmed")
  end

  # Redemptions are paid on their due date when it has passed; later ones stay outstanding
  def pay_redemptions(date)
    DealingDate.for(@fund, date).redemption_fills.includes(:capital_distribution_payment).find_each do |fill|
      payment = fill.capital_distribution_payment
      next unless payment && payment.payment_date < @today

      ok, error = EvergreenPayments.mark_redemption_paid(payment, payment_date: payment.payment_date, reference: "DEMO-RED-#{fill.id}")
      raise "Redemption payment #{payment.id}: #{error}" unless ok

      @cash_moves << [payment.payment_date, -payment.cost_of_investment_cents.to_d]
      say("    redemption paid #{money(payment.cost_of_investment_cents)} on #{payment.payment_date}#{" (early fee #{money(fill.early_fee_cents)})" if fill.early_fee_cents.to_d.positive?}")
    end
  end

  # Orders still open: on the next subscription date one paid and one awaiting money, and a
  # redemption on the next redemption date (each lands on whatever date its cut-off / notice allows)
  def place_open_orders
    say("  Open orders:")
    now = Time.current
    subscribe(4, profile[:top_up]["A"], now, pay: true)
    subscribe(1, profile[:top_up]["A"], now, pay: false)
    redeem({ inv: 0, units_pct: 10 }, now)
  end

  # ---------- Output ----------

  def print_summary
    @fund.reload
    say("Done: #{@fund.name} — /funds/#{@fund.id}")
    say("  Folios #{@fund.capital_commitments.count}; orders #{DealingOrder.where(fund_id: @fund.id).group(:status).count.map { |s, c| "#{s} #{c}" }.join(', ')}")
    say("  Dealing dates confirmed #{DealingDate.where(fund_id: @fund.id, status: 'confirmed').count}; NAVs approved #{FundNav.approved.where(fund_id: @fund.id).count}")
    CLASSES.each do |ut|
      nav = FundNav.latest_approved(@fund, ut, @today)
      units = FundUnit.where(fund_id: @fund.id, unit_type: ut).sum(:quantity).to_d
      say("  Class #{ut}: #{number_to_delimited(units.round(4))} units, NAV per unit #{money(nav&.nav_per_unit_cents)} (#{nav&.nav_date})")
    end
  end

  def money(cents)
    return "-" if cents.nil?

    "#{@currency} #{number_to_delimited(format('%.2f', cents.to_d / 100))}"
  end

  def say(msg)
    @out.puts(msg)
  end
end
