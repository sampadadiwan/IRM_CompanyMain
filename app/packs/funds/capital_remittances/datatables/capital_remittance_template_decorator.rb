class CapitalRemittanceTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper

  def initialize(object)
    super
    @curr_date = object.remittance_date
    @end_date = (object.remittance_date - 1.day).end_of_day
    @currency = object.fund.currency
  end

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_f if part.respond_to?(:cents)
    total = total.cents.to_f if total.respond_to?(:cents)
    total.zero? ? 0 : (part / total) * 100
  end

  ### SECTION C ###

  def init_prior_remittances
    if @prior_lp_remittances.nil? || @prior_gp_remittances.nil?

      prior_lp_remittances_ids = []
      prior_gp_remittances_ids = []

      @capital_calls = object.fund.capital_calls.where(call_date: ..@end_date)

      @capital_calls.each do |call|
        call.capital_remittances.where(remittance_date: ..@end_date).find_each do |cr|
          if cr.capital_commitment.fund_unit_setting&.gp_units
            prior_gp_remittances_ids << cr.id
          else
            prior_lp_remittances_ids << cr.id
          end
        end
      end

      @prior_lp_remittances = object.fund.capital_remittances.where(id: prior_lp_remittances_ids)
      @prior_gp_remittances = object.fund.capital_remittances.where(id: prior_gp_remittances_ids)
    end
  end

  def cash_prior_notice_lp
    init_prior_remittances
    @cash_prior_notice_lp = money_sum(@prior_lp_remittances, :computed_amount_cents)
  end

  def cash_prior_notice_gp
    init_prior_remittances
    @cash_prior_notice_gp = money_sum(@prior_gp_remittances, :computed_amount_cents)
  end

  def cash_prior_notice_total
    @cash_prior_notice_total ||= cash_prior_notice_lp + cash_prior_notice_gp
  end

  def init_prior_remittances_investor
    init_prior_remittances
    @prior_remittances_investor = @prior_lp_remittances.where(capital_commitment_id: object.capital_commitment_id).or(@prior_gp_remittances.where(capital_commitment_id: object.capital_commitment_id)) if @prior_remittances_investor.nil?
  end

  def cash_prior_notice_investor
    return @cash_prior_notice_investor if @cash_prior_notice_investor

    init_prior_remittances_investor
    @cash_prior_notice_investor ||= money_sum(@prior_remittances_investor, :computed_amount_cents)
  end

  def cash_prior_notice_investor_percent
    percentage(cash_prior_notice_investor, cash_prior_notice_total)
  end

  def init_current_remittances
    if @current_lp_remittances.nil? || @current_gp_remittances.nil?

      current_lp_remittances_ids = []
      current_gp_remittances_ids = []

      object.capital_call.capital_remittances.where(remittance_date: @curr_date).find_each do |cr|
        if cr.capital_commitment.fund_unit_setting&.gp_units
          current_gp_remittances_ids << cr.id
        else
          current_lp_remittances_ids << cr.id
        end
      end

      @current_lp_remittances = object.fund.capital_remittances.where(id: current_lp_remittances_ids)
      @current_gp_remittances = object.fund.capital_remittances.where(id: current_gp_remittances_ids)
    end
  end

  def cash_current_notice_lp
    init_current_remittances
    @cash_current_notice_lp ||= money_sum(@current_lp_remittances, :computed_amount_cents)
  end

  def cash_current_notice_gp
    init_current_remittances
    @cash_current_notice_gp ||= money_sum(@current_gp_remittances, :computed_amount_cents)
  end

  def cash_current_notice_total
    @cash_current_notice_total ||= cash_current_notice_lp + cash_current_notice_gp
  end

  def cash_current_notice_investor
    @cash_current_notice_investor ||= object.computed_amount
  end

  def cash_current_notice_investor_percent
    percentage(cash_current_notice_investor, cash_current_notice_total)
  end

  def cash_incl_current_notice_lp
    cash_prior_notice_lp + cash_current_notice_lp
  end

  def cash_incl_current_notice_gp
    cash_prior_notice_gp + cash_current_notice_gp
  end

  def cash_incl_current_notice_total
    cash_prior_notice_total + cash_current_notice_total
  end

  def cash_incl_current_notice_investor
    cash_prior_notice_investor + cash_current_notice_investor
  end

  def cash_incl_current_notice_investor_percent
    percentage(cash_incl_current_notice_investor, cash_incl_current_notice_total)
  end

  def fees_prior_notice_lp
    init_prior_remittances
    @fees_prior_notice_lp = money_sum(@prior_lp_remittances, :capital_fee_cents) + money_sum(@prior_lp_remittances, :other_fee_cents)
  end

  def fees_prior_notice_gp
    init_prior_remittances
    @fees_prior_notice_gp = money_sum(@prior_gp_remittances, :capital_fee_cents) + money_sum(@prior_gp_remittances, :other_fee_cents)
  end

  def fees_prior_notice_total
    fees_prior_notice_lp + fees_prior_notice_gp
  end

  def fees_prior_notice_investor
    return @fees_prior_notice_investor if @fees_prior_notice_investor

    init_prior_remittances_investor
    @fees_prior_notice_investor ||= money_sum(@prior_remittances_investor, :capital_fee_cents) + money_sum(@prior_remittances_investor, :other_fee_cents)
  end

  def fees_prior_notice_investor_percent
    percentage(fees_prior_notice_investor, fees_prior_notice_total)
  end

  def fees_current_notice_lp
    init_current_remittances
    @fees_current_notice_lp = money_sum(@current_lp_remittances, :capital_fee_cents) + money_sum(@current_lp_remittances, :other_fee_cents)
  end

  def fees_current_notice_gp
    @fees_current_notice_gp = money_sum(@current_gp_remittances, :capital_fee_cents) + money_sum(@current_gp_remittances, :other_fee_cents)
  end

  def fees_current_notice_total
    fees_current_notice_lp + fees_current_notice_gp
  end

  def fees_current_notice_investor
    @fees_current_notice_investor ||= object.capital_fee + object.other_fee
  end

  def fees_current_notice_investor_percent
    percentage(fees_current_notice_investor, fees_current_notice_total)
  end

  def fees_incl_current_notice_lp
    fees_prior_notice_lp + fees_current_notice_lp
  end

  def fees_incl_current_notice_gp
    fees_prior_notice_gp + fees_current_notice_gp
  end

  def fees_incl_current_notice_total
    fees_prior_notice_total + fees_current_notice_total
  end

  def fees_incl_current_notice_investor
    fees_prior_notice_investor + fees_current_notice_investor
  end

  def fees_incl_current_notice_investor_percent
    percentage(fees_incl_current_notice_investor, fees_incl_current_notice_total)
  end

  def agg_drawdown_prior_notice_lp
    cash_prior_notice_lp + fees_prior_notice_lp
  end

  def agg_drawdown_prior_notice_gp
    cash_prior_notice_gp + fees_prior_notice_gp
  end

  def agg_drawdown_prior_notice_total
    agg_drawdown_prior_notice_lp + agg_drawdown_prior_notice_gp
  end

  def agg_drawdown_prior_notice_investor
    cash_prior_notice_investor + fees_prior_notice_investor
  end

  def agg_drawdown_prior_notice_investor_percent
    percentage(agg_drawdown_prior_notice_investor, agg_drawdown_prior_notice_total)
  end

  def agg_drawdown_current_notice_lp
    cash_current_notice_lp + fees_current_notice_lp
  end

  def agg_drawdown_current_notice_gp
    cash_current_notice_gp + fees_current_notice_gp
  end

  def agg_drawdown_current_notice_total
    agg_drawdown_current_notice_lp + agg_drawdown_current_notice_gp
  end

  def init_current_remittances_investor
    init_current_remittances
    @current_remittances_investor = @current_lp_remittances.where(capital_commitment_id: object.capital_commitment_id).or(@current_gp_remittances.where(capital_commitment_id: object.capital_commitment_id)) if @current_remittances_investor.nil?
  end

  def agg_drawdown_current_notice_investor
    cash_current_notice_investor + fees_current_notice_investor
  end

  def agg_drawdown_current_notice_investor_percent
    percentage(agg_drawdown_current_notice_investor, agg_drawdown_current_notice_total)
  end

  def agg_drawdown_incl_current_notice_lp
    agg_drawdown_prior_notice_lp + agg_drawdown_current_notice_lp
  end

  def agg_drawdown_incl_current_notice_gp
    agg_drawdown_prior_notice_gp + agg_drawdown_current_notice_gp
  end

  def agg_drawdown_incl_current_notice_total
    agg_drawdown_prior_notice_total + agg_drawdown_current_notice_total
  end

  def agg_drawdown_incl_current_notice_investor
    agg_drawdown_prior_notice_investor + agg_drawdown_current_notice_investor
  end

  def agg_drawdown_incl_current_notice_investor_percent
    percentage(agg_drawdown_incl_current_notice_investor, agg_drawdown_incl_current_notice_total)
  end

  def init_prior_calls_committments_and_remittances
    if @prior_calls_lp_committments.nil? || @prior_calls_gp_committments.nil? || @prior_calls_lp_remittances.nil? || @prior_calls_gp_remittances.nil?

      prior_calls_lp_committments_ids = []
      prior_calls_gp_committments_ids = []

      prior_calls_gp_remittances_ids = []
      prior_calls_lp_remittances_ids = []

      capital_calls = object.fund.capital_calls.where(call_date: ..@end_date)
      capital_calls.each do |call|
        call.capital_remittances.includes(:capital_commitment).where(remittance_date: ..@end_date).find_each do |cr|
          if cr.capital_commitment.fund_unit_setting&.gp_units
            prior_calls_gp_committments_ids << cr.capital_commitment_id
            prior_calls_gp_remittances_ids << cr.id
          else
            prior_calls_lp_committments_ids << cr.capital_commitment_id
            prior_calls_lp_remittances_ids << cr.id
          end
        end
      end

      @prior_calls_lp_committments = object.fund.capital_commitments.where(id: prior_calls_lp_committments_ids).order(:commitment_date)
      @prior_calls_gp_committments = object.fund.capital_commitments.where(id: prior_calls_gp_committments_ids).order(:commitment_date)

      @prior_calls_lp_remittances = object.fund.capital_remittances.where(id: prior_calls_lp_remittances_ids)
      @prior_calls_gp_remittances = object.fund.capital_remittances.where(id: prior_calls_gp_remittances_ids)
    end
  end

  def init_current_calls_committments_and_remittances
    if @current_calls_lp_committments.nil? || @current_calls_gp_committments.nil? || @current_calls_lp_remittances.nil? || @current_calls_gp_remittances.nil?

      current_calls_lp_committments_ids = []
      current_calls_gp_committments_ids = []

      current_calls_lp_remittances_ids = []
      current_calls_gp_remittances_ids = []

      calls = object.fund.capital_calls.where(call_date: ..@curr_date)

      calls.each do |call|
        call.capital_remittances.includes(:capital_commitment).where(remittance_date: ..@curr_date).find_each do |cr|
          if cr.capital_commitment.fund_unit_setting&.gp_units
            current_calls_gp_committments_ids << cr.capital_commitment_id
            current_calls_gp_remittances_ids << cr.id
          else
            current_calls_lp_committments_ids << cr.capital_commitment_id
            current_calls_lp_remittances_ids << cr.id
          end
        end
      end

      @current_calls_lp_committments = object.fund.capital_commitments.where(id: current_calls_lp_committments_ids).order(:commitment_date)
      @current_calls_gp_committments = object.fund.capital_commitments.where(id: current_calls_gp_committments_ids).order(:commitment_date)

      @current_calls_lp_remittances = object.fund.capital_remittances.where(id: current_calls_lp_remittances_ids)
      @current_calls_gp_remittances = object.fund.capital_remittances.where(id: current_calls_gp_remittances_ids)
    end
  end

  def undrawn_comm_prior_notice_lp
    return @undrawn_comm_prior_notice_lp if @undrawn_comm_prior_notice_lp

    init_prior_calls_committments_and_remittances
    last_call_before = object.fund.capital_calls.where(call_date: ..@end_date).order(:call_date).last
    prior_lp_committment_amt = Money.new(0, @currency)
    prior_lp_committment_amt = money_sum(@prior_calls_lp_remittances.where(capital_call_id: last_call_before.id), :committed_amount_cents) if last_call_before
    if prior_lp_committment_amt.zero?
      init_current_calls_committments_and_remittances
      prior_lp_committment_amt = money_sum(@current_calls_lp_remittances, :committed_amount_cents)
    end
    prior_lp_committment_amt = object.committed_amount if prior_lp_committment_amt.zero?

    # prior_lp_remittances_call_amt_sum = money_sum(@prior_calls_lp_remittances, :call_amount_cents)
    @undrawn_comm_prior_notice_lp = prior_lp_committment_amt - agg_drawdown_prior_notice_lp
  end

  def undrawn_comm_prior_notice_gp
    return @undrawn_comm_prior_notice_gp if @undrawn_comm_prior_notice_gp

    init_prior_calls_committments_and_remittances
    last_call_before = object.fund.capital_calls.where(call_date: ..@end_date).order(:call_date).last
    prior_gp_committment_amt = Money.new(0, @currency)
    prior_gp_committment_amt = money_sum(@prior_calls_gp_remittances.where(capital_call_id: last_call_before.id), :committed_amount_cents) if last_call_before
    if prior_gp_committment_amt.zero?
      init_current_calls_committments_and_remittances
      prior_gp_committment_amt = money_sum(@current_calls_gp_remittances, :committed_amount_cents)
    end
    prior_gp_committment_amt = object.committed_amount if prior_gp_committment_amt.zero?

    # prior_gp_remittances_call_amt_sum = money_sum(@prior_calls_gp_remittances, :call_amount_cents)
    @undrawn_comm_prior_notice_gp = prior_gp_committment_amt - agg_drawdown_prior_notice_gp
  end

  def undrawn_comm_prior_notice_total
    undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp
  end

  def undrawn_comm_prior_notice_investor
    return @undrawn_comm_prior_notice_investor if @undrawn_comm_prior_notice_investor

    investor_committment_amt = object.committed_amount

    @undrawn_comm_prior_notice_investor ||= investor_committment_amt - agg_drawdown_prior_notice_investor
  end

  def undrawn_comm_prior_notice_investor_percent
    percentage(undrawn_comm_prior_notice_investor, undrawn_comm_prior_notice_total)
  end

  def undrawn_comm_current_notice_lp
    return @undrawn_comm_current_notice_lp if @undrawn_comm_current_notice_lp

    init_current_calls_committments_and_remittances

    current_lp_committment_amt = money_sum(@current_calls_lp_remittances.where(capital_call_id: object.capital_call_id), :committed_amount_cents)
    current_lp_committment_amt = object.committed_amount if current_lp_committment_amt.zero?

    @undrawn_comm_current_notice_lp = current_lp_committment_amt - agg_drawdown_incl_current_notice_lp
  end

  def undrawn_comm_current_notice_gp
    return @undrawn_comm_current_notice_gp if @undrawn_comm_current_notice_gp

    init_current_calls_committments_and_remittances

    current_gp_committment_amt = money_sum(@current_calls_gp_remittances.where(capital_call_id: object.capital_call_id), :committed_amount_cents)
    current_gp_committment_amt = object.committed_amount if current_gp_committment_amt.zero?

    # till_current_gp_remittances_call_amt_sum = money_sum(@prior_calls_gp_remittances, :call_amount_cents) + money_sum(@current_calls_gp_remittances, :call_amount_cents)
    @undrawn_comm_current_notice_gp = current_gp_committment_amt - agg_drawdown_incl_current_notice_gp
  end

  def undrawn_comm_current_notice_total
    undrawn_comm_current_notice_lp + undrawn_comm_current_notice_gp
  end

  def undrawn_comm_current_notice_investor
    return @undrawn_comm_current_notice_investor if @undrawn_comm_current_notice_investor

    investor_committment_amt = object.committed_amount

    @undrawn_comm_current_notice_investor ||= investor_committment_amt - agg_drawdown_incl_current_notice_investor
  end

  def undrawn_comm_current_notice_investor_percent
    percentage(undrawn_comm_current_notice_investor, undrawn_comm_current_notice_total)
  end

  def undrawn_comm_incl_current_notice_lp
    undrawn_comm_current_notice_lp
  end

  def undrawn_comm_incl_current_notice_gp
    undrawn_comm_current_notice_gp
  end

  def undrawn_comm_incl_current_notice_total
    undrawn_comm_current_notice_total
  end

  def undrawn_comm_incl_current_notice_investor
    undrawn_comm_current_notice_investor
  end

  def undrawn_comm_incl_current_notice_investor_percent
    percentage(undrawn_comm_incl_current_notice_investor, undrawn_comm_incl_current_notice_total)
  end
end
