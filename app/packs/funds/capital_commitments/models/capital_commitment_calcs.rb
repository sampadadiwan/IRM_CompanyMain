class CapitalCommitmentCalcs
  def initialize(capital_commitment, end_date)
    @capital_commitment = capital_commitment
    @end_date = end_date
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

  def dpi
    cc = collected_cents
    cc.positive? ? (distribution_cents / cc) : 0
  end

  def rvpi
    cc = collected_cents
    if cc.positive?
      (fmv_cents + cash_in_hand_cents + net_current_assets_cents) / cc
    else
      0
    end
  end

  def tvpi
    dpi + rvpi
  end

  def fmv_on_date
    @fmv_on_date ||= begin
      ae = @capital_commitment.account_entries.where(name: "Portfolio FMV", cumulative: false, reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def xirr(net_irr: false, return_cash_flows: false)
    cf = Xirr::Cashflow.new

    @capital_commitment.capital_remittance_payments.where(capital_remittance_payments: { payment_date: ..@end_date }).find_each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id}") if cr.amount_cents != 0
    end

    @capital_commitment.capital_distribution_payments.where(capital_distribution_payments: { payment_date: ..@end_date }).find_each do |cdp|
      cf << Xirr::Transaction.new(cdp.net_payable_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Distribution #{cdp.id}") if cdp.net_payable_cents != 0
    end

    cf << Xirr::Transaction.new(fmv_on_date, date: @end_date, notes: "FMV") if fmv_on_date != 0
    cf << Xirr::Transaction.new(cash_in_hand_cents, date: @end_date, notes: "Cash in Hand") if cash_in_hand_cents != 0
    cf << Xirr::Transaction.new(net_current_assets_cents, date: @end_date, notes: "Net Current Assets") if net_current_assets_cents != 0

    cf << Xirr::Transaction.new(estimated_carry_cents * -1, date: @end_date, notes: "Estimated Carry") if net_irr && estimated_carry_cents != 0

    Rails.logger.debug { "capital_commitment.xirr cf: #{cf}" }
    Rails.logger.debug { "capital_commitment.xirr irr: #{cf.xirr}" }

    lxirr = XirrApi.new.xirr(cf, "xirr_captial_commitment_#{@capital_commitment.id}_#{@end_date}") || 0
    Rails.logger.debug { "cc.xirr irr: #{lxirr}" }
    if return_cash_flows
      [(lxirr * 100).round(2), cf]
    else
      (lxirr * 100).round(2)
    end
  end
end
