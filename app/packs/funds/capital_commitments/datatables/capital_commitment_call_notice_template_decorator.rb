class CapitalCommitmentCallNoticeTemplateDecorator < CapitalCommitmentTemplateDecorator # rubocop:disable Metrics/ClassLength
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
    return @committed_reinvest_lp if defined?(@committed_reinvest_lp)

    init_lp_gp_commitments
    committed_reinvest_lp_cents = 0
    @lp_commitments.each do |comm|
      comm.capital_distribution_payments.where(payment_date: ..@end_date).find_each do |dist|
        committed_reinvest_lp_cents += dist.reinvestment_with_fees_cents
      end
    end
    @committed_reinvest_lp = Money.new(committed_reinvest_lp_cents, @currency)
  end

  def committed_reinvest_gp
    return @committed_reinvest_gp if defined?(@committed_reinvest_gp)

    init_lp_gp_commitments
    committed_reinvest_gp_cents = 0
    @gp_commitments.each do |comm|
      comm.capital_distribution_payments.where(payment_date: ..@end_date).find_each do |dist|
        committed_reinvest_gp_cents += dist.reinvestment_with_fees_cents
      end
    end
    @committed_reinvest_gp = Money.new(committed_reinvest_gp_cents, @currency)
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

  def total_comm_lp
    @total_comm_lp ||= committed_cash_lp + committed_reinvest_lp
  end

  def total_comm_gp
    @total_comm_gp ||= committed_cash_gp + committed_reinvest_gp
  end

  def total_comm_fund
    total_comm_lp + total_comm_gp
  end

  def total_comm_investor
    committed_cash_investor + committed_reinvest_investor
  end

  def total_comm_investor_percent
    percentage(total_comm_investor, total_comm_fund)
  end

  def percent_reinvest_to_cash_lp
    percentage(committed_reinvest_lp, committed_cash_lp)
  end

  def percent_reinvest_to_cash_gp
    percentage(committed_reinvest_gp, committed_cash_gp)
  end

  def percent_reinvest_to_cash_total
    percentage(committed_reinvest_total, committed_cash_total)
  end

  def percent_reinvest_to_cash_investor
    percentage(committed_reinvest_investor, committed_cash_investor)
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

  def drawdown_reinvest_lp
    @drawdown_reinvest_lp ||= committed_reinvest_lp
  end

  def drawdown_reinvest_gp
    @drawdown_reinvest_gp ||= committed_reinvest_gp
  end

  def drawdown_reinvest_total
    drawdown_reinvest_lp + drawdown_reinvest_gp
  end

  def drawdown_reinvest_investor
    @drawdown_reinvest_investor ||= committed_reinvest_investor
  end

  def drawdown_reinvest_investor_percent
    percentage(drawdown_reinvest_investor, drawdown_reinvest_total)
  end

  def total_drawdown_lp
    @total_drawdown_lp ||= drawdown_cash_lp + drawdown_reinvest_lp
  end

  def total_drawdown_gp
    @total_drawdown_gp ||= drawdown_cash_gp + drawdown_reinvest_gp
  end

  def total_drawdown_fund
    total_drawdown_lp + total_drawdown_gp
  end

  def total_drawdown_investor
    drawdown_cash_investor + drawdown_reinvest_investor
  end

  def total_drawdown_investor_percent
    percentage(total_drawdown_investor, total_drawdown_fund)
  end

  def percent_drawdown_cash_lp
    percentage(drawdown_cash_lp, committed_cash_lp)
  end

  def percent_drawdown_cash_gp
    percentage(drawdown_cash_gp, committed_cash_gp)
  end

  def percent_drawdown_cash_total
    percentage(drawdown_cash_total, committed_cash_total)
  end

  def percent_drawdown_cash_investor
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

  def dist_reinvest_lp
    @dist_reinvest_lp ||= committed_reinvest_lp
  end

  def dist_reinvest_gp
    @dist_reinvest_gp ||= committed_reinvest_gp
  end

  def dist_reinvest_total
    @dist_reinvest_total ||= dist_reinvest_lp + dist_reinvest_gp
  end

  def dist_reinvest_investor
    @dist_reinvest_investor ||= money_sum(object.capital_distribution_payments.where(payment_date: ..@end_date), :reinvestment_with_fees_cents)
  end

  def dist_reinvest_investor_percent
    percentage(dist_reinvest_investor, dist_reinvest_total)
  end

  def total_dist_lp
    dist_cash_lp + dist_reinvest_lp
  end

  def total_dist_gp
    dist_cash_gp + dist_reinvest_gp
  end

  def total_dist_fund
    total_dist_lp + total_dist_gp
  end

  def total_dist_investor
    dist_cash_investor + dist_reinvest_investor
  end

  def total_dist_investor_percent
    percentage(total_dist_investor, total_dist_fund)
  end

  ### SECTION C AGGREGATE REINVESTMENT ###

  def init_prior_distribution_payments
    if @prior_dist_payments_lp.nil? || @prior_dist_payments_gp.nil?
      prior_dist_payments_lp_ids = []
      prior_dist_payments_gp_ids = []

      init_lp_gp_commitments
      @lp_commitments.each do |comm|
        ids = comm.capital_distribution_payments.where(payment_date: ..@end_date).pluck(:id)
        prior_dist_payments_lp_ids += ids
      end

      @gp_commitments.each do |comm|
        ids = comm.capital_distribution_payments.where(payment_date: ..@end_date).pluck(:id)
        prior_dist_payments_gp_ids += ids
      end

      @prior_dist_payments_lp = object.capital_distribution_payments.where(id: prior_dist_payments_lp_ids)
      @prior_dist_payments_gp = object.capital_distribution_payments.where(id: prior_dist_payments_gp_ids)
    end
  end

  def init_current_distribution_payments
    if @current_dist_payments_lp.nil? || @current_dist_payments_gp.nil?
      current_dist_payments_lp_ids = []
      current_dist_payments_gp_ids = []

      init_lp_gp_commitments
      @lp_commitments.each do |comm|
        ids = comm.capital_distribution_payments.where(payment_date: @end_date).pluck(:id)
        current_dist_payments_lp_ids += ids
      end

      @gp_commitments.each do |comm|
        ids = comm.capital_distribution_payments.where(payment_date: @end_date).pluck(:id)
        current_dist_payments_gp_ids += ids
      end

      @current_dist_payments_lp = object.capital_distribution_payments.where(id: current_dist_payments_lp_ids)
      @current_dist_payments_gp = object.capital_distribution_payments.where(id: current_dist_payments_gp_ids)
    end
  end

  # discuss how to get all dist before current dist
  def agg_dist_prior_notice_lp
    init_prior_distribution_payments

    @agg_dist_prior_notice_lp ||= money_sum(@prior_dist_payments_lp, :gross_payable_cents)
  end

  def agg_dist_prior_notice_gp
    init_prior_distribution_payments

    @agg_dist_prior_notice_gp ||= money_sum(@prior_dist_payments_gp, :gross_payable_cents)
  end

  def agg_dist_prior_notice_total
    agg_dist_prior_notice_lp + agg_dist_prior_notice_gp
  end

  def agg_dist_prior_notice_investor
    return @agg_dist_prior_notice_investor if @agg_dist_prior_notice_investor
    init_prior_distribution_payments

    dist_prior_notice_investor_lp = @prior_dist_payments_lp.where(folio_id: object.folio_id)
    dist_prior_notice_investor_gp = @prior_dist_payments_gp.where(folio_id: object.folio_id)

    @agg_dist_prior_notice_investor = money_sum(dist_prior_notice_investor_lp, :gross_payable_cents) + money_sum(dist_prior_notice_investor_gp, :gross_payable_cents)
  end

  def agg_dist_prior_notice_investor_percent
    percentage(agg_dist_prior_notice_investor, agg_dist_prior_notice_total)
  end

  def agg_dist_current_notice_lp
    init_current_distribution_payments

    @agg_dist_current_notice_lp ||= money_sum(@current_dist_payments_lp, :gross_payable_cents)
  end

  def agg_dist_current_notice_gp
    init_current_distribution_payments

    @agg_dist_current_notice_gp ||= money_sum(@current_dist_payments_gp, :gross_payable_cents)
  end

  def agg_dist_current_notice_total
    agg_dist_current_notice_lp + agg_dist_current_notice_gp
  end

  def agg_dist_current_notice_investor
    @agg_dist_current_notice_investor ||= money_sum(object.capital_distribution_payments.where(payment_date: @end_date), :gross_payable_cents)
  end

  def agg_dist_current_notice_investor_percent
    percentage(agg_dist_current_notice_investor, agg_dist_current_notice_total)
  end

  def agg_dist_incl_current_notice_lp
    agg_dist_prior_notice_lp + agg_dist_current_notice_lp
  end

  def agg_dist_incl_current_notice_gp
    agg_dist_prior_notice_gp + agg_dist_current_notice_gp
  end

  def agg_dist_incl_current_notice_total
    agg_dist_prior_notice_total + agg_dist_current_notice_total
  end

  def agg_dist_incl_current_notice_investor
    agg_dist_prior_notice_investor + agg_dist_current_notice_investor
  end

  def agg_dist_incl_current_notice_investor_percent
    percentage(agg_dist_incl_current_notice_investor, agg_dist_incl_current_notice_total)
  end

  def agg_reinvest_prior_current_notice_lp
    init_prior_distribution_payments

    @agg_reinvest_prior_current_notice_lp ||= money_sum(@prior_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_prior_current_notice_gp
    init_prior_distribution_payments

    @agg_reinvest_prior_current_notice_gp ||= money_sum(@prior_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_prior_current_notice_total
    agg_reinvest_prior_current_notice_lp + agg_reinvest_prior_current_notice_gp
  end

  def agg_reinvest_prior_current_notice_investor
    return @agg_reinvest_prior_current_notice_investor if @agg_reinvest_prior_current_notice_investor
    init_prior_distribution_payments

    dist_prior_notice_investor_lp = @prior_dist_payments_lp.where(folio_id: object.folio_id)
    dist_prior_notice_investor_gp = @prior_dist_payments_gp.where(folio_id: object.folio_id)

    @agg_reinvest_prior_current_notice_investor = money_sum(dist_prior_notice_investor_lp, :reinvestment_with_fees_cents) + money_sum(dist_prior_notice_investor_gp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_prior_current_notice_investor_percent
    percentage(agg_reinvest_prior_current_notice_investor, agg_reinvest_prior_current_notice_total)
  end

  def agg_reinvest_current_notice_lp
    init_current_distribution_payments

    @agg_reinvest_current_notice_lp ||= money_sum(@current_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_current_notice_gp
    init_current_distribution_payments

    @agg_reinvest_current_notice_gp ||= money_sum(@current_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_current_notice_total
    agg_reinvest_current_notice_lp + agg_reinvest_current_notice_gp
  end

  def agg_reinvest_current_notice_investor
    @agg_reinvest_current_notice_investor ||= money_sum(object.capital_distribution_payments.where(payment_date: @end_date), :reinvestment_with_fees_cents)
  end

  def agg_reinvest_current_notice_investor_percent
    percentage(agg_reinvest_current_notice_investor, agg_reinvest_current_notice_total)
  end

  def agg_reinvest_incl_current_notice_lp
    agg_reinvest_prior_current_notice_lp + agg_reinvest_current_notice_lp
  end

  def agg_reinvest_incl_current_notice_gp
    agg_reinvest_prior_current_notice_gp + agg_reinvest_current_notice_gp
  end

  def agg_reinvest_incl_current_notice_total
    agg_reinvest_prior_current_notice_total + agg_reinvest_current_notice_total
  end

  def agg_reinvest_incl_current_notice_investor
    agg_reinvest_prior_current_notice_investor + agg_reinvest_current_notice_investor
  end

  def agg_reinvest_incl_current_notice_investor_percent
    percentage(agg_reinvest_incl_current_notice_investor, agg_reinvest_incl_current_notice_total)
  end
end
