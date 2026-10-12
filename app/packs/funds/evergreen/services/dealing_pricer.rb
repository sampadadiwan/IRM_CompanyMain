# Prices a dealing date on read (design card ⑤): ready subscriptions at the approved NAV, ready
# redemptions through the GateAllocator, orders not ready listed with the reason and their fate.
# Nothing is written; DealingConfirm re-prices and compares the hash before storing fills.
# Worked examples H18, H19, H20, E24–E30, E34, X17 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingPricer
  SubRow = Data.define(:order, :nav, :amount_cents, :units)
  RedRow = Data.define(:order, :nav, :requested_units, :requested_value_cents, :filled_units, :value_cents, :carried_units, :early_fee_cents, :queue_position)
  UnreadyRow = Data.define(:order, :reason, :fate)
  # A ready order whose class has no usable NAV (missing, unapproved or already used): not priced, but still
  # listed so the dealing date's tabs show every order the list counts (E322)
  AwaitingNavRow = Data.define(:order, :reason)
  Pricing = Data.define(:dealing_date, :subscriptions, :redemptions, :unready, :awaiting_nav, :navs, :missing_navs, :gate) do
    def empty?
      subscriptions.empty? && redemptions.empty?
    end

    # Confirmable with something to price, or with only not-ready orders: confirming then just rolls
    # or cancels them, so they are never stuck on a past date (E181)
    def confirmable?
      (!empty? || unready.any?) && missing_navs.empty?
    end

    # Nothing priced, only orders to roll or cancel (E181) — not when ready orders wait on a NAV (E322)
    def roll_only?
      empty? && unready.any? && awaiting_nav.empty?
    end

    # Stable digest of what would be stored, compared at confirm (X20)
    def hash_key
      parts = subscriptions.map { |r| [r.order.id, r.units.to_s, r.nav&.id] } +
              redemptions.map { |r| [r.order.id, r.filled_units.to_s, r.value_cents.to_s, r.nav&.id] } +
              unready.map { |r| [r.order.id, r.fate] }
      Digest::SHA256.hexdigest(parts.to_json)
    end
  end

  def self.preview(dealing_date)
    new(dealing_date).preview
  end

  def initialize(dealing_date)
    @dd = dealing_date
    @fund = dealing_date.fund
    @setting = @fund.evergreen_fund_setting
  end

  def preview
    orders = DealingOrder.where(dealing_date_id: @dd.id, status: DealingOrder::OPEN_STATUSES)
                         .includes(:investor, :capital_commitment, :capital_remittance).in_queue_order.to_a
    ready, not_ready = orders.partition(&:ready_to_deal?)
    navs = ready.map(&:unit_type).uniq.index_with { |ut| pricing_nav(ut) }
    # A class can't be priced without an approved NAV — nor, by Decision 4, at a NAV its previous
    # dealing date already used (see .reused_on). Both block Confirm with the reason.
    missing = navs.reject { |_, nav| usable_nav?(nav) }.keys
    priced, waiting = ready.partition { |o| missing.exclude?(o.unit_type) }
    # E322: the reason is the same message that blocks Confirm, so the row and the alert agree
    awaiting = waiting.map { |o| AwaitingNavRow.new(order: o, reason: DealingConfirm.missing_nav_message(o.unit_type, navs[o.unit_type], @dd)) }

    subs = priced.select(&:subscription?).map { |o| sub_row(o, navs[o.unit_type]) }
    reds, gate = redemption_rows(priced.select(&:redemption?), navs)
    Pricing.new(dealing_date: @dd, subscriptions: subs, redemptions: reds,
                unready: not_ready.map { |o| unready_row(o) }, awaiting_nav: awaiting, navs:,
                missing_navs: missing.map { |ut| [ut, navs[ut]] }, gate:)
  end

  # The NAV a class prices at: its latest NAV on or before the dealing date, which must be approved.
  # A newer draft blocks pricing (X17) rather than silently using an older approved NAV.
  def pricing_nav(unit_type)
    FundNav.where(fund_id: @fund.id, unit_type:, nav_date: ..@dd.date).order(nav_date: :desc).first
  end

  # Approved, and not already used by this class's previous dealing date (Decision 4)
  def usable_nav?(nav)
    nav.present? && nav.approved? && self.class.reused_on(nav, @dd).nil?
  end

  # Decision 4, option B (docs/modules/funds/evergreen_design_decisions.md, agreed 10 Oct 2026):
  # a class's NAV must be NEWER than the NAV its previous dealing date used, so two dealing dates
  # never deal at the same NAV per unit. Without it, a date confirmed after its deadlines but before
  # the period's NAV is drafted silently deals at last period's price (1 Dec dealt at the 31 Oct NAV
  # when 30 Nov hasn't been drafted yet) — moving value between subscribers, redeemers and holders.
  # "Previous dealing date" = the latest confirmed / closed date before this one on which this class
  # was priced (it has fills). A class's first dealing date has none, so any approved NAV is fine;
  # undoing the previous date removes its fills, which frees its NAV again.
  #
  # Returns that previous DealingDate when `nav` is not newer than the NAV it used, else nil.
  def self.reused_on(nav, dealing_date)
    previous = DealingFill.joins(:dealing_date).includes(:fund_nav, :dealing_date)
                          .where(fund_id: dealing_date.fund_id, unit_type: nav.unit_type)
                          .where(dealing_dates: { status: %w[confirmed closed], date: ...dealing_date.date })
                          .where.not(fund_nav_id: nil)
                          .order("dealing_dates.date DESC").first
    return nil unless previous&.fund_nav

    nav.nav_date <= previous.fund_nav.nav_date ? previous.dealing_date : nil
  end

  # Redemption value already paid on OTHER confirmed / closed dealing dates in this date's gate period
  # (the date itself, its quarter or its year), per pool: { "fund" => cents } or { "A" => cents, ... }.
  # Review fix 8 (10 Oct 2026): shared with EvergreenGateForecast and returned in the pricing's gate
  # hash, so the dealing date's gate card and the Redemptions tab show the gate LEFT, as the allocation
  # uses — they used to show the full % of NAV, which disagreed with the fills on a quarterly / yearly gate.
  def self.gate_used(fund, setting, date, excluding_dealing_date_id: nil)
    period = DealingCalendar.gate_period_range(setting, date)
    consumed = DealingFill.joins(:dealing_date).where(fund_id: fund.id, kind: "redemption")
                          .where(dealing_dates: { status: %w[confirmed closed], date: period })
    consumed = consumed.where.not(dealing_date_id: excluding_dealing_date_id) if excluding_dealing_date_id
    if setting.gate_level == "class"
      consumed.group(:unit_type).sum(:amount_cents).transform_values(&:to_d)
    else
      { "fund" => consumed.sum(:amount_cents).to_d }
    end
  end

  private

  # Units the subscription buys: amount ÷ NAV per unit (the unit engine computes the same on allotment)
  def sub_row(order, nav)
    SubRow.new(order:, nav:, amount_cents: order.amount_cents.to_d, units: (order.amount_cents.to_d / nav.nav_per_unit_cents.to_d).round(8))
  end

  def redemption_rows(orders, navs)
    requests = orders.map { |o| request_for(o, navs[o.unit_type]) }
    pools = gate_pools(navs)
    fills = GateAllocator.allocate(requests:, pools:, level: @setting.gate_level, method: @setting.gate_method,
                                   investor_caps: investor_caps(orders, navs)).index_by(&:order_id)
    rows = orders.each_with_index.map do |o, i|
      req = requests[i]
      f = fills[o.id]
      RedRow.new(order: o, nav: navs[o.unit_type], requested_units: f.filled_units + f.carried_units, requested_value_cents: req.requested_value,
                 filled_units: f.filled_units, value_cents: f.value_cents, carried_units: f.carried_units,
                 early_fee_cents: early_fee(o, f, navs[o.unit_type]), queue_position: o.queue_position)
    end
    # The same whole-fund NAV the gate pool uses, so the summary never reads "= ₹0.00" on a date
    # with no ready redemptions (E112, review finding)
    total_nav = whole_fund_nav_cents(navs)
    gate = { pct: @setting.gate_pct.to_d, level: @setting.gate_level, period: @setting.gate_period, method: @setting.gate_method,
             # used: gate already paid earlier in the period (review fix 8), for the gate card
             pools:, used: (@setting.gate_pct.to_d.zero? ? {} : gate_used), fund_nav_cents: total_nav, requested_cents: requests.sum(&:requested_value),
             filled_cents: rows.sum(&:value_cents) }
    [rows, gate]
  end

  # What is still being asked for: the order's units / amount less what earlier dealing dates filled.
  # All-units orders are counted at this dealing date (E34).
  def request_for(order, nav)
    prior = order.dealing_fills.where.not(dealing_date_id: @dd.id)
    if order.form == "amount"
      amount = order.amount_cents.to_d - prior.sum(:amount_cents).to_d
      GateAllocator::Request.new(order_id: order.id, investor_id: order.investor_id, unit_type: order.unit_type, units: nil,
                                 nav_per_unit_cents: nav.nav_per_unit_cents, amount_cents: amount)
    else
      # Never more than the folio still holds net of other dates' dealt-but-unpaid redemptions
      free = [order.free_units(as_of: @dd.date, excluding_date_id: @dd.id), 0].max
      units = order.all_units ? free : [order.units.to_d - prior.sum(:units).to_d, free].min
      GateAllocator::Request.new(order_id: order.id, investor_id: order.investor_id, unit_type: order.unit_type, units:,
                                 nav_per_unit_cents: nav.nav_per_unit_cents, amount_cents: nil)
    end
  end

  # Gate value still available this period, per level; nil = no gate
  def gate_pools(navs)
    return Hash.new(nil) if @setting.gate_pct.to_d.zero?

    used = gate_used
    pct = @setting.gate_pct.to_d / 100
    if @setting.gate_level == "class"
      navs.to_h { |ut, nav| [ut, nav ? (nav.nav_cents.to_d * pct) - used.fetch(ut, 0).to_d : 0] }
    else
      # Fund level: % of the WHOLE fund's NAV — every class, not only those with orders today (review finding)
      { "fund" => (whole_fund_nav_cents(navs) * pct) - used.fetch("fund", 0).to_d }
    end
  end

  def gate_used
    @gate_used ||= self.class.gate_used(@fund, @setting, @dd.date, excluding_dealing_date_id: @dd.id)
  end

  # Every class's NAV: the one priced today, else its latest approved NAV on or before the dealing date
  def whole_fund_nav_cents(navs)
    @whole_fund_nav_cents ||= @fund.unit_types_list.sum { |ut| (navs[ut] || FundNav.latest_approved(@fund, ut, @dd.date))&.nav_cents.to_d }
  end

  # Investor-level gate: % of the investor's holding at the start of the period, less what they were
  # already filled this period (E29)
  def investor_caps(orders, _navs)
    return {} if @setting.investor_gate_pct.to_d.zero?

    period = DealingCalendar.gate_period_range(@setting, @dd.date)
    pct = @setting.investor_gate_pct.to_d / 100
    orders.map { |o| [o.investor_id, o.unit_type] }.uniq.to_h do |investor_id, unit_type|
      held = FundUnit.joins(:capital_commitment).where(fund_id: @fund.id, unit_type:, issue_date: ...period.first,
                                                       capital_commitments: { investor_id: }).sum(:quantity).to_d
      filled = DealingFill.joins(:dealing_date, :dealing_order).where(fund_id: @fund.id, kind: "redemption", unit_type:)
                          .where(dealing_dates: { status: %w[confirmed closed], date: period }, dealing_orders: { investor_id: })
                          .sum(:units).to_d
      [[investor_id, unit_type], (held * pct) - filled]
    end
  end

  # Early-redemption fee on the filled units, re-judged per lot on THIS dealing date: each locked lot
  # at its own age's rate (E86), and nothing for lots that unlocked since the order was placed or
  # rolled (E87). Other open redemptions of the folio take the free units first, as at acceptance.
  def early_fee(order, fill, nav)
    return 0.to_d unless fill.filled_units.positive?

    queued = DealingOrder.where(capital_commitment_id: order.capital_commitment_id, unit_type: order.unit_type, kind: "redemption",
                                status: DealingOrder::OPEN_STATUSES).where.not(id: order.id)
                         .where(received_at: ...order.received_at).sum { |o| o.all_units ? o.free_units : o.resolved_units.to_d }
    EvergreenLockUp.call(order, on: @dd.date, requested: fill.filled_units, queued:).fee_cents(nav.nav_per_unit_cents)
  end

  def unready_row(order)
    # A pending journey step is the real blocker (E21); unpaid money only when the journey is clear or absent (E24)
    waiting = OrderJourneyStatus.waiting_on(order)
    reason = if waiting
               "Not ready — waiting on: #{waiting}"
             elsif order.subscription? && @setting.pre_funded? && !order.fully_paid?
               "Not paid by cut-off"
             else
               "Not ready"
             end
    # Same rule as the confirm (DealingRoll.fate), so the preview states what will really happen (E108)
    no_later = DealingRoll.no_later_date(order)
    fate = case DealingRoll.fate(order, @dd)
           when :roll then "will roll to #{I18n.l(DealingRoll.next_date(order, @dd), format: :day_month_year)}"
           when :stay then "money received but #{no_later} — stays pending for a refund"
           else DealingRoll.next_date(order, @dd) ? "will be cancelled" : "will be cancelled — #{no_later}"
           end
    UnreadyRow.new(order:, reason:, fate:)
  end
end
