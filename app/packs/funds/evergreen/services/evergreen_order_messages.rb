# Proposal Behavior Rules wording shown when an order is placed (wizard preview, done step, emails).
# Worked examples E14, E16 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenOrderMessages
  module_function

  # ₹25,00,000 for INR (south-Asian grouping), $2,500,000 otherwise; no paise when whole
  def money(cents, fund)
    Money.new(cents.to_d, fund.currency).format(no_cents_if_whole: true, south_asian_number_formatting: fund.currency == "INR")
  end

  def units(value)
    ActionController::Base.helpers.number_with_precision(value, precision: 2, delimiter: ",", strip_insignificant_zeros: true)
  end

  # Screens use the locale's long date; emails always read "Aug 19, 2026" in English (CLAUDE.md — a mailer
  # renders under whatever locale the triggering job had, so the format and locale are forced)
  def date(value, email: false)
    email ? I18n.l(value, format: :email, locale: :en) : I18n.l(value, format: :day_month_year)
  end

  # The subscription payment reference the investor quotes: SUB-<folio>-<order id>, or SUB-<order id> while the
  # order has no folio yet (a first subscription) — one rule for the done page and the acknowledgement email
  def payment_reference(order)
    ["SUB", order.capital_commitment&.folio_id.presence, order.id].compact.join("-")
  end

  # Notes about the dealing date and fee the investor should know straight away. email: true when the
  # notes go into an email (date format, above)
  def notes(order, email: false)
    msgs = []
    fund = order.fund
    unit_word = EvergreenLabels.t(:units, fund:)
    # "An exit load" / "A redemption charge": the article follows the fund's word for the fee
    fee = EvergreenLabels.t(:early_fee, fund:, lower: true, article: true).sub(/\A\w/, &:upcase)
    missed = missed_cutoff(order)
    msgs << "Received after the #{date(missed.to_date, email:)} cut-off — #{EvergreenLabels.t(:dealt, fund:, lower: true)} on #{date(order.dealing_date.date, email:)}." if missed
    if order.redemption? && order.early_fee_pct.to_d.positive?
      # E86: lots of different ages pay different rates — say so, with the per-lot split
      msgs << if order.fee_breakdown
                "#{fee} applies to #{units(order.locked_units)} #{unit_word}: #{order.fee_breakdown}."
              else
                "#{fee} of #{units(order.early_fee_pct)}% applies to #{units(order.locked_units)} #{unit_word}."
              end
    end
    msgs
  end

  # The cut-off (or notice deadline) of the first dealing date on or after the received date, when
  # the order missed it and was moved to a later date
  def missed_cutoff(order)
    setting = order.fund.evergreen_fund_setting
    first = DealingCalendar.dates(setting, order.kind, from: order.received_at.to_date, to: order.received_at.to_date + 1.year).first
    return nil if first.nil? || order.dealing_date.nil? || first == order.dealing_date.date

    order.subscription? ? DealingCalendar.cutoff_at(setting, first) : DealingCalendar.notice_deadline(setting, first, order.unit_type)
  end
end
