# Display helpers for NAV screens and the management-fee accrual warning.
# Worked examples E35, E36 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenNavHelper
  LINE_LABELS = {
    "investments_fmv" => "Investments at fair value",
    "cash" => "Cash",
    "other_assets" => "Other assets",
    "mgmt_fee_payable" => "Management fee payable",
    "perf_fee_payable" => "Performance fee payable",
    "perf_fee_accrued" => "Accrued performance fee",
    "class_expenses_payable" => "Class expenses payable",
    "other_liabilities" => "Other liabilities",
    "dealing_in_progress" => "Money received for orders not yet dealt"
  }.freeze

  def evergreen_money(cents, fund)
    return "—" if cents.nil?

    money_to_currency(Money.new(cents.to_d, fund.currency))
  end

  def evergreen_nav_per_unit(cents)
    return "—" if cents.nil?

    number_with_precision(cents.to_d / 100, precision: 2, delimiter: ",")
  end

  # E205: the dealing-in-progress line takes advance money OUT of the cash balance, so that balance must
  # already include it. Warn when the latest cash balance is older than money received for orders not
  # yet dealt — otherwise the NAV would come out too low.
  def evergreen_cash_warning(fund_nav)
    return nil unless fund_nav.source == "computed" && fund_nav.dealing_in_progress_cents.to_d.positive?

    inputs = NavInputs.new(fund_nav.fund, fund_nav.nav_date)
    received_on = inputs.latest_advance_payment
    cash_on = inputs.cash_balance_date
    return nil if received_on.nil? || (cash_on && cash_on >= received_on)

    cash_text = cash_on ? "is from #{I18n.l(cash_on, format: :day_month_year)}" : "has not been entered"
    "The cash balance (\"#{inputs.setting.cash_entry_name}\") #{cash_text}, before money received on " \
      "#{I18n.l(received_on, format: :day_month_year)} for orders not yet dealt — update the cash balance and draft again, " \
      "or this NAV will be too low"
  end

  # The class-only expenses row shows when the class names its entries, or still carries an amount
  # (e.g. an override) — a class without its own expenses shows no such row (evergreen-share-classes E16)
  def evergreen_show_class_expenses?(fund_nav)
    fund_nav.class_expenses_payable_cents.to_d.nonzero? ||
      fund_nav.fund.evergreen_fund_setting&.terms_for(fund_nav.unit_type)&.class_expenses?
  end

  # E22, E23: "Class …" ledger entries that no class uses as its expense entries, found when the NAV was
  # drafted — a class expense booked there would otherwise be ignored without a word
  def evergreen_unclaimed_entries_warning(fund_nav)
    names = Array(fund_nav.breakdown.to_h["unclaimed_class_entries"])
    return nil if names.empty?

    quoted = names.map { |n| "'#{n}'" }.to_sentence
    noun = names.one? ? "Ledger entry #{quoted} looks" : "Ledger entries #{quoted} look"
    "#{noun} class-specific but no class uses #{names.one? ? 'it' : 'them'} — name it on the class or it is ignored"
  end

  # When a class charging a management fee has not been accrued up to the NAV date (E35); one rule with
  # the alert and the approval refusal (EvergreenFeeCheck, R9.2)
  def evergreen_mgmt_fee_warning(fund_nav)
    EvergreenFeeCheck.accrual_message(fund_nav)
  end
end
