# What the subscribe / redeem wizards show before submitting: dealing date and cut-off, indicative
# units or value at the latest approved NAV, early-redemption fee, queue position and any
# eligibility failure — nothing is saved.
# Worked examples H7, H9 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenOrderPreview
  attr_reader :order, :errors, :nav

  def initialize(order)
    @order = order
    fund = order.fund
    @nav = FundNav.latest_approved(fund, order.unit_type, Time.zone.today)
    @date = DealingCalendar.next_dealing_date(fund.evergreen_fund_setting, order.kind, order.unit_type, order.received_at)
    order.dealing_date = DealingDate.new(fund:, date: @date, cutoff_at: DealingCalendar.cutoff_at(fund.evergreen_fund_setting, @date))
    @errors = order.amount_cents.present? || order.units.present? || order.all_units ? OrderEligibility.errors_for(order) : []
  rescue DealingCalendar::NoDate => e
    @errors = [e.message]
  end

  def dealing_date
    @date
  end

  def notes
    EvergreenOrderMessages.notes(order)
  end

  def cutoff_date
    order.dealing_date&.cutoff_at&.to_date
  end

  def indicative_units
    return nil unless nav && order.subscription? && order.amount_cents.to_d.positive?

    (order.amount_cents.to_d / nav.nav_per_unit_cents.to_d).floor(4)
  end

  def indicative_value_cents
    return nil unless nav && order.redemption?

    (order.resolved_units * nav.nav_per_unit_cents.to_d).round(2)
  rescue DealingOrder::NoNav
    nil
  end

  # Where this redemption would sit if submitted now: after every open request on the same dealing
  # date (and class, for a class-level gate) — the same queue DealingOrder#queue_position ranks in
  # (review fix 7; it used to count every open redemption of the fund)
  def queue_position_if_submitted
    return nil unless order.redemption? && @date

    DealingOrder.redemption_queue(order.fund, @date, order.unit_type).count + 1
  end
end
