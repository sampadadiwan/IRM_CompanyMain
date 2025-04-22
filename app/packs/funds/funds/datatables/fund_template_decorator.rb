class FundTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper
  include Memoized

  attr_reader :remittance_date, :currency, :capital_commitment, :capital_remittance

  def initialize(object)
    super
    @remittance_date = object.as_of_date
    @currency = object.currency
    @capital_remittance = object.json_fields["capital_remittance"]
    @capital_commitment = @capital_remittance.capital_commitment
  end

  # === Helpers ===

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_d if part.respond_to?(:cents)
    total = total.cents.to_d if total.respond_to?(:cents)
    return 0 if total.zero?

    (part.to_d / total.to_d) * 100
  end

  # === Fund Base ===

  def fund_as_of = object
  memoize :fund_as_of

  def fund_commitments = fund_as_of.capital_commitments
  memoize :fund_commitments

  def fund_commitments_lp = fund_commitments.lp(fund_as_of.id)
  memoize :fund_commitments_lp

  def fund_commitments_gp = fund_commitments.gp(fund_as_of.id)
  memoize :fund_commitments_gp

  def fund_remittances_lp = fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  memoize :fund_remittances_lp

  def fund_remittances_gp = fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  memoize :fund_remittances_gp

  def fund_dist_payments = fund_as_of.capital_distribution_payments
  memoize :fund_dist_payments

  def fund_dist_payments_lp = fund_dist_payments.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  memoize :fund_dist_payments_lp

  def fund_dist_payments_gp = fund_dist_payments.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  memoize :fund_dist_payments_gp

  def dist_payments = @capital_commitment.capital_distribution_payments.where(payment_date: ..@remittance_date)
  memoize :dist_payments

  #=== Committed Cash Helpers ===#

  def committed_cash_lp = money_sum(fund_commitments_lp, :committed_amount_cents)
  memoize :committed_cash_lp

  def committed_cash_gp = money_sum(fund_commitments_gp, :committed_amount_cents)
  memoize :committed_cash_gp

  def committed_reinvest_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_lp

  def committed_reinvest_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_gp

  def committed_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_investor

  def committed_cash_investor_percent = percentage(@capital_commitment.committed_amount_cents, fund_commitments.sum(:committed_amount_cents))

  def committed_reinvest_investor_percent = percentage(committed_reinvest_investor.cents, fund_dist_payments.sum(:reinvestment_with_fees_cents))

  #=== Commitment Totals ===#

  def total_comm_lp = committed_cash_lp + committed_reinvest_lp
  memoize :total_comm_lp

  def total_comm_gp = committed_cash_gp + committed_reinvest_gp
  memoize :total_comm_gp

  def total_comm_fund = total_comm_lp + total_comm_gp

  def total_comm_investor = @capital_commitment.committed_amount + committed_reinvest_investor
  memoize :total_comm_investor

  def total_comm_investor_percent = percentage(total_comm_investor.cents, total_comm_fund.cents)

  #=== Reinvestment Ratios ===#

  def percent_reinvest_to_cash_lp = percentage(committed_reinvest_lp, committed_cash_lp)
  def percent_reinvest_to_cash_gp = percentage(committed_reinvest_gp, committed_cash_gp)
  def percent_reinvest_to_cash_total = percentage(committed_reinvest_lp + committed_reinvest_gp, committed_cash_lp + committed_cash_gp)
  def percent_reinvest_to_cash_investor = percentage(committed_reinvest_investor.cents, @capital_commitment.committed_amount_cents)

  #=== Drawdowns ===#

  def drawdown_cash_lp = money_sum(fund_remittances_lp, :call_amount_cents)
  memoize :drawdown_cash_lp

  def drawdown_cash_gp = money_sum(fund_remittances_gp, :call_amount_cents)
  memoize :drawdown_cash_gp

  def drawdown_cash_investor = money_sum(@capital_commitment.capital_remittances.where(remittance_date: ..@remittance_date), :call_amount_cents)
  memoize :drawdown_cash_investor

  def drawdown_cash_investor_percent = percentage(drawdown_cash_investor.cents, fund_as_of.capital_remittances.sum(:call_amount_cents))

  def drawdown_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :drawdown_reinvest_investor

  def drawdown_reinvest_investor_percent = percentage(drawdown_reinvest_investor.cents, fund_dist_payments.sum(:reinvestment_with_fees_cents))

  def total_drawdown_lp = drawdown_cash_lp + money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :total_drawdown_lp

  def total_drawdown_gp = drawdown_cash_gp + money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :total_drawdown_gp

  def total_drawdown_fund = total_drawdown_lp + total_drawdown_gp
  memoize :total_drawdown_fund

  def total_drawdown_investor = drawdown_cash_investor + drawdown_reinvest_investor
  memoize :total_drawdown_investor

  def total_drawdown_investor_percent = percentage(total_drawdown_investor.cents, total_drawdown_fund.cents)

  def percent_drawdown_cash_lp = percentage(drawdown_cash_lp, committed_cash_lp)
  def percent_drawdown_cash_gp = percentage(drawdown_cash_gp, committed_cash_gp)
  def percent_drawdown_cash_total = percentage(drawdown_cash_lp + drawdown_cash_gp, committed_cash_lp + committed_cash_gp)
  def percent_drawdown_cash_investor = percentage(drawdown_cash_investor, @capital_commitment.committed_amount)

  #=== Undrawn Commitments ===#

  def undrawn_comm_lp = total_comm_lp - total_drawdown_lp
  def undrawn_comm_gp = total_comm_gp - total_drawdown_gp
  def undrawn_comm_total = undrawn_comm_lp + undrawn_comm_gp
  def undrawn_comm_investor = @capital_commitment.committed_amount - drawdown_cash_investor
  def undrawn_comm_investor_percent = percentage(undrawn_comm_investor, undrawn_comm_total)

  def percent_unpaid_comm_lp = percentage(undrawn_comm_lp.cents, committed_cash_lp.cents)
  def percent_unpaid_comm_gp = percentage(undrawn_comm_gp.cents, committed_cash_gp.cents)
  def percent_unpaid_comm_total = percentage(undrawn_comm_total.cents, (committed_cash_lp + committed_cash_gp).cents)
  def percent_unpaid_comm_investor = percentage(undrawn_comm_investor.cents, @capital_commitment.committed_amount_cents)

  # === Distribution Cash ===
  # === Distribution Cash & Reinvestment ===

  def dist_cash_investor = Money.new(dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :dist_cash_investor

  def dist_cash_total = Money.new(fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :dist_cash_total

  def dist_cash_investor_percent = percentage(dist_cash_investor.cents, dist_cash_total.cents)

  def dist_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  def dist_reinvest_investor_percent = percentage(dist_reinvest_investor.cents, fund_dist_payments.sum(:reinvestment_with_fees_cents))

  def total_dist_investor = dist_cash_investor + dist_reinvest_investor
  def total_dist_investor_percent = percentage(total_dist_investor.cents, total_dist_fund.cents)

  def dist_cash_lp = Money.new(fund_dist_payments_lp.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  def dist_cash_gp = Money.new(fund_dist_payments_gp.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)

  def dist_reinvest_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  def dist_reinvest_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)

  def total_dist_lp = dist_cash_lp + dist_reinvest_lp
  def total_dist_gp = dist_cash_gp + dist_reinvest_gp
  def total_dist_fund = total_dist_lp + total_dist_gp

  # === Prior / Current / Incl Distributions ===

  def agg_dist_prior_notice_investor = Money.new(dist_payments.where(payment_date: ..@remittance_date.yesterday.end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_prior_notice_investor

  def agg_dist_prior_notice_investor_percent = percentage(agg_dist_prior_notice_investor.cents, fund_dist_payments.where(payment_date: ..@remittance_date.yesterday.end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents"))

  def agg_dist_curr_notice_investor = Money.new(dist_payments.where(payment_date: @remittance_date).sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_curr_notice_investor

  def agg_dist_curr_notice_investor_percent = percentage(agg_dist_curr_notice_investor.cents, fund_dist_payments.where(payment_date: @remittance_date).sum("gross_payable_cents - reinvestment_with_fees_cents"))

  def agg_dist_incl_curr_notice_investor = Money.new(dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_incl_curr_notice_investor

  def agg_dist_incl_curr_notice_investor_percent = percentage(agg_dist_incl_curr_notice_investor.cents, fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"))

  # === Reinvestment Prior / Curr / Incl ===

  def agg_reinvest_prior_curr_notice_investor = money_sum(dist_payments.where(payment_date: ..@remittance_date.yesterday.end_of_day), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_prior_curr_notice_investor

  def agg_reinvest_prior_curr_notice_investor_percent = percentage(agg_reinvest_prior_curr_notice_investor.cents, fund_dist_payments.where(payment_date: ..@remittance_date.yesterday.end_of_day).sum("reinvestment_with_fees_cents"))

  def agg_reinvest_curr_notice_investor = money_sum(dist_payments.where(payment_date: @remittance_date), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_curr_notice_investor

  def agg_reinvest_curr_notice_investor_percent = percentage(agg_reinvest_curr_notice_investor.cents, fund_dist_payments.where(payment_date: @remittance_date).sum("reinvestment_with_fees_cents"))

  def agg_reinvest_incl_curr_notice_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_incl_curr_notice_investor

  def agg_reinvest_incl_curr_notice_investor_percent = percentage(agg_reinvest_incl_curr_notice_investor.cents, fund_dist_payments.sum("reinvestment_with_fees_cents"))

  # === Drawdowns ===
  # === Drawdown Cash ===

  def prior_calls = fund_as_of.capital_calls.where(call_date: ..@remittance_date.yesterday.end_of_day)
  memoize :prior_calls

  def drawdown_cash_prior_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id)
        .where(remittance_date: ..@remittance_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id)),
      :computed_amount_cents
    )
  end
  memoize :drawdown_cash_prior_notice_investor

  def drawdown_cash_prior_notice_investor_percent
    percentage(
      drawdown_cash_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@remittance_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:computed_amount_cents)
    )
  end

  def drawdown_cash_curr_notice_investor_percent
    percentage(
      @capital_remittance.computed_amount,
      fund_as_of.capital_remittances
        .where(remittance_date: @remittance_date)
        .where(capital_call_id: @capital_remittance.capital_call_id)
        .sum(:computed_amount_cents)
    )
  end

  def drawdown_cash_incl_curr_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id, remittance_date: ..@remittance_date),
      :computed_amount_cents
    )
  end
  memoize :drawdown_cash_incl_curr_notice_investor

  def drawdown_cash_incl_curr_notice_investor_percent
    percentage(
      drawdown_cash_incl_curr_notice_investor.cents,
      fund_as_of.capital_remittances.sum(:computed_amount_cents)
    )
  end

  # === Drawdown Fees ===

  def drawdown_fees_prior_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id)
        .where(remittance_date: ..@remittance_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id)),
      :capital_fee_cents
    )
  end
  memoize :drawdown_fees_prior_notice_investor

  def drawdown_fees_prior_notice_investor_percent
    percentage(
      drawdown_fees_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@remittance_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:capital_fee_cents)
    )
  end

  def drawdown_fees_curr_notice_investor_percent
    percentage(
      @capital_remittance.capital_fee_cents,
      fund_as_of.capital_remittances
        .where(remittance_date: @remittance_date)
        .where(capital_call_id: @capital_remittance.capital_call_id)
        .sum(:capital_fee_cents)
    )
  end

  def drawdown_fees_incl_curr_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id, remittance_date: ..@remittance_date),
      :capital_fee_cents
    )
  end
  memoize :drawdown_fees_incl_curr_notice_investor

  def drawdown_fees_incl_curr_notice_investor_percent
    percentage(
      drawdown_fees_incl_curr_notice_investor.cents,
      fund_as_of.capital_remittances.sum(:capital_fee_cents)
    )
  end

  # === Aggregate Drawdowns ===

  def agg_drawdown_prior_notice_investor = drawdown_cash_prior_notice_investor + drawdown_fees_prior_notice_investor

  def agg_drawdown_prior_notice_investor_percent
    percentage(
      agg_drawdown_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@remittance_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:call_amount_cents)
    )
  end

  def agg_drawdown_curr_notice_investor_percent
    percentage(
      @capital_remittance.call_amount_cents,
      fund_as_of.capital_remittances
        .where(remittance_date: @remittance_date)
        .where(capital_call_id: @capital_remittance.capital_call_id)
        .sum(:call_amount_cents)
    )
  end

  def agg_drawdown_incl_curr_notice_investor
    money_sum(
      fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id),
      :call_amount_cents
    )
  end
  memoize :agg_drawdown_incl_curr_notice_investor

  def agg_drawdown_incl_curr_notice_investor_percent
    percentage(
      agg_drawdown_incl_curr_notice_investor.cents,
      fund_as_of.capital_remittances.sum(:call_amount_cents)
    )
  end

  # === Undrawn Commitments ===

  def undrawn_comm_prior_notice_lp
    last_call = prior_calls.order(:call_date).last
    last_remittances = last_call ? last_call.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id)).where(remittance_date: ..@remittance_date.yesterday.end_of_day) : []

    committed_amt = if last_call && last_remittances.present?
                      money_sum(last_remittances, :committed_amount_cents)
                    else
                      current = @capital_remittance.capital_call.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id), remittance_date: ..@remittance_date)
                      current.present? ? money_sum(current, :committed_amount_cents) : Money.new(0, @currency)
                    end

    committed_amt - money_sum(fund_remittances_lp.where(remittance_date: ..@remittance_date.yesterday.end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_lp

  def undrawn_comm_prior_notice_gp
    last_call = prior_calls.order(:call_date).last
    last_remittances = last_call ? last_call.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id)).where(remittance_date: ..@remittance_date.yesterday.end_of_day) : []

    committed_amt = if last_call && last_remittances.present?
                      money_sum(last_remittances, :committed_amount_cents)
                    else
                      current = @capital_remittance.capital_call.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id), remittance_date: ..@remittance_date)
                      current.present? ? money_sum(current, :committed_amount_cents) : Money.new(0, @currency)
                    end

    committed_amt - money_sum(fund_remittances_gp.where(remittance_date: ..@remittance_date.yesterday.end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_gp

  def undrawn_comm_prior_notice_total = undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp

  def undrawn_comm_prior_notice_investor
    Money.new(
      @capital_remittance.committed_amount_cents - agg_drawdown_prior_notice_investor.cents,
      @currency
    )
  end

  def undrawn_comm_prior_notice_investor_percent
    percentage(undrawn_comm_prior_notice_investor, undrawn_comm_prior_notice_total)
  end

  def undrawn_comm_curr_notice_lp
    Money.new(
      committed_cash_lp.cents - fund_remittances_lp.sum(:call_amount_cents),
      @currency
    )
  end
  memoize :undrawn_comm_curr_notice_lp

  def undrawn_comm_curr_notice_gp
    Money.new(
      committed_cash_gp.cents - fund_remittances_gp.sum(:call_amount_cents),
      @currency
    )
  end
  memoize :undrawn_comm_curr_notice_gp

  def undrawn_comm_curr_notice_total = undrawn_comm_curr_notice_lp + undrawn_comm_curr_notice_gp
  memoize :undrawn_comm_curr_notice_total

  def undrawn_comm_curr_notice_investor
    Money.new(
      @capital_remittance.committed_amount_cents - agg_drawdown_incl_curr_notice_investor.cents,
      @currency
    )
  end

  def undrawn_comm_curr_notice_investor_percent
    percentage(undrawn_comm_curr_notice_investor, undrawn_comm_curr_notice_total)
  end

  def undrawn_comm_incl_curr_notice_lp = undrawn_comm_curr_notice_lp
  def undrawn_comm_incl_curr_notice_gp = undrawn_comm_curr_notice_gp
  def undrawn_comm_incl_curr_notice_total = undrawn_comm_curr_notice_total
  def undrawn_comm_incl_curr_notice_investor = undrawn_comm_curr_notice_investor

  def undrawn_comm_incl_curr_notice_investor_percent
    percentage(undrawn_comm_incl_curr_notice_investor, undrawn_comm_incl_curr_notice_total)
  end
end
