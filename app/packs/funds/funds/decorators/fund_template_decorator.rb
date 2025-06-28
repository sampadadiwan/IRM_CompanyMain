class FundTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper
  include Memoized

  attr_reader :as_of_date, :currency, :capital_commitment, :capital_remittance

  def initialize(object)
    super
    @as_of_date = object.as_of_date
    @currency = object.currency
    @capital_remittance = object.json_fields["capital_remittance"]
    @capital_distribution_payment = object.json_fields["capital_distribtion_payment"]

    @capital_commitment = if @capital_remittance
                            @capital_remittance.capital_commitment
                          elsif @capital_distribution_payment
                            @capital_distribution_payment.capital_commitment
                          end
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
  # Fund As Of is the fund object at the time of the remittance date
  def fund_as_of = object
  memoize :fund_as_of

  # Commitments of type All, LP and GP as of the remittance date
  def fund_commitments = fund_as_of.capital_commitments
  memoize :fund_commitments

  def fund_commitments_lp = fund_commitments.lp(fund_as_of.id)
  memoize :fund_commitments_lp

  def fund_commitments_gp = fund_commitments.gp(fund_as_of.id)
  memoize :fund_commitments_gp

  # Remittances of type LP and GP as of the remittance date
  def fund_remittances_lp = fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  memoize :fund_remittances_lp

  def fund_remittances_gp = fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  memoize :fund_remittances_gp

  # Distribution Payments of type All, LP and GP as of the remittance date
  def fund_dist_payments = fund_as_of.capital_distribution_payments
  memoize :fund_dist_payments

  def fund_dist_payments_lp = fund_dist_payments.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  memoize :fund_dist_payments_lp

  def fund_dist_payments_gp = fund_dist_payments.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  memoize :fund_dist_payments_gp

  # Distribution Payments associated to the capital commitment of type All  as of the remittance date
  def dist_payments = @capital_commitment.capital_distribution_payments.where(payment_date: ..@as_of_date)
  memoize :dist_payments

  #=== Committed Cash Helpers ===#

  # Committed Cash Amount of the fund_as_of commitments of type LP and GP
  def committed_cash_lp = money_sum(fund_commitments_lp, :committed_amount_cents)
  memoize :committed_cash_lp

  def committed_cash_gp = money_sum(fund_commitments_gp, :committed_amount_cents)
  memoize :committed_cash_gp

  # Committed Reinvestment Amount of the fund_as_of commitments of type LP and GP
  def committed_reinvest_lp = money_sum(fund_dist_payments_lp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_lp

  def committed_reinvest_gp = money_sum(fund_dist_payments_gp, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_gp

  # Committed Reinvestment Amount of the commitment
  def committed_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :committed_reinvest_investor

  # Percentage of committed cash of the capital commitment relative to the total fund commitments
  def committed_cash_investor_percent = percentage(@capital_commitment.committed_amount_cents, fund_commitments.sum(:committed_amount_cents))

  # Percentage of committed reinvestment of the capital commitment relative to the total fund commitments
  def committed_reinvest_investor_percent = percentage(committed_reinvest_investor.cents, fund_dist_payments.sum(:reinvestment_with_fees_cents))

  #=== Commitment Totals ===#

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments of type LP
  def total_comm_lp = committed_cash_lp + committed_reinvest_lp
  memoize :total_comm_lp

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments of type GP
  def total_comm_gp = committed_cash_gp + committed_reinvest_gp
  memoize :total_comm_gp

  # Total Committed Cash And Reinvestment Amount of the fund_as_of commitments
  def total_comm_fund = total_comm_lp + total_comm_gp

  # Total Committed Cash And Reinvestment Amount of the commitment
  def total_comm_investor = @capital_commitment.committed_amount + committed_reinvest_investor
  memoize :total_comm_investor

  # Percentage of total committed cash and reinvestment of the capital commitment relative to the total fund
  def total_comm_investor_percent = percentage(total_comm_investor.cents, total_comm_fund.cents)

  #=== Reinvestment Ratios ===#
  # Percentage of committed reinvestment to committed cash of type LP and GP
  def percent_reinvest_to_cash_lp = percentage(committed_reinvest_lp, committed_cash_lp)
  def percent_reinvest_to_cash_gp = percentage(committed_reinvest_gp, committed_cash_gp)
  # Percentage of total committed reinvestment to total committed cash
  def percent_reinvest_to_cash_total = percentage(committed_reinvest_lp + committed_reinvest_gp, committed_cash_lp + committed_cash_gp)
  # Percentage of investor's committed reinvestment to investor's committed cash
  def percent_reinvest_to_cash_investor = percentage(committed_reinvest_investor.cents, @capital_commitment.committed_amount_cents)

  #=== Drawdowns ===#

  # Remittance Call amount of the fund_as_of remittances of type LP and GP and of the investor
  def drawdown_cash_lp = money_sum(fund_remittances_lp, :call_amount_cents)
  memoize :drawdown_cash_lp

  def drawdown_cash_gp = money_sum(fund_remittances_gp, :call_amount_cents)
  memoize :drawdown_cash_gp

  def drawdown_cash_investor = money_sum(@capital_commitment.capital_remittances.where(remittance_date: ..@as_of_date), :call_amount_cents)
  memoize :drawdown_cash_investor

  def drawdown_cash_investor_percent = percentage(drawdown_cash_investor.cents, fund_as_of.capital_remittances.sum(:call_amount_cents))

  # Reinvestment amount of the fund_as_of distribution payments of the investor / commitment
  def drawdown_reinvest_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :drawdown_reinvest_investor

  def drawdown_reinvest_investor_percent = percentage(drawdown_reinvest_investor.cents, fund_dist_payments.sum(:reinvestment_with_fees_cents))

  # Total of remittance call amount and Reinvestment amount
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

  # Undrawn Amount is the difference between the committed cash + commitment reinvestment and the total drawdown amount
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

  # Distribution Cash is the sum of the gross payable amount - reinvestment amount of the dsitribution payments
  # For investor we use distribution payments of the capital commitment
  def dist_cash_investor = Money.new(dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :dist_cash_investor

  # For Total we use the distribution payments of the fund_as_of
  def dist_cash_total = Money.new(fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :dist_cash_total

  def dist_cash_investor_percent = percentage(dist_cash_investor.cents, dist_cash_total.cents)

  # Reinvestment amount is sum of the reinvestment amount of the distribution payments
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

  # For PRIOR we consider the data BEFORE the end_date
  # For CURRENT we consider the data EXACTLY ON the end_date
  # For INCL we consider the data before and on the end_date i.e. TILL the end_date
  # === Prior / Current / Incl Distributions ===

  def agg_dist_prior_notice_investor = Money.new(dist_payments.where(payment_date: ..@as_of_date.yesterday.end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_prior_notice_investor

  def agg_dist_prior_notice_investor_percent = percentage(agg_dist_prior_notice_investor.cents, fund_dist_payments.where(payment_date: ..@as_of_date.yesterday.end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents"))

  def agg_dist_curr_notice_investor = Money.new(dist_payments.where(payment_date: @as_of_date).sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_curr_notice_investor

  def agg_dist_curr_notice_investor_percent = percentage(agg_dist_curr_notice_investor.cents, fund_dist_payments.where(payment_date: @as_of_date).sum("gross_payable_cents - reinvestment_with_fees_cents"))

  def agg_dist_incl_curr_notice_investor = Money.new(dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), @currency)
  memoize :agg_dist_incl_curr_notice_investor

  def agg_dist_incl_curr_notice_investor_percent = percentage(agg_dist_incl_curr_notice_investor.cents, fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"))

  # === Reinvestment Prior / Curr / Incl ===

  def agg_reinvest_prior_curr_notice_investor = money_sum(dist_payments.where(payment_date: ..@as_of_date.yesterday.end_of_day), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_prior_curr_notice_investor

  def agg_reinvest_prior_curr_notice_investor_percent = percentage(agg_reinvest_prior_curr_notice_investor.cents, fund_dist_payments.where(payment_date: ..@as_of_date.yesterday.end_of_day).sum("reinvestment_with_fees_cents"))

  def agg_reinvest_curr_notice_investor = money_sum(dist_payments.where(payment_date: @as_of_date), :reinvestment_with_fees_cents)
  memoize :agg_reinvest_curr_notice_investor

  def agg_reinvest_curr_notice_investor_percent = percentage(agg_reinvest_curr_notice_investor.cents, fund_dist_payments.where(payment_date: @as_of_date).sum("reinvestment_with_fees_cents"))

  def agg_reinvest_incl_curr_notice_investor = money_sum(dist_payments, :reinvestment_with_fees_cents)
  memoize :agg_reinvest_incl_curr_notice_investor

  def agg_reinvest_incl_curr_notice_investor_percent = percentage(agg_reinvest_incl_curr_notice_investor.cents, fund_dist_payments.sum("reinvestment_with_fees_cents"))

  # === Drawdowns ===
  # === Drawdown Cash ===

  # Fetch Capital Calls before the remittance date
  def prior_calls = fund_as_of.capital_calls.where(call_date: ..@as_of_date.yesterday.end_of_day)
  memoize :prior_calls

  # For Drawdown Cash we use Computed Amount as we dont want to include the capital fee in it
  def drawdown_cash_prior_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id)
        .where(remittance_date: ..@as_of_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id)),
      :computed_amount_cents
    )
  end
  memoize :drawdown_cash_prior_notice_investor

  def drawdown_cash_prior_notice_investor_percent
    percentage(
      drawdown_cash_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@as_of_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:computed_amount_cents)
    )
  end

  def drawdown_cash_curr_notice_investor_percent
    return 0 unless @capital_remittance

    percentage(
      @capital_remittance.computed_amount,
      fund_as_of.capital_remittances
        .where(remittance_date: @as_of_date)
        .where(capital_call_id: @capital_remittance.capital_call_id)
        .sum(:computed_amount_cents)
    )
  end

  def drawdown_cash_incl_curr_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id, remittance_date: ..@as_of_date),
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
        .where(remittance_date: ..@as_of_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id)),
      :capital_fee_cents
    )
  end
  memoize :drawdown_fees_prior_notice_investor

  def drawdown_fees_prior_notice_investor_percent
    percentage(
      drawdown_fees_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@as_of_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:capital_fee_cents)
    )
  end

  def drawdown_fees_curr_notice_investor_percent
    return 0 unless @capital_remittance

    percentage(
      @capital_remittance.capital_fee_cents,
      fund_as_of.capital_remittances
        .where(remittance_date: @as_of_date)
        .where(capital_call_id: @capital_remittance.capital_call_id)
        .sum(:capital_fee_cents)
    )
  end

  def drawdown_fees_incl_curr_notice_investor
    money_sum(
      fund_as_of.capital_remittances
        .where(capital_commitment_id: @capital_commitment.id, remittance_date: ..@as_of_date),
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
  # Aggregate Drawdown is the sum of drawdown cash and drawdown fees

  def agg_drawdown_prior_notice_investor = drawdown_cash_prior_notice_investor + drawdown_fees_prior_notice_investor

  def agg_drawdown_prior_notice_investor_percent
    percentage(
      agg_drawdown_prior_notice_investor.cents,
      fund_as_of.capital_remittances
        .where(remittance_date: ..@as_of_date.yesterday.end_of_day)
        .where(capital_call_id: prior_calls.pluck(:id))
        .sum(:call_amount_cents)
    )
  end

  def agg_drawdown_curr_notice_investor_percent
    return 0 unless @capital_remittance

    percentage(
      @capital_remittance.call_amount_cents,
      fund_as_of.capital_remittances
        .where(remittance_date: @as_of_date)
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

  # For PRIOR we consider the data BEFORE the end_date
  # For CURRENT we consider the data EXACTLY ON the end_date
  # For INCLUDING we consider the data BEFORE and ON the end_date i.e. TILL the end_date

  # Undrawn Amount is the difference between the committed amount and the drawdown amount
  # Fetch the capital call before the current call that has capital remittances and sum their committed amount
  # If not then use the remittances from the current call and sum the committed amount
  def undrawn_comm_prior_notice_lp
    last_call = prior_calls.order(:call_date).last
    last_remittances = last_call ? last_call.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id)).where(remittance_date: ..@as_of_date.yesterday.end_of_day) : []
    remittances = if @capital_remittance
                    @capital_remittance.capital_call.capital_remittances
                  elsif @capital_distribution_payment
                    @capital_distribution_payment.capital_commitment.capital_remittances
                  else
                    fund_as_of.capital_remittances
                  end

    committed_amt = if last_call && last_remittances.present?
                      money_sum(last_remittances, :committed_amount_cents)
                    else
                      current = remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id), remittance_date: ..@as_of_date)
                      current.present? ? money_sum(current, :committed_amount_cents) : Money.new(0, @currency)
                    end

    committed_amt - money_sum(fund_remittances_lp.where(remittance_date: ..@as_of_date.yesterday.end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_lp

  def undrawn_comm_prior_notice_gp
    last_call = prior_calls.order(:call_date).last
    last_remittances = last_call ? last_call.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id)).where(remittance_date: ..@as_of_date.yesterday.end_of_day) : []
    remittances = if @capital_remittance
                    @capital_remittance.capital_call.capital_remittances
                  elsif @capital_distribution_payment
                    @capital_distribution_payment.capital_commitment.capital_remittances
                  else
                    fund_as_of.capital_remittances
                  end

    committed_amt = if last_call && last_remittances.present?
                      money_sum(last_remittances, :committed_amount_cents)
                    else
                      current = remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id), remittance_date: ..@as_of_date)
                      current.present? ? money_sum(current, :committed_amount_cents) : Money.new(0, @currency)
                    end

    committed_amt - money_sum(fund_remittances_gp.where(remittance_date: ..@as_of_date.yesterday.end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_gp

  def undrawn_comm_prior_notice_total = undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp

  def undrawn_comm_prior_notice_investor
    return Money.new(0, @currency) unless @capital_remittance

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
    return Money.new(0, @currency) unless @capital_remittance

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
