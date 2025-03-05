class CapitalCommitmentCallNoticeTemplateDecorator < CapitalCommitmentTemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper
  attr_reader :curr_date, :end_date, :currency

  def initialize(object)
    super
    @curr_date = object.json_fields['end_date']
    @end_date = (object.json_fields['end_date'] - 1.day).end_of_day
    @currency = object.fund.currency
    @cache = {} # Use a cache hash to store computed values
  end

  # === Helper Methods ===

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_f if part.respond_to?(:cents)
    total = total.cents.to_f if total.respond_to?(:cents)
    total.zero? ? 0 : (part / total) * 100
  end

  # === Improved Data Loading Methods with Caching ===

  # Get LP and GP commitments with caching
  def lp_commitments(end_date = nil)
    end_date ||= @curr_date
    key = "lp_commitments_#{end_date}"

    @cache[key] ||= begin
      lp_records = []
      object.fund.capital_commitments.where(commitment_date: ..end_date).find_each do |comm|
        lp_records << comm.id unless comm.fund_unit_setting&.gp_units
      end
      object.fund.capital_commitments.where(id: lp_records)
    end
  end

  def gp_commitments(end_date = nil)
    end_date ||= @curr_date
    key = "gp_commitments_#{end_date}"

    @cache[key] ||= begin
      gp_records = []
      object.fund.capital_commitments.where(commitment_date: ..end_date).find_each do |comm|
        gp_records << comm.id if comm.fund_unit_setting&.gp_units
      end
      object.fund.capital_commitments.where(id: gp_records)
    end
  end

  # Get LP and GP remittances with caching
  def lp_remittances(end_date = nil)
    end_date ||= @curr_date
    key = "lp_remittances_#{end_date}"

    @cache[key] ||= begin
      lp_remittance_ids = []
      lp_commitments(end_date).each do |comm|
        lp_remittance_ids += comm.capital_remittances.where(remittance_date: ..end_date).pluck(:id)
      end
      object.fund.capital_remittances.where(id: lp_remittance_ids)
    end
  end

  def gp_remittances(end_date = nil)
    end_date ||= @curr_date
    key = "gp_remittances_#{end_date}"

    @cache[key] ||= begin
      gp_remittance_ids = []
      gp_commitments(end_date).each do |comm|
        gp_remittance_ids += comm.capital_remittances.where(remittance_date: ..end_date).pluck(:id)
      end
      object.fund.capital_remittances.where(id: gp_remittance_ids)
    end
  end

  # Get distribution payments with caching
  def prior_dist_payments_lp
    @cache[:prior_dist_payments_lp] ||= begin
      prior_dist_payments_lp_ids = []
      lp_commitments.each do |comm|
        prior_dist_payments_lp_ids += comm.capital_distribution_payments.where(payment_date: ..@end_date).pluck(:id)
      end
      object.fund.capital_distribution_payments.where(id: prior_dist_payments_lp_ids)
    end
  end

  def prior_dist_payments_gp
    @cache[:prior_dist_payments_gp] ||= begin
      prior_dist_payments_gp_ids = []
      gp_commitments.each do |comm|
        prior_dist_payments_gp_ids += comm.capital_distribution_payments.where(payment_date: ..@end_date).pluck(:id)
      end
      object.fund.capital_distribution_payments.where(id: prior_dist_payments_gp_ids)
    end
  end

  def current_dist_payments_lp
    @cache[:current_dist_payments_lp] ||= begin
      current_dist_payments_lp_ids = []
      lp_commitments(@curr_date).each do |comm|
        current_dist_payments_lp_ids += comm.capital_distribution_payments.where(payment_date: @curr_date).pluck(:id)
      end
      object.fund.capital_distribution_payments.where(id: current_dist_payments_lp_ids)
    end
  end

  def current_dist_payments_gp
    @cache[:current_dist_payments_gp] ||= begin
      current_dist_payments_gp_ids = []
      gp_commitments(@curr_date).each do |comm|
        current_dist_payments_gp_ids += comm.capital_distribution_payments.where(payment_date: @curr_date).pluck(:id)
      end
      object.fund.capital_distribution_payments.where(id: current_dist_payments_gp_ids)
    end
  end

  # === Reinvestment Calculation Methods ===

  def committed_reinvest_lp_cents
    @cache[:committed_reinvest_lp_cents] ||= begin
      cents = 0
      lp_commitments(@curr_date).each do |comm|
        comm.capital_distribution_payments.where(payment_date: ..@curr_date).find_each do |dist|
          cents += dist.reinvestment_with_fees_cents
        end
      end
      cents
    end
  end

  def committed_reinvest_gp_cents
    @cache[:committed_reinvest_gp_cents] ||= begin
      cents = 0
      gp_commitments(@curr_date).each do |comm|
        comm.capital_distribution_payments.where(payment_date: ..@curr_date).find_each do |dist|
          cents += dist.reinvestment_with_fees_cents
        end
      end
      cents
    end
  end

  # === Business Logic Methods ===

  def committed_cash_lp
    @cache[:committed_cash_lp] ||= money_sum(lp_commitments(@curr_date), :committed_amount_cents)
  end

  def committed_cash_gp
    @cache[:committed_cash_gp] ||= money_sum(gp_commitments(@curr_date), :committed_amount_cents)
  end

  def committed_cash_total
    @cache[:committed_cash_total] ||= committed_cash_lp + committed_cash_gp
  end

  def committed_cash_investor
    object.committed_amount
  end

  def committed_cash_investor_percent
    percentage(committed_cash_investor, committed_cash_total)
  end

  def committed_reinvest_lp
    @cache[:committed_reinvest_lp] ||= Money.new(committed_reinvest_lp_cents, @currency)
  end

  def committed_reinvest_gp
    @cache[:committed_reinvest_gp] ||= Money.new(committed_reinvest_gp_cents, @currency)
  end

  def committed_reinvest_total
    @cache[:committed_reinvest_total] ||= committed_reinvest_lp + committed_reinvest_gp
  end

  def committed_reinvest_investor
    @cache[:committed_reinvest_investor] ||= money_sum(
      object.capital_distribution_payments.where(payment_date: ..@curr_date),
      :reinvestment_with_fees_cents
    )
  end

  def committed_reinvest_investor_percent
    percentage(committed_reinvest_investor, committed_reinvest_total)
  end

  # === Total Commitments ===

  def total_comm_lp
    @cache[:total_comm_lp] ||= committed_cash_lp + committed_reinvest_lp
  end

  def total_comm_gp
    @cache[:total_comm_gp] ||= committed_cash_gp + committed_reinvest_gp
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

  # === Percentages ===

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

  # === Drawdowns ===

  def drawdown_cash_lp
    @cache[:drawdown_cash_lp] ||= money_sum(lp_remittances(@curr_date), :call_amount_cents)
  end

  def drawdown_cash_gp
    @cache[:drawdown_cash_gp] ||= money_sum(gp_remittances(@curr_date), :call_amount_cents)
  end

  def drawdown_cash_total
    @cache[:drawdown_cash_total] ||= drawdown_cash_lp + drawdown_cash_gp
  end

  def drawdown_cash_investor
    @cache[:drawdown_cash_investor] ||= money_sum(object.capital_remittances.where(remittance_date: ..@curr_date), :call_amount_cents)
  end

  def drawdown_cash_investor_percent
    percentage(drawdown_cash_investor, drawdown_cash_total)
  end

  def drawdown_reinvest_lp
    committed_reinvest_lp
  end

  def drawdown_reinvest_gp
    committed_reinvest_gp
  end

  def drawdown_reinvest_total
    drawdown_reinvest_lp + drawdown_reinvest_gp
  end

  def drawdown_reinvest_investor
    committed_reinvest_investor
  end

  def drawdown_reinvest_investor_percent
    percentage(drawdown_reinvest_investor, drawdown_reinvest_total)
  end

  # === Total Drawdowns ===

  def total_drawdown_lp
    @cache[:total_drawdown_lp] ||= drawdown_cash_lp + drawdown_reinvest_lp
  end

  def total_drawdown_gp
    @cache[:total_drawdown_gp] ||= drawdown_cash_gp + drawdown_reinvest_gp
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

  # === Drawdown Percentages ===

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

  # === Undrawn Commitments ===

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

  # === Undrawn Percentages ===

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

  # === Distribution Cash ===

  def dist_cash_lp
    @cache[:dist_cash_lp] ||= money_sum(current_dist_payments_lp, :gross_payable_cents) - money_sum(current_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def dist_cash_gp
    @cache[:dist_cash_gp] ||= money_sum(current_dist_payments_lp, :gross_payable_cents) - money_sum(current_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def dist_cash_total
    @cache[:dist_cash_total] ||= dist_cash_lp + dist_cash_gp
  end

  def dist_cash_investor
    @cache[:dist_cash_investor] ||= money_sum(
      object.capital_distribution_payments.where(payment_date: ..@curr_date),
      :gross_payable_cents
    ) - money_sum(object.capital_distribution_payments.where(payment_date: ..@curr_date), :reinvestment_with_fees_cents)
  end

  def dist_cash_investor_percent
    percentage(dist_cash_investor, dist_cash_total)
  end

  # === Distribution Reinvest ===

  def dist_reinvest_lp
    committed_reinvest_lp
  end

  def dist_reinvest_gp
    committed_reinvest_gp
  end

  def dist_reinvest_total
    dist_reinvest_lp + dist_reinvest_gp
  end

  def dist_reinvest_investor
    committed_reinvest_investor
  end

  def dist_reinvest_investor_percent
    percentage(dist_reinvest_investor, dist_reinvest_total)
  end

  # === Total Distribution ===

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

  # === Aggregate Prior Distribution ===

  def agg_dist_prior_notice_lp
    @cache[:agg_dist_prior_notice_lp] ||= money_sum(prior_dist_payments_lp, :gross_payable_cents) - money_sum(prior_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_dist_prior_notice_gp
    @cache[:agg_dist_prior_notice_gp] ||= money_sum(prior_dist_payments_gp, :gross_payable_cents) - money_sum(prior_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_dist_prior_notice_total
    agg_dist_prior_notice_lp + agg_dist_prior_notice_gp
  end

  def agg_dist_prior_notice_investor
    @cache[:agg_dist_prior_notice_investor] ||= begin
      dist_prior_notice_investor_lp = prior_dist_payments_lp.where(folio_id: object.folio_id)
      dist_prior_notice_investor_gp = prior_dist_payments_gp.where(folio_id: object.folio_id)
      money_sum(dist_prior_notice_investor_lp, :gross_payable_cents) +
        money_sum(dist_prior_notice_investor_gp, :gross_payable_cents)
    end
  end

  def agg_dist_prior_notice_investor_percent
    percentage(agg_dist_prior_notice_investor, agg_dist_prior_notice_total)
  end

  # === Aggregate Current Distribution ===

  def agg_dist_current_notice_lp
    @cache[:agg_dist_current_notice_lp] ||= money_sum(current_dist_payments_lp, :gross_payable_cents) - money_sum(current_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_dist_current_notice_gp
    @cache[:agg_dist_current_notice_gp] ||= money_sum(current_dist_payments_gp, :gross_payable_cents) - money_sum(current_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_dist_current_notice_total
    agg_dist_current_notice_lp + agg_dist_current_notice_gp
  end

  def agg_dist_current_notice_investor
    @cache[:agg_dist_current_notice_investor] ||= money_sum(
      object.capital_distribution_payments.where(payment_date: @curr_date),
      :gross_payable_cents
    ) - money_sum(
      object.capital_distribution_payments.where(payment_date: @curr_date),
      :reinvestment_with_fees_cents
    )
  end

  def agg_dist_current_notice_investor_percent
    percentage(agg_dist_current_notice_investor, agg_dist_current_notice_total)
  end

  # === Aggregate Total Distribution ===

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

  # === Aggregate Reinvestment ===

  def agg_reinvest_prior_current_notice_lp
    @cache[:agg_reinvest_prior_current_notice_lp] ||= money_sum(prior_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_prior_current_notice_gp
    @cache[:agg_reinvest_prior_current_notice_gp] ||= money_sum(prior_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_prior_current_notice_total
    agg_reinvest_prior_current_notice_lp + agg_reinvest_prior_current_notice_gp
  end

  def agg_reinvest_prior_current_notice_investor
    @cache[:agg_reinvest_prior_current_notice_investor] ||= begin
      dist_prior_notice_investor_lp = prior_dist_payments_lp.where(folio_id: object.folio_id)
      dist_prior_notice_investor_gp = prior_dist_payments_gp.where(folio_id: object.folio_id)
      money_sum(dist_prior_notice_investor_lp, :reinvestment_with_fees_cents) +
        money_sum(dist_prior_notice_investor_gp, :reinvestment_with_fees_cents)
    end
  end

  def agg_reinvest_prior_current_notice_investor_percent
    percentage(agg_reinvest_prior_current_notice_investor, agg_reinvest_prior_current_notice_total)
  end

  # === Current Reinvestment ===

  def agg_reinvest_current_notice_lp
    @cache[:agg_reinvest_current_notice_lp] ||= money_sum(current_dist_payments_lp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_current_notice_gp
    @cache[:agg_reinvest_current_notice_gp] ||= money_sum(current_dist_payments_gp, :reinvestment_with_fees_cents)
  end

  def agg_reinvest_current_notice_total
    agg_reinvest_current_notice_lp + agg_reinvest_current_notice_gp
  end

  def agg_reinvest_current_notice_investor
    @cache[:agg_reinvest_current_notice_investor] ||= money_sum(
      object.capital_distribution_payments.where(payment_date: @curr_date),
      :reinvestment_with_fees_cents
    )
  end

  def agg_reinvest_current_notice_investor_percent
    percentage(agg_reinvest_current_notice_investor, agg_reinvest_current_notice_total)
  end

  # === Total Reinvestment ===

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
