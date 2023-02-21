class CapitalCommitmentCalcs
  def initialize(capital_commitment, end_date)
    @capital_commitment = capital_commitment
    @end_date = end_date
  end

  def fmv_cents
    ae = @capital_commitment.account_entries.where(name: "Portfolio FMV", cumulative: true, reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def cash_in_hand_cents
    ae = @capital_commitment.account_entries.where(name: "Cash In Hand", cumulative: true, reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def net_current_assets_cents
    ae = @capital_commitment.account_entries.where(name: "Net Current Assets", cumulative: true, reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def estimated_carry_cents
    ae = @capital_commitment.account_entries.where(name: "Estimated Carry", cumulative: true, reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def collected_cents
    @capital_commitment.capital_remittances.verified.where(payment_date: ..@end_date).sum(:collected_amount_cents)
  end

  def distribution_cents
    @capital_commitment.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:amount_cents)
  end

  def dpi
    cc = collected_cents
    cc.positive? ? (distribution_cents / cc) : 0
  end

  def rvpi
    cc = collected_cents
    cc.positive? ? (fmv_cents / cc).round(2) : 0
  end

  def tvpi
    dpi + rvpi
  end

  def fmv_on_date
    ae = @capital_commitment.account_entries.where(name: "Portfolio FMV", cumulative: true, reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def xirr(net_irr: false)
    cf = Xirr::Cashflow.new

    @capital_commitment.capital_remittance_payments.where("capital_remittance_payments.payment_date <= ?", @end_date).each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date)
    end

    @capital_commitment.capital_distribution_payments.where("capital_distribution_payments.payment_date <= ?", @end_date).each do |cdp|
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date)
    end

    cf << Xirr::Transaction.new(fmv_on_date, date: @end_date)
    cf << Xirr::Transaction.new(cash_in_hand_cents, date: @end_date)
    cf << Xirr::Transaction.new(net_current_assets_cents, date: @end_date)

    cf << Xirr::Transaction.new(estimated_carry_cents, date: @end_date) if net_irr

    Rails.logger.debug { "capital_commitment.xirr cf: #{cf}" }
    Rails.logger.debug { "capital_commitment.xirr irr: #{cf.xirr}" }
    (cf.xirr * 100).round(2)
  end
end
