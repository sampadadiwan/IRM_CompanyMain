class CapitalCommitmentCalcs < FundRatioCalcs
  delegate :ratio_formulas, to: :@capital_commitment

  def initialize(capital_commitment, end_date)
    @capital_commitment = capital_commitment
    @model = @capital_commitment
    @end_date = end_date
    super()
  end

  def ratio_formula_level
    "Folio"
  end

  def fmv_cents
    # Take the amount from the last account that satisfies the condition.
    # Cumulative entries are always on fund level so we should not need to search with false here but its here for safety
    # The last account entry will have the cumulative amount as we'll make sure of it by generating it using a fund formula
    @fmv_cents ||= begin
      ae = @capital_commitment.account_entries.where(name: "Portfolio FMV", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def cash_in_hand_cents
    @cash_in_hand_cents ||= begin
      ae = @capital_commitment.account_entries.where(name: "Cash In Hand", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def net_current_assets_cents
    @net_current_assets_cents ||= begin
      ae = @capital_commitment.account_entries.where(name: "Net Current Assets", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def estimated_carry_cents
    @estimated_carry_cents ||= begin
      ae = @capital_commitment.account_entries.where(name: "Estimated Carry", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def collected_cents
    @collected_cents ||=
      @capital_commitment.capital_remittances.verified.where(remittance_date: ..@end_date).sum(:collected_amount_cents)
  end

  def distribution_cents
    @distribution_cents ||=
      @capital_commitment.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:net_payable_cents)
  end

  def dpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    dc = distribution_cents
    dc, cc = apply_static_formulas('DPI', dc, cc, use_tracking_currency, ratio_formula_level, label: label)
    cc.positive? ? (dc / cc.to_f) : 0
  end

  def rvpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    total_val = fmv_cents + cash_in_hand_cents + net_current_assets_cents
    total_val, cc = apply_static_formulas('RVPI', total_val, cc, use_tracking_currency, ratio_formula_level, label: label, fmv: fmv_cents)
    cc.positive? ? (total_val / cc.to_f) : 0
  end

  def tvpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    dc = distribution_cents
    rv = fmv_cents + cash_in_hand_cents + net_current_assets_cents

    numerator = dc + rv
    numerator, cc = apply_static_formulas('TVPI', numerator, cc, use_tracking_currency, ratio_formula_level, label: label, fmv: fmv_cents)
    cc.positive? ? (numerator / cc.to_f) : 0
  end

  def fmv_on_date
    @fmv_on_date ||= begin
      ae = @capital_commitment.account_entries.where(name: "Portfolio FMV", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil, use_tracking_currency: false, label: nil)
    super(model: @capital_commitment, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:, label: label, level: ratio_formula_level)
  end
end
