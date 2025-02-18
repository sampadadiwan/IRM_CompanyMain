class CapitalCommitmentCallNoticeTemplateDecorator < TemplateDecorator
  include CurrencyHelper
  attr_reader :gp_commitments, :lp_commitments

  def initialize(object)
    super
    @end_date = Time.zone.now.end_of_day
    @currency = object.fund.currency
  end

  def init_lp_gp_commitments
    if @gp_commitments.nil? || @lp_commitments.nil?
      gp_records = []
      lp_records = []

      object.fund.capital_commitments.where(commitment_date: ..@end_date).find_each do |comm|
        if comm.fund_unit_setting&.gp_units
          gp_records << comm.id
        else
          lp_records << comm.id
        end
      end

      # Convert arrays into ActiveRecord-like collections
      @gp_commitments = object.fund.capital_commitments.where(id: gp_records)
      @lp_commitments = object.fund.capital_commitments.where(id: lp_records)
    end
  end

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    total.zero? ? 0 : (part / total) * 100
  end

  def committed_cash_lp
    init_lp_gp_commitments
    @committed_cash_lp ||= money_sum(@lp_commitments, :committed_amount_cents)
  end

  def committed_cash_gp
    init_lp_gp_commitments
    @committed_cash_gp ||= money_sum(@gp_commitments, :committed_amount_cents)
  end

  def committed_cash_total
    @committed_cash_total ||= committed_cash_lp + committed_cash_gp
  end

  def committed_cash_investor
    object.committed_amount
  end

  def committed_cash_investor_percent
    percentage(committed_cash_investor, committed_cash_total)
  end

  def committed_reinvest_lp
    init_lp_gp_commitments
    @committed_reinvest_lp ||= money_sum(@lp_commitments, :committed_reinvest_cents)
  end

  def committed_reinvest_gp
    init_lp_gp_commitments
    @committed_reinvest_gp ||= money_sum(@gp_commitments, :committed_reinvest_cents)
  end

  def committed_reinvest_total
    @committed_reinvest_total ||= committed_reinvest_lp + committed_reinvest_gp
  end

  def committed_reinvest_investor
    @committed_reinvest_investor ||= money_sum(object.capital_distribution_payments.where(payment_date: ..@end_date), :reinvestment_with_fees_cents)
  end

  def committed_reinvest_investor_percent
    percentage(committed_reinvest_investor, committed_reinvest_total)
  end

  def drawdown_cash_lp
    init_lp_gp_commitments
    @drawdown_cash_lp ||= money_sum(@lp_commitments, :call_amount_cents)
  end

  def drawdown_cash_gp
    init_lp_gp_commitments
    @drawdown_cash_gp ||= money_sum(@gp_commitments, :call_amount_cents)
  end

  def drawdown_cash_total
    @drawdown_cash_total ||= drawdown_cash_lp + drawdown_cash_gp
  end

  def drawdown_cash_investor
    object.call_amount
  end

  def drawdown_cash_investor_percent
    percentage(drawdown_cash_investor, drawdown_cash_total)
  end

  def dist_cash_lp
    init_lp_gp_commitments
    @dist_cash_lp ||= money_sum(@lp_commitments.joins(:capital_distribution_payments).where(capital_distribution_payments: { payment_date: ..@end_date }), :gross_payable_cents)
  end

  def dist_cash_gp
    init_lp_gp_commitments
    @dist_cash_gp ||= money_sum(@gp_commitments.joins(:capital_distribution_payments).where(capital_distribution_payments: { payment_date: ..@end_date }), :gross_payable_cents)
  end

  def dist_cash_total
    @dist_cash_total ||= dist_cash_lp + dist_cash_gp
  end

  def dist_cash_investor
    @dist_cash_investor ||= money_sum(object.capital_distribution_payments.where(payment_date: ..@end_date), :gross_payable_cents)
  end

  def dist_cash_investor_percent
    percentage(dist_cash_investor, dist_cash_total)
  end

  def percentage_drawdown_cash_lp
    percentage(drawdown_cash_lp, committed_cash_lp)
  end

  def percentage_drawdown_cash_gp
    percentage(drawdown_cash_gp, committed_cash_gp)
  end

  def percentage_drawdown_cash_total
    percentage(drawdown_cash_total, committed_cash_total)
  end

  def percentage_drawdown_cash_investor
    percentage(drawdown_cash_investor, committed_cash_investor)
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
    percentage(undrawn_comm_investor, undrawn_comm_total)
  end

  def percentage_unpaid_comm_lp
    percentage(undrawn_comm_lp, committed_cash_lp)
  end

  def percentage_unpaid_comm_gp
    percentage(undrawn_comm_gp, committed_cash_gp)
  end

  def percentage_unpaid_comm_total
    percentage(undrawn_comm_total, committed_cash_total)
  end

  def percentage_unpaid_comm_investor
    percentage(undrawn_comm_investor, committed_cash_investor)
  end
end
