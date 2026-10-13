# Headline figures for an evergreen fund (header, Overview, funds-list card): latest approved NAV per
# class, total NAV and units, net flows for the quarter to date, next dealing date, queue vs gate, cash.
# Worked examples H32, H33, E45 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenFundFigures
  def initialize(fund, today: Time.zone.today)
    @fund = fund
    @today = today
    @setting = fund.evergreen_fund_setting
  end

  def navs
    @navs ||= @fund.unit_types_list.index_with { |ut| FundNav.latest_approved(@fund, ut, @today) }
  end

  def total_nav_cents
    navs.values.compact.sum { |n| n.nav_cents.to_d }
  end

  def total_units
    navs.values.compact.sum { |n| n.units_outstanding.to_d }
  end

  # The newest draft newer than the latest approved NAV (E45)
  def newer_draft
    latest = navs.values.compact.map(&:nav_date).max
    scope = FundNav.draft.where(fund_id: @fund.id)
    scope = scope.where(nav_date: latest.next_day..) if latest
    scope.order(nav_date: :desc).first
  end

  # Quarter to date: subscriptions dealt minus redemptions dealt, counted at Confirm — when the units are
  # priced and the value moves (H33, F10). Redemptions dealt but not yet paid are already owed by the fund
  # (NavInputs#unpaid_redemptions), so leaving them out until payment overstated inflows after every
  # dealing date. :unpaid_out / :unallotted_in say how much of each side hasn't settled yet.
  def flows_qtd
    range = @today.beginning_of_quarter..@today
    fills = DealingFill.joins(:dealing_date).where(fund_id: @fund.id, dealing_dates: { date: range })
    subs = fills.where(kind: "subscription")
    reds = fills.where(kind: "redemption")
    inflow = subs.sum(:amount_cents).to_d
    outflow = reds.sum(:amount_cents).to_d
    { in: inflow, out: outflow, net: inflow - outflow,
      unallotted_in: subs.where(fund_unit_id: nil).sum(:amount_cents).to_d, unpaid_out: reds.where(fund_unit_id: nil).sum(:amount_cents).to_d }
  end

  def next_dealing_date
    @fund.dealing_dates.where(date: @today..).where.not(status: "closed").order(:date).first
  end

  def queued_redemption_cents
    DealingOrder.where(fund_id: @fund.id, kind: "redemption", status: DealingOrder::OPEN_STATUSES).sum do |o|
      nav = navs[o.unit_type]
      next 0 unless nav

      begin
        (o.resolved_units(nav_per_unit_cents: nav.nav_per_unit_cents) * nav.nav_per_unit_cents.to_d)
      rescue StandardError
        0
      end
    end
  end

  def gate_cents
    @setting.gate_pct.to_d.positive? ? total_nav_cents * @setting.gate_pct.to_d / 100 : nil
  end

  def cash_cents
    @fund.fund_account_entries.where(name: @setting.cash_entry_name, reporting_date: ..@today).order(reporting_date: :desc).pick(:amount_cents).to_d
  end

  def trend(unit_type)
    FundNav.approved.where(fund_id: @fund.id, unit_type:, nav_date: (@today - 12.months)..@today).order(:nav_date).pluck(:nav_date, :nav_per_unit_cents)
  end
end
