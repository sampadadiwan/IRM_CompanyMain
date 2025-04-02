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

  # === Helper Methods ===

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_f if part.respond_to?(:cents)
    total = total.cents.to_f if total.respond_to?(:cents)
    p "part:  #{part}"
    p "total: #{total}"
    total.zero? ? 0 : (part / total) * 100
  end

  def fund_as_of
    object
  end
  memoize :fund_as_of

  def fund_commitments
    fund_as_of.capital_commitments
  end
  memoize :fund_commitments

  def fund_commitments_lp
    fund_as_of.capital_commitments.lp(fund_as_of.id)
  end
  memoize :fund_commitments_lp

  def fund_commitments_gp
    fund_as_of.capital_commitments.gp(fund_as_of.id)
  end
  memoize :fund_commitments_gp

  def fund_remittances_lp
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  end
  memoize :fund_remittances_lp

  def fund_remittances_gp
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  end
  memoize :fund_remittances_gp

  def fund_dist_payments
    fund_as_of.capital_distribution_payments
  end
  memoize :fund_dist_payments

  def fund_dist_payments_lp
    fund_as_of.capital_distribution_payments.where(capital_commitment_id: fund_commitments_lp.pluck(:id))
  end
  memoize :fund_dist_payments_lp

  def fund_dist_payments_gp
    fund_as_of.capital_distribution_payments.where(capital_commitment_id: fund_commitments_gp.pluck(:id))
  end
  memoize :fund_dist_payments_gp

  def dist_payments
    @capital_commitment.capital_distribution_payments.where(payment_date: ..@remittance_date)
  end
  memoize :dist_payments

  # === Committed Cash ===
  def committed_cash_lp
    fund_commitments_lp.sum(:committed_amount_cents)
  end
  memoize :committed_cash_lp

  def committed_cash_gp
    fund_commitments_gp.sum(:committed_amount_cents)
  end
  memoize :committed_cash_gp

  def committed_reinvest_lp
    fund_dist_payments_lp.sum(:reinvestment_with_fees_cents)
  end
  memoize :committed_reinvest_lp

  def committed_reinvest_gp
    fund_dist_payments_gp.sum(:reinvestment_with_fees_cents)
  end
  memoize :committed_reinvest_gp

  def committed_reinvest_investor
    dist_payments.sum(:reinvestment_with_fees_cents)
  end
  memoize :committed_reinvest_investor

  def committed_cash_investor_percent
    percentage(@capital_commitment.committed_amount_cents, fund_as_of.capital_commitments.sum(:committed_amount_cents))
  end

  def committed_reinvest_investor_percent
    percentage(committed_reinvest_investor, fund_dist_payments.sum(:reinvestment_with_fees_cents))
  end

  # === Total Commitments ===

  def total_comm_lp
    committed_cash_lp + committed_reinvest_lp
  end
  memoize :total_comm_lp

  def total_comm_gp
    committed_cash_gp + committed_reinvest_gp
  end
  memoize :total_comm_gp

  def total_comm_fund
    total_comm_lp + total_comm_gp
  end

  def total_comm_investor
    @capital_commitment.committed_amount_cents + committed_reinvest_investor
  end
  memoize :total_comm_investor

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
    percentage(committed_reinvest_lp + committed_reinvest_gp, committed_cash_lp + committed_cash_gp)
  end

  def percent_reinvest_to_cash_investor
    percentage(committed_reinvest_investor, @capital_commitment.committed_amount)
  end

  # === Drawdowns ===

  def drawdown_cash_lp
    fund_remittances_lp.sum(:call_amount_cents)
  end
  memoize :drawdown_cash_lp

  def drawdown_cash_gp
    fund_remittances_gp.sum(:call_amount_cents)
  end
  memoize :drawdown_cash_gp

  def drawdown_cash_investor
    @capital_commitment.capital_remittances.where(remittance_date: ..@remittance_date).sum(:call_amount_cents)
  end
  memoize :drawdown_cash_investor

  def drawdown_cash_investor_percent
    percentage(drawdown_cash_investor, fund_as_of.capital_remittances.sum(:call_amount_cents))
  end

  def drawdown_reinvest_investor
    dist_payments.sum(:reinvestment_with_fees_cents)
  end
  memoize :drawdown_reinvest_investor

  def drawdown_reinvest_investor_percent
    percentage(drawdown_reinvest_investor, fund_dist_payments.sum(:reinvestment_with_fees_cents))
  end

  # === Total Drawdowns ===

  def total_drawdown_lp
    drawdown_cash_lp + fund_dist_payments_lp.sum(:reinvestment_with_fees_cents)
  end
  memoize :total_drawdown_lp

  def total_drawdown_gp
    drawdown_cash_gp + fund_dist_payments_gp.sum(:reinvestment_with_fees_cents)
  end
  memoize :total_drawdown_gp

  def total_drawdown_fund
    total_drawdown_lp + total_drawdown_gp
  end
  memoize :total_drawdown_fund

  def total_drawdown_investor
    drawdown_cash_investor + drawdown_reinvest_investor
  end
  memoize :total_drawdown_investor

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
    percentage(total_drawdown_fund, total_comm_fund)
  end

  def percent_drawdown_cash_investor
    percentage(drawdown_cash_investor, @capital_commitment.committed_amount)
  end

  # === Undrawn Commitments ===

  def undrawn_comm_lp
    committed_cash_lp - drawdown_cash_lp
  end

  def undrawn_comm_gp
    committed_cash_gp - drawdown_cash_gp
  end

  def undrawn_comm_total
    committed_cash_lp + committed_cash_gp - (drawdown_cash_lp + drawdown_cash_gp)
  end

  def undrawn_comm_investor
    @capital_commitment.committed_amount_cents - drawdown_cash_investor
  end

  def undrawn_comm_investor_percent
    percentage(undrawn_comm_investor, undrawn_comm_total)
  end

  # === Undrawn Percentages ===

  def percent_unpaid_comm_lp
    percentage(undrawn_comm_lp, committed_cash_lp)
  end

  def percent_unpaid_comm_gp
    percentage(undrawn_comm_gp, committed_cash_gp)
  end

  def percent_unpaid_comm_total
    percentage(undrawn_comm_total, committed_cash_lp + committed_cash_gp)
  end

  def percent_unpaid_comm_investor
    percentage(undrawn_comm_investor, @capital_commitment.committed_amount_cents)
  end

  # === Distribution Cash ===

  def dist_cash_lp
    fund_dist_payments_lp.sum("gross_payable_cents - reinvestment_with_fees_cents")
  end

  def dist_cash_gp
    fund_dist_payments_gp.sum("gross_payable_cents - reinvestment_with_fees_cents")
  end

  def dist_cash_investor
    dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents")
  end
  memoize :dist_cash_investor

  def dist_cash_total
    fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents")
  end
  memoize :dist_cash_total

  def dist_cash_investor_percent
    percentage(dist_cash_investor, dist_cash_total)
  end

  # === Distribution Reinvest ===

  def dist_reinvest_lp
    fund_dist_payments_lp.sum(:reinvestment_with_fees_cents)
  end

  def dist_reinvest_gp
    fund_dist_payments_gp.sum(:reinvestment_with_fees_cents)
  end

  def dist_reinvest_investor
    dist_payments.sum(:reinvestment_with_fees_cents)
  end

  def dist_reinvest_investor_percent
    percentage(dist_reinvest_investor, fund_dist_payments.sum(:reinvestment_with_fees_cents))
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

  # === Drawdown Cash Prior to current notice ===
  def prior_calls
    fund_as_of.capital_calls.where(call_date: ..(@remittance_date - 1.day).end_of_day)
  end
  memoize :prior_calls

  def drawdown_cash_prior_notice_investor
    money_sum(fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id).where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id)), :computed_amount_cents)
  end
  memoize :drawdown_cash_prior_notice_investor

  def drawdown_cash_prior_notice_investor_percent
    percentage(drawdown_cash_prior_notice_investor, money_sum(fund_as_of.capital_remittances.where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id)), :computed_amount_cents))
  end

  # === Drawdown Cash Current notice ===

  def drawdown_cash_curr_notice_investor_percent
    percentage(@capital_remittance.computed_amount, money_sum(fund_as_of.capital_remittances.where(remittance_date: @remittance_date).where(capital_call_id: @capital_remittance.capital_call_id), :computed_amount_cents))
  end

  # === Drawdown Cash Including Current notice ===

  def drawdown_cash_incl_current_notice_investor
    fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id, remittance_date: @remittance_date).sum(:computed_amount_cents)
  end
  memoize :drawdown_cash_incl_current_notice_investor

  def drawdown_cash_incl_current_notice_investor_percent
    percentage(drawdown_cash_incl_current_notice_investor, fund_as_of.capital_remittances.sum(:computed_amount_cents))
  end

  # === Drawdown Fees Prior to current notice ===

  def drawdown_fees_prior_notice_investor
    money_sum(fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id).where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id)), :capital_fee_cents)
  end
  memoize :drawdown_fees_prior_notice_investor

  def drawdown_fees_prior_notice_investor_percent
    percentage(drawdown_fees_prior_notice_investor, money_sum(fund_as_of.capital_remittances.where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id)), :capital_fee_cents))
  end

  # === Drawdown Fees Current notice ===

  def drawdown_fees_curr_notice_investor_percent
    percentage(@capital_remittance.capital_fee_cents, money_sum(fund_as_of.capital_remittances.where(remittance_date: @remittance_date).where(capital_call_id: @capital_remittance.capital_call_id), :capital_fee_cents))
  end

  # === Drawdown Fees Including Current notice ===

  def drawdown_fees_incl_curr_notice_investor
    fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id, remittance_date: @remittance_date).sum(:capital_fee_cents)
  end
  memoize :drawdown_fees_incl_curr_notice_investor

  def drawdown_fees_incl_curr_notice_investor_percent
    percentage(drawdown_fees_incl_curr_notice_investor, fund_as_of.capital_remittances.sum(:capital_fee_cents))
  end

  # === Aggregate Drawdown Prior to Current Notice ===

  def agg_drawdown_prior_notice_investor
    drawdown_cash_prior_notice_investor + drawdown_fees_prior_notice_investor
  end

  def agg_drawdown_prior_notice_investor_percent
    percentage(agg_drawdown_prior_notice_investor, fund_as_of.capital_remittances.where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id)).sum(:call_amount_cents))
  end

  # === Aggregate Drawdown Current Notice ===

  def agg_drawdown_curr_notice_investor_percent
    percentage(@capital_remittance.call_amount, money_sum(fund_as_of.capital_remittances.where(remittance_date: @remittance_date).where(capital_call_id: @capital_remittance.capital_call_id), :call_amount_cents))
  end

  # === Aggregate Drawdown INCL Current Notice ===

  def agg_drawdown_incl_curr_notice_investor
    fund_as_of.capital_remittances.where(capital_commitment_id: @capital_commitment.id).sum(:call_amount_cents)
  end
  memoize :agg_drawdown_incl_curr_notice_investor

  def agg_drawdown_incl_curr_notice_investor_percent
    percentage(agg_drawdown_incl_curr_notice_investor, fund_as_of.capital_remittances.sum(:call_amount_cents))
  end

  # === Aggregate Prior Distribution ===

  def agg_dist_prior_notice_investor
    dist_payments.where(payment_date: ..(@remittance_date - 1.day).end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents")
  end
  memoize :agg_dist_prior_notice_investor

  def agg_dist_prior_notice_investor_percent
    percentage(agg_dist_prior_notice_investor, fund_dist_payments.where(payment_date: ..(@remittance_date - 1.day).end_of_day).sum("gross_payable_cents - reinvestment_with_fees_cents"))
  end

  # === Aggregate Current Distribution ===

  def agg_dist_curr_notice_investor
    dist_payments.where(payment_date: @remittance_date).sum("gross_payable_cents - reinvestment_with_fees_cents")
  end
  memoize :agg_dist_curr_notice_investor

  def agg_dist_curr_notice_investor_percent
    percentage(agg_dist_curr_notice_investor, fund_dist_payments.where(payment_date: @remittance_date).sum("gross_payable_cents - reinvestment_with_fees_cents"))
  end

  # === Aggregate Total Distribution ===

  def agg_dist_incl_curr_notice_investor
    dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents")
  end
  memoize :agg_dist_incl_curr_notice_investor

  def agg_dist_incl_curr_notice_investor_percent
    percentage(agg_dist_incl_curr_notice_investor, fund_dist_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"))
  end

  # === Aggregate PRIOR Reinvestment ===

  # remove curr from these methods
  def agg_reinvest_prior_curr_notice_investor
    dist_payments.where(payment_date: ..(@remittance_date - 1.day).end_of_day).sum("reinvestment_with_fees_cents")
  end
  memoize :agg_reinvest_prior_curr_notice_investor

  def agg_reinvest_prior_curr_notice_investor_percent
    percentage(agg_reinvest_prior_curr_notice_investor, fund_dist_payments.where(payment_date: ..(@remittance_date - 1.day).end_of_day).sum("reinvestment_with_fees_cents"))
  end

  # === Aggregate Current Reinvestment ===

  def agg_reinvest_curr_notice_investor
    dist_payments.where(payment_date: @remittance_date).sum("reinvestment_with_fees_cents")
  end
  memoize :agg_reinvest_curr_notice_investor

  # this is taking perentage of current commitments dist payments that are on the remittance date to all dist payments of the fund on the current date
  # is this correct?
  def agg_reinvest_curr_notice_investor_percent
    percentage(agg_reinvest_curr_notice_investor, fund_dist_payments.where(payment_date: @remittance_date).sum("reinvestment_with_fees_cents"))
  end

  # === Aggregate INCL Current Reinvestment ===

  def agg_reinvest_incl_curr_notice_investor
    dist_payments.sum("reinvestment_with_fees_cents")
  end
  memoize :agg_reinvest_incl_curr_notice_investor

  def agg_reinvest_incl_curr_notice_investor_percent
    percentage(agg_reinvest_incl_curr_notice_investor, fund_dist_payments.sum("reinvestment_with_fees_cents"))
  end

  # === Undrawn Commitments Calculations ===

  # === Undrawn Commitments PRIOR Calculations ===

  def prior_calls_lp_remittances
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id)).where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id))
  end
  memoize :prior_calls_lp_remittances

  def prior_calls_gp_remittances
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id)).where(remittance_date: ..(@remittance_date - 1.day).end_of_day).where(capital_call_id: prior_calls.pluck(:id))
  end
  memoize :prior_calls_gp_remittances

  def current_calls_lp_remittances
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_lp.pluck(:id)).where(remittance_date: @remittance_date).where(capital_call_id: @capital_remittance.capital_call_id)
  end
  memoize :current_calls_lp_remittances

  def current_calls_gp_remittances
    fund_as_of.capital_remittances.where(capital_commitment_id: fund_commitments_gp.pluck(:id)).where(remittance_date: @remittance_date).where(capital_call_id: @capital_remittance.capital_call_id)
  end
  memoize :current_calls_gp_remittances

  def undrawn_comm_prior_notice_lp
    last_call_before = prior_calls.order(:call_date).last
    # initialize prior commitment amount to 0
    prior_lp_committment_amt = Money.new(0, @currency)

    # if there are calls before this then take prior calls lp capital remittances and sum the committed amount
    prior_lp_committment_amt = money_sum(prior_calls_lp_remittances, :committed_amount_cents) if last_call_before

    # take current calls lp capital remittances and sum the committed amount if prior_lp_committment_amt is zero
    prior_lp_committment_amt = money_sum(current_calls_lp_remittances, :committed_amount_cents) if prior_lp_committment_amt.zero?

    # take the current remittances committed amount if prior_lp_committment_amt is zero
    prior_lp_committment_amt = @capital_remittance.committed_amount if prior_lp_committment_amt.zero?
    prior_lp_committment_amt - money_sum(fund_remittances_lp.where(remittance_date: ..(@remittance_date - 1.day).end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_lp

  def undrawn_comm_prior_notice_gp
    last_call_before = prior_calls.order(:call_date).last
    # initialize prior commitment amount to 0
    prior_gp_committment_amt = Money.new(0, @currency)

    # if there are calls before this then take prior calls gp capital remittances and sum the committed amount
    prior_gp_committment_amt = money_sum(prior_calls_gp_remittances, :committed_amount_cents) if last_call_before

    # take current calls gp capital remittances and sum the committed amount if prior_gp_committment_amt is zero
    prior_gp_committment_amt = money_sum(current_calls_gp_remittances, :committed_amount_cents) if prior_gp_committment_amt.zero?

    # take the current remittances committed amount if prior_gp_committment_amt is zero
    prior_gp_committment_amt = @capital_remittance.committed_amount if prior_gp_committment_amt.zero?
    prior_gp_committment_amt - money_sum(fund_remittances_gp.where(remittance_date: ..(@remittance_date - 1.day).end_of_day), :call_amount_cents)
  end
  memoize :undrawn_comm_prior_notice_gp

  def undrawn_comm_prior_notice_total
    undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp
  end

  def undrawn_comm_prior_notice_investor
    @capital_remittance.committed_amount - agg_drawdown_prior_notice_investor
  end

  def undrawn_comm_prior_notice_investor_percent
    percentage(undrawn_comm_prior_notice_investor, undrawn_comm_prior_notice_total)
  end

  # === Undrawn Commitments CURRENT Calculations ===

  def undrawn_comm_curr_notice_lp
    current_lp_committment_amt = money_sum(@capital_remittance.capital_call.capital_remittances, :committed_amount_cents)
    current_lp_committment_amt = @capital_remittance.committed_amount if current_lp_committment_amt.zero?
    current_lp_committment_amt - money_sum(fund_remittances_lp.where(remittance_date: @remittance_date), :call_amount_cents)
  end
  memoize :undrawn_comm_curr_notice_lp

  def undrawn_comm_curr_notice_gp
    current_gp_committment_amt = money_sum(@capital_remittance.capital_call.capital_remittances, :committed_amount_cents)
    current_gp_committment_amt = @capital_remittance.committed_amount if current_gp_committment_amt.zero?
    current_gp_committment_amt - money_sum(fund_remittances_gp.where(remittance_date: @remittance_date), :call_amount_cents)
  end
  memoize :undrawn_comm_curr_notice_gp

  def undrawn_comm_curr_notice_total
    undrawn_comm_curr_notice_lp + undrawn_comm_curr_notice_gp
  end
  memoize :undrawn_comm_curr_notice_total

  def undrawn_comm_curr_notice_investor
    @capital_remittance.committed_amount_cents - agg_drawdown_incl_curr_notice_investor
  end

  def undrawn_comm_curr_notice_investor_percent
    percentage(undrawn_comm_curr_notice_investor, undrawn_comm_curr_notice_total)
  end

  # === Undrawn Commitments INCL Current Calculations ===

  def undrawn_comm_incl_curr_notice_lp
    undrawn_comm_curr_notice_lp
  end

  def undrawn_comm_incl_curr_notice_gp
    undrawn_comm_curr_notice_gp
  end

  def undrawn_comm_incl_curr_notice_total
    undrawn_comm_curr_notice_total
  end

  def undrawn_comm_incl_curr_notice_investor
    undrawn_comm_curr_notice_investor
  end

  def undrawn_comm_incl_curr_notice_investor_percent
    percentage(undrawn_comm_incl_curr_notice_investor, undrawn_comm_incl_curr_notice_total)
  end
end
