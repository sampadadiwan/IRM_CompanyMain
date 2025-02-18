class CapitalCommitmentTemplateDecorator < TemplateDecorator
  include CurrencyHelper

  def init_lp_gp_commitments(object)
    return if defined?(@gp_commitments) && defined?(@lp_commitments)

    base_scope = object.fund.capital_commitments.includes(:fund, :fund_unit_setting).where(committment_date: ..@end_date)

    @gp_commitments = base_scope.joins(:fund_unit_setting).where(fund_unit_settings: { gp_units: true })
    @lp_commitments = base_scope.joins(:fund_unit_setting).where(fund_unit_settings: { gp_units: false })
  end

  def committed_cash_lp
    init_lp_gp_commitments
    @committed_cash_lp = Money.new(@lp_commitments.sum(:committed_amount_cents), object.fund&.currency)
    @committed_cash_lp
  end

  def committed_cash_gp
    init_lp_gp_commitments
    @committed_cash_gp = Money.new(@gp_commitments.sum(:committed_amount_cents), object.fund&.currency)
    @committed_cash_gp
  end

  def committed_cash_total
    @committed_cash_total = committed_cash_lp + committed_cash_gp
    @committed_cash_total
  end

  def committed_cash_investor
    object.committed_amount
  end

  def committed_cash_investor_percent
    @committed_cash_investor_percent = committed_cash_total.zero? ? 0 : (object.committed_amount / committed_cash_total) * 100
    @committed_cash_investor_percent
  end

  def committed_reinvest_lp
    init_lp_gp_commitments
    @committed_reinvest_lp = Money.new(@lp_commitments.sum(:committed_reinvest_cents), object.fund&.currency) unless defined?(@committed_reinvest_lp)
    @committed_reinvest_lp
  end

  def committed_reinvest_gp
    init_lp_gp_commitments
    @committed_reinvest_gp = Money.new(@gp_commitments.sum(:committed_reinvest_cents), object.fund&.currency) unless defined?(@committed_reinvest_gp)
    @committed_reinvest_gp
  end

  def committed_reinvest_total
    @committed_reinvest_total = committed_reinvest_gp + committed_reinvest_lp
    @committed_reinvest_total
  end

  def committed_reinvest_investor
    @committed_reinvest_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents), object.fund.currency) unless defined?(@committed_reinvest_investor)
    @committed_reinvest_investor
  end

  def committed_reinvest_investor_percent
    @committed_reinvest_investor_percent = committed_reinvest_total.zero? ? 0 : (committed_reinvest_investor / committed_reinvest_total) * 100
    @committed_reinvest_investor_percent
  end

  def drawdown_cash_lp
    init_lp_gp_commitments
    @drawdown_cash_lp = Money.new(@lp_commitments.sum(:call_amount_cents), object.fund.currency) unless defined?(@drawdown_cash_lp)
    @drawdown_cash_lp
  end

  def drawdown_cash_gp
    init_lp_gp_commitments
    @drawdown_cash_gp = Money.new(@gp_commitments.sum(:call_amount_cents), object.fund.currency) unless defined?(@drawdown_cash_gp)
    @drawdown_cash_gp
  end

  def drawdown_cash_total
    @drawdown_cash_total = drawdown_cash_gp + drawdown_cash_lp
    @drawdown_cash_total
  end

  def drawdown_cash_investor
    object.call_amount
  end

  def drawdown_cash_investor_percent
    @drawdown_cash_investor_percent = drawdown_cash_total.zero? ? 0 : (object.call_amount / drawdown_cash_total) * 100
    @drawdown_cash_investor_percent
  end

  def drawdown_reinvest_lp
    @drawdown_reinvest_lp = committed_reinvest_lp unless defined?(@drawdown_reinvest_lp)
    @drawdown_reinvest_lp
  end

  def drawdown_reinvest_gp
    @drawdown_reinvest_gp = committed_reinvest_gp unless defined?(@drawdown_reinvest_gp)
    @drawdown_reinvest_gp
  end

  def drawdown_reinvest_total
    @drawdown_reinvest_total = drawdown_reinvest_gp + drawdown_reinvest_lp
    @drawdown_reinvest_total
  end

  def drawdown_reinvest_investor
    @drawdown_reinvest_investor = committed_reinvest_investor unless defined?(@drawdown_reinvest_investor)
    @drawdown_reinvest_investor
  end

  def drawdown_reinvest_investor_percent
    @drawdown_reinvest_investor_percent = drawdown_reinvest_total.zero? ? 0 : (drawdown_reinvest_investor / drawdown_reinvest_total) * 100
    @drawdown_reinvest_investor_percent
  end

  def dist_cash_lp
    return @dist_cash_lp if defined?(@dist_cash_lp)

    dist_cash_lp_cents = 0
    @lp_commitments.each do |comm|
      dist_cash_lp_cents += comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents)
    end
    @dist_cash_lp = Money.new(dist_cash_lp_cents, object.fund.currency)
  end

  def dist_cash_gp
    return @dist_cash_gp if defined?(@dist_cash_gp)

    dist_cash_gp_cents = 0
    @gp_commitments.each do |comm|
      dist_cash_gp_cents += comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents)
    end
    @dist_cash_gp = Money.new(dist_cash_gp_cents, object.fund.currency)
  end

  def dist_cash_total
    @dist_cash_total = dist_cash_gp + dist_cash_lp
    @dist_cash_total
  end

  def dist_cash_investor
    @dist_cash_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents), object.fund.currency)
    @dist_cash_investor
  end

  def dist_cash_investor_percent
    @dist_cash_investor_percent = dist_cash_total.zero? ? 0 : (dist_cash_investor / dist_cash_total) * 100
    @dist_cash_investor_percent
  end

  def dist_reinvest_lp
    @dist_reinvest_lp = committed_reinvest_lp unless defined?(@dist_reinvest_lp)
    @dist_reinvest_lp
  end

  def dist_reinvest_gp
    @dist_reinvest_gp = committed_reinvest_gp unless defined?(@dist_reinvest_gp)
    @dist_reinvest_gp
  end

  def dist_reinvest_total
    @dist_reinvest_total = dist_reinvest_gp + dist_reinvest_lp
    @dist_reinvest_total
  end

  def dist_reinvest_investor
    @dist_reinvest_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents), object.fund.currency)
    @dist_reinvest_investor
  end

  def dist_reinvest_investor_percent
    @dist_reinvest_investor_percent = dist_reinvest_total.zero? ? 0 : (dist_reinvest_investor / dist_reinvest_total) * 100
    @dist_reinvest_investor_percent
  end

  def percentage_drawdown_cash_lp
    committed_cash_lp.zero? ? 0 : (drawdown_cash_lp / committed_cash_lp) * 100
  end

  def percentage_drawdown_cash_gp
    committed_cash_gp.zero? ? 0 : (drawdown_cash_gp / committed_cash_gp) * 100
  end

  def percentage_drawdown_cash_total
    committed_cash_total.zero? ? 0 : (drawdown_cash_total / committed_cash_total) * 100
  end

  def percentage_drawdown_cash_investor
    committed_cash_investor.zero? ? 0 : (drawdown_cash_investor / committed_cash_investor) * 100
  end

  def undrawn_comm_lp
    committed_cash_lp - drawdown_cash_lp
  end

  def undrawn_comm_gp
    committed_cash_gp - drawdown_cash_gp
  end

  def undrawn_comm_total
    committed_cash_total - drawdown_cash_total
  end

  def undrawn_comm_investor
    committed_cash_investor - drawdown_cash_investor
  end

  def undrawn_comm_investor_percent
    undrawn_comm_total.zero? ? 0 : (undrawn_comm_investor / undrawn_comm_total) * 100
  end

  def percentage_unpaid_comm_lp
    committed_cash_lp.zero? ? 0 : (undrawn_comm_lp / committed_cash_lp) * 100
  end

  def percentage_unpaid_comm_gp
    committed_cash_gp.zero? ? 0 : (undrawn_comm_gp / committed_cash_gp) * 100
  end

  def percentage_unpaid_comm_total
    committed_cash_total.zero? ? 0 : (undrawn_comm_total / committed_cash_total) * 100
  end

  def percentage_unpaid_comm_investor
    committed_cash_investor.zero? ? 0 : (undrawn_comm_investor / committed_cash_investor) * 100
  end
end
