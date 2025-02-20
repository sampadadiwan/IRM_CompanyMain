class CapitalRemittanceTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper

  def drawdown_cash
    cash_lp = 0
    cash_gp = 0
    object.fund.capital_remittances.includes(capital_commitment: :fund).find_each do |remit|
      if remit.capital_commitment.fund.fund_unit_setting.gp_units
        cash_gp += remit.collected_amount
      else
        cash_lp += remit.collected_amount
      end
    end
    cash_total = cash_gp + cash_lp
    OpenStruct.new({ gp: cash_gp, lp: cash_lp, total: cash_total, investor: object.committed_amount, investor_percent: (object.committed_amount / cash_total) * 100 })
  end

  def initialize(object)
    super
    @end_date = Time.zone.now.end_of_day
    @currency = object.fund.currency
  end

  def money_sum(scope, column)
    Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
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
          if cr.capital_commitment.fund_unit_setting.gp_units
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
    @cash_prior_notice_investor ||= money_sum(prior_remittances_investor, :collected_amount_cents)
  end

  def cash_prior_notice_investor_percent
    percentage(cash_prior_notice_investor, cash_prior_notice_total)
  end

  def init_current_remittances
    if @current_lp_remittances.nil? || @current_gp_remittances.nil?

      current_lp_remittances_ids = []
      current_gp_remittances_ids = []

      object.capital_call.capital_remittances.where(remittance_date: @end_date).find_each do |cr|
        if cr.capital_commitment.fund_unit_setting.gp_units
          current_gp_remittances_ids << cr.id
        else
          current_lp_remittances_ids << cr.id
        end
      end

      @current_lp_remittances = object.fund.capital_remittances.where(id: prior_lp_remittances_ids)
      @current_gp_remittances = object.fund.capital_remittances.where(id: prior_gp_remittances_ids)
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
    @cash_current_notice_investor ||= object.computed_amount_cents
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
    init_prior_remittances
    @fees_prior_notice_investor ||= money_sum(prior_remittances_investor, :capital_fee_cents) + money_sum(prior_remittances_investor, :other_fee_cents)
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
    @fees_current_notice_investor ||= object.captital_fee + object.other_fee
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
    percentage(fees_incl_current_notice_total, fees_incl_current_notice_investor)
  end

  def agg_drawdown_prior_notice_lp
    init_current_remittances
    @agg_drawdown_prior_notice_lp ||= money_sum(@current_lp_remittances, :call_amount_cents)
  end

  def agg_drawdown_prior_notice_gp
    init_current_remittances
    @agg_drawdown_prior_notice_gp ||= money_sum(@current_gp_remittances, :call_amount_cents)
  end

  def agg_drawdown_prior_notice_total
    agg_drawdown_prior_notice_lp + agg_drawdown_prior_notice_gp
  end

  def agg_drawdown_prior_notice_investor
    init_prior_remittances_investor
    @agg_drawdown_prior_notice_investor ||= money_sum(@prior_remittances_investor, :call_amount_cents)
  end

  def agg_drawdown_prior_notice_investor_percent
    percentage(agg_drawdown_prior_notice_investor, agg_drawdown_prior_notice_total)
  end

  def agg_drawdown_current_notice_lp
    init_current_remittances
    @agg_drawdown_current_notice_lp ||= money_sum(@current_lp_remittances, :call_amount_cents)
  end

  def agg_drawdown_current_notice_gp
    init_current_remittances
    @agg_drawdown_current_notice_gp ||= money_sum(@current_gp_remittances, :call_amount_cents)
  end

  def agg_drawdown_current_notice_total
    agg_drawdown_current_notice_lp + agg_drawdown_current_notice_gp
  end

  def init_current_remittances_investor
    init_current_remittances
    @current_remittances_investor = @current_lp_remittances.where(capital_commitment_id: object.capital_commitment_id).or(@current_gp_remittances.where(capital_commitment_id: object.capital_commitment_id)) if @current_remittances_investor.nil?
  end

  def agg_drawdown_current_notice_investor
    init_current_remittances_investor
    @agg_drawdown_current_notice_investor ||= money_sum(@current_remittances_investor, :call_amount_cents)
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

  def init_prior_calls_committments
    if @prior_calls_lp_committments.nil? || @prior_calls_gp_committments.nil?

      prior_calls_lp_committments_ids = []
      prior_calls_gp_committments_ids = []

      capital_calls = object.fund.capital_calls.where(call_date: ..@end_date)
      capital_calls.each do |call|
        call.capital_commitments.where(commitment_date: ..@end_date).find_each do |cc|
          if cc.fund_unit_setting.gp_units
            prior_calls_gp_committments_ids << cc.id
          else
            prior_calls_lp_committments_ids << cc.id
          end
        end
      end

      @prior_calls_lp_committments = object.fund.capital_commitments.where(id: prior_calls_lp_committments_ids).order(:commitment_date)
      @prior_calls_gp_committments = object.fund.capital_commitments.where(id: prior_calls_gp_committments_ids).order(:commitment_date)
    end
  end

  def init_current_calls_committments
    if @current_calls_lp_committments.nil? || @current_calls_gp_committments.nil?

      current_calls_lp_committments_ids = []
      current_calls_gp_committments_ids = []

      object.capital_call.capital_commitments.where(commitment_date: @end_date).find_each do |cc|
        if cc.fund_unit_setting.gp_units
          current_calls_gp_committments_ids << cc.id
        else
          current_calls_lp_committments_ids << cc.id
        end
      end

      @current_calls_lp_committments = object.fund.capital_commitments.where(id: current_calls_lp_committments_ids).order(:commitment_date)
      @current_calls_gp_committments = object.fund.capital_commitments.where(id: current_calls_gp_committments_ids).order(:commitment_date)
    end
  end

  def undrawn_comm_prior_notice_lp
    return @undrawn_comm_prior_notice_lp if @undrawn_comm_prior_notice_lp

    init_prior_calls_committments
    init_prior_remittances
    prior_lp_committment_amt = @prior_calls_lp_committments.order(:commitment_date).last.committed_amount_cents
    prior_lp_remittances_call_amt_sum = money_sum(@prior_lp_remittances, :call_amount_cents)
    @undrawn_comm_prior_notice_lp = prior_lp_committment_amt - prior_lp_remittances_call_amt_sum
  end

  def undrawn_comm_prior_notice_gp
    return @undrawn_comm_prior_notice_gp if @undrawn_comm_prior_notice_gp

    init_prior_calls_committments
    init_prior_remittances
    prior_gp_committment_amt = @prior_calls_gp_committments.order(:commitment_date).last.committed_amount_cents
    prior_gp_remittances_call_amt_sum = money_sum(@prior_gp_remittances, :call_amount_cents)
    @undrawn_comm_prior_notice_gp = prior_gp_committment_amt - prior_gp_remittances_call_amt_sum
  end

  def undrawn_comm_prior_notice_total
    undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp
  end

  def undrawn_comm_prior_notice_investor
    return @undrawn_comm_prior_notice_investor if @undrawn_comm_prior_notice_investor

    init_prior_calls_committments
    init_prior_remittances_investor

    # only one of these will be present
    investor_committment_amt = @prior_calls_lp_committments.where(capital_commitment_id: object.capital_commitment_id).last&.committed_amount || Money.new(0, @currency)
    investor_committment_amt += @prior_calls_gp_committments.where(capital_commitment_id: object.capital_commitment_id).last&.committed_amount || Money.new(0, @currency)
    investor_remittances_call_amt_sum = money_sum(@prior_lp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents) + money_sum(@prior_gp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents)
    @undrawn_comm_prior_notice_investor ||= investor_committment_amt - investor_remittances_call_amt_sum
  end

  def undrawn_comm_prior_notice_investor_percent
    percentage(undrawn_comm_prior_notice_investor, undrawn_comm_prior_notice_total)
  end

  def init_current_calls_remittances
    if @current_calls_lp_remittances.nil? || @current_calls_gp_remittances.nil?

      current_calls_lp_remittances_ids = []
      current_calls_gp_remittances_ids = []

      object.capital_call.capital_remittances.where(remittance_date: ..@end_date).find_each do |cr|
        if cr.capital_commitment.fund_unit_setting.gp_units
          current_calls_gp_remittances_ids << cr.id
        else
          current_calls_lp_remittances_ids << cr.id
        end
      end

      @current_calls_lp_remittances = object.fund.capital_remittances.where(id: prior_lp_remittances_ids)
      @current_calls_gp_remittances = object.fund.capital_remittances.where(id: prior_gp_remittances_ids)
    end
  end

  def undrawn_comm_current_notice_lp
    return @undrawn_comm_current_notice_lp if @undrawn_comm_current_notice_lp

    init_current_calls_committments
    init_prior_remittances
    init_current_calls_remittances

    current_lp_committment_amt = @current_calls_lp_committments.order(:commitment_date).last.committed_amount
    # take all remittances of the all calls before end date including the current call
    till_current_lp_remittances_call_amt_sum = money_sum(@prior_lp_remittances, :call_amount_cents) + money_sum(@current_calls_lp_remittances, :call_amount_cents)
    @undrawn_comm_current_notice_lp = current_lp_committment_amt - till_current_lp_remittances_call_amt_sum
  end

  def undrawn_comm_current_notice_gp
    return @undrawn_comm_current_notice_gp if @undrawn_comm_current_notice_gp

    init_current_calls_committments
    init_prior_remittances
    init_current_calls_remittances

    current_gp_committment_amt = @current_calls_gp_committments.order(:commitment_date).last.committed_amount

    till_current_gp_remittances_call_amt_sum = money_sum(@prior_gp_remittances, :call_amount_cents) + money_sum(@current_calls_gp_remittances, :call_amount_cents)
    @undrawn_comm_current_notice_gp = current_gp_committment_amt - till_current_gp_remittances_call_amt_sum
  end

  def undrawn_comm_current_notice_total
    undrawn_comm_current_notice_lp + undrawn_comm_current_notice_gp
  end

  def undrawn_comm_current_notice_investor
    return @undrawn_comm_current_notice_investor if @undrawn_comm_current_notice_investor

    init_current_calls_committments
    init_current_calls_remittances_investor

    investor_committment_amt = @current_calls_lp_committments.where(capital_commitment_id: object.capital_commitment_id).last&.committed_amount || Money.new(0, @currency)
    investor_committment_amt += @current_calls_gp_committments.where(capital_commitment_id: object.capital_commitment_id).last&.committed_amount || Money.new(0, @currency)

    prior_investor_remittances_call_amt_sum = money_sum(@prior_lp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents) + money_sum(@prior_gp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents)

    current_investor_remittances_call_amt_sum = money_sum(@current_calls_lp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents) + money_sum(@current_calls_gp_remittances.where(capital_commitment_id: object.capital_commitment_id), :call_amount_cents)

    investor_remittances_call_amt_sum = prior_investor_remittances_call_amt_sum + current_investor_remittances_call_amt_sum

    @undrawn_comm_current_notice_investor ||= investor_committment_amt - investor_remittances_call_amt_sum
  end

  def undrawn_comm_current_notice_investor_percent
    percentage(undrawn_comm_current_notice_investor, undrawn_comm_current_notice_total)
  end

  def undrawn_comm_incl_current_notice_lp
    undrawn_comm_prior_notice_lp + undrawn_comm_current_notice_lp
  end

  def undrawn_comm_incl_current_notice_gp
    undrawn_comm_prior_notice_gp + undrawn_comm_current_notice_gp
  end

  def undrawn_comm_incl_current_notice_total
    undrawn_comm_prior_notice_total + undrawn_comm_current_notice_total
  end

  def undrawn_comm_incl_current_notice_investor
    undrawn_comm_prior_notice_investor + undrawn_comm_current_notice_investor
  end

  def undrawn_comm_incl_current_notice_investor_percent
    percentage(undrawn_comm_incl_current_notice_investor, undrawn_comm_incl_current_notice_total)
  end
end
