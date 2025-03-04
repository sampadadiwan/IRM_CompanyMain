class CapitalRemittanceTemplateDecorator < TemplateDecorator # rubocop:disable Metrics/ClassLength
  include CurrencyHelper

  attr_reader :curr_date, :end_date, :currency

  def initialize(object)
    super
    @curr_date = object.remittance_date
    @end_date = (object.remittance_date - 1.day).end_of_day
    @currency = object.fund.currency
    @cache = {} # Cache for computed values
  end

  # === Helper Methods ===

  def money_sum(scope, column)
    scope.empty? ? Money.new(0, @currency) : Money.new(scope.sum(column), @currency)
  end

  def percentage(part, total)
    part = part.cents.to_f if part.respond_to?(:cents)
    total = total.cents.to_f if total.respond_to?(:cents)
    total.zero? ? 0 : (part / total) * 100
  end

  # === Data Loading Methods with Caching ===

  def capital_calls
    @cache[:capital_calls] ||= object.fund.capital_calls.where(call_date: ..@end_date)
  end

  def current_capital_calls
    @cache[:current_capital_calls] ||= object.fund.capital_calls.where(call_date: ..@curr_date)
  end

  def prior_lp_remittances
    @cache[:prior_lp_remittances] ||= begin
      ids = []
      capital_calls.each do |call|
        call.capital_remittances.where(remittance_date: ..@end_date).find_each do |cr|
          ids << cr.id unless cr.capital_commitment.fund_unit_setting&.gp_units
        end
      end
      object.fund.capital_remittances.where(id: ids)
    end
  end

  def prior_gp_remittances
    @cache[:prior_gp_remittances] ||= begin
      ids = []
      capital_calls.each do |call|
        call.capital_remittances.where(remittance_date: ..@end_date).find_each do |cr|
          ids << cr.id if cr.capital_commitment.fund_unit_setting&.gp_units
        end
      end
      object.fund.capital_remittances.where(id: ids)
    end
  end

  def prior_remittances_investor
    @cache[:prior_remittances_investor] ||= prior_lp_remittances.where(capital_commitment_id: object.capital_commitment_id)
                                                                .or(prior_gp_remittances.where(capital_commitment_id: object.capital_commitment_id))
  end

  def current_lp_remittances
    @cache[:current_lp_remittances] ||= begin
      ids = []
      object.capital_call.capital_remittances.where(remittance_date: @curr_date).find_each do |cr|
        ids << cr.id unless cr.capital_commitment.fund_unit_setting&.gp_units
      end
      object.fund.capital_remittances.where(id: ids)
    end
  end

  def current_gp_remittances
    @cache[:current_gp_remittances] ||= begin
      ids = []
      object.capital_call.capital_remittances.where(remittance_date: @curr_date).find_each do |cr|
        ids << cr.id if cr.capital_commitment.fund_unit_setting&.gp_units
      end
      object.fund.capital_remittances.where(id: ids)
    end
  end

  def current_remittances_investor
    @cache[:current_remittances_investor] ||= current_lp_remittances.where(capital_commitment_id: object.capital_commitment_id)
                                                                    .or(current_gp_remittances.where(capital_commitment_id: object.capital_commitment_id))
  end

  # Optimized committments and remittances
  def prior_calls_data
    @cache[:prior_calls_data] ||= begin
      lp_commitment_ids = []
      gp_commitment_ids = []
      lp_remittance_ids = []
      gp_remittance_ids = []

      capital_calls.includes(capital_remittances: :capital_commitment).each do |call|
        call.capital_remittances.each do |cr|
          if cr.remittance_date <= @end_date
            if cr.capital_commitment.fund_unit_setting&.gp_units
              gp_commitment_ids << cr.capital_commitment_id
              gp_remittance_ids << cr.id
            else
              lp_commitment_ids << cr.capital_commitment_id
              lp_remittance_ids << cr.id
            end
          end
        end
      end

      {
        lp_commitments: object.fund.capital_commitments.where(id: lp_commitment_ids.uniq).order(:commitment_date),
        gp_commitments: object.fund.capital_commitments.where(id: gp_commitment_ids.uniq).order(:commitment_date),
        lp_remittances: object.fund.capital_remittances.where(id: lp_remittance_ids),
        gp_remittances: object.fund.capital_remittances.where(id: gp_remittance_ids)
      }
    end
  end

  def prior_calls_lp_committments
    prior_calls_data[:lp_commitments]
  end

  def prior_calls_gp_committments
    prior_calls_data[:gp_commitments]
  end

  def prior_calls_lp_remittances
    prior_calls_data[:lp_remittances]
  end

  def prior_calls_gp_remittances
    prior_calls_data[:gp_remittances]
  end

  def current_calls_data
    @cache[:current_calls_data] ||= begin
      lp_commitment_ids = []
      gp_commitment_ids = []
      lp_remittance_ids = []
      gp_remittance_ids = []

      current_capital_calls.includes(capital_remittances: :capital_commitment).each do |call|
        call.capital_remittances.each do |cr|
          if cr.remittance_date <= @curr_date
            if cr.capital_commitment.fund_unit_setting&.gp_units
              gp_commitment_ids << cr.capital_commitment_id
              gp_remittance_ids << cr.id
            else
              lp_commitment_ids << cr.capital_commitment_id
              lp_remittance_ids << cr.id
            end
          end
        end
      end

      {
        lp_commitments: object.fund.capital_commitments.where(id: lp_commitment_ids.uniq).order(:commitment_date),
        gp_commitments: object.fund.capital_commitments.where(id: gp_commitment_ids.uniq).order(:commitment_date),
        lp_remittances: object.fund.capital_remittances.where(id: lp_remittance_ids),
        gp_remittances: object.fund.capital_remittances.where(id: gp_remittance_ids)
      }
    end
  end

  def current_calls_lp_committments
    current_calls_data[:lp_commitments]
  end

  def current_calls_gp_committments
    current_calls_data[:gp_commitments]
  end

  def current_calls_lp_remittances
    current_calls_data[:lp_remittances]
  end

  def current_calls_gp_remittances
    current_calls_data[:gp_remittances]
  end

  # === Cash Calculations ===

  def cash_prior_notice_lp
    @cache[:cash_prior_notice_lp] ||= money_sum(prior_lp_remittances, :computed_amount_cents)
  end

  def cash_prior_notice_gp
    @cache[:cash_prior_notice_gp] ||= money_sum(prior_gp_remittances, :computed_amount_cents)
  end

  def cash_prior_notice_total
    @cache[:cash_prior_notice_total] ||= cash_prior_notice_lp + cash_prior_notice_gp
  end

  def cash_prior_notice_investor
    @cache[:cash_prior_notice_investor] ||= money_sum(prior_remittances_investor, :computed_amount_cents)
  end

  def cash_prior_notice_investor_percent
    percentage(cash_prior_notice_investor, cash_prior_notice_total)
  end

  def cash_current_notice_lp
    @cache[:cash_current_notice_lp] ||= money_sum(current_lp_remittances, :computed_amount_cents)
  end

  def cash_current_notice_gp
    @cache[:cash_current_notice_gp] ||= money_sum(current_gp_remittances, :computed_amount_cents)
  end

  def cash_current_notice_total
    @cache[:cash_current_notice_total] ||= cash_current_notice_lp + cash_current_notice_gp
  end

  def cash_current_notice_investor
    @cache[:cash_current_notice_investor] ||= object.computed_amount
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

  # === Fees Calculations ===

  def fees_prior_notice_lp
    @cache[:fees_prior_notice_lp] ||= money_sum(prior_lp_remittances, :capital_fee_cents) +
                                      money_sum(prior_lp_remittances, :other_fee_cents)
  end

  def fees_prior_notice_gp
    @cache[:fees_prior_notice_gp] ||= money_sum(prior_gp_remittances, :capital_fee_cents) +
                                      money_sum(prior_gp_remittances, :other_fee_cents)
  end

  def fees_prior_notice_total
    fees_prior_notice_lp + fees_prior_notice_gp
  end

  def fees_prior_notice_investor
    @cache[:fees_prior_notice_investor] ||= money_sum(prior_remittances_investor, :capital_fee_cents) +
                                            money_sum(prior_remittances_investor, :other_fee_cents)
  end

  def fees_prior_notice_investor_percent
    percentage(fees_prior_notice_investor, fees_prior_notice_total)
  end

  def fees_current_notice_lp
    @cache[:fees_current_notice_lp] ||= money_sum(current_lp_remittances, :capital_fee_cents) +
                                        money_sum(current_lp_remittances, :other_fee_cents)
  end

  def fees_current_notice_gp
    @cache[:fees_current_notice_gp] ||= money_sum(current_gp_remittances, :capital_fee_cents) +
                                        money_sum(current_gp_remittances, :other_fee_cents)
  end

  def fees_current_notice_total
    fees_current_notice_lp + fees_current_notice_gp
  end

  def fees_current_notice_investor
    @cache[:fees_current_notice_investor] ||= object.capital_fee + object.other_fee
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

  # === Aggregate Drawdown Calculations ===

  def agg_drawdown_prior_notice_lp
    @cache[:agg_drawdown_prior_notice_lp] ||= cash_prior_notice_lp + fees_prior_notice_lp
  end

  def agg_drawdown_prior_notice_gp
    @cache[:agg_drawdown_prior_notice_gp] ||= cash_prior_notice_gp + fees_prior_notice_gp
  end

  def agg_drawdown_prior_notice_total
    agg_drawdown_prior_notice_lp + agg_drawdown_prior_notice_gp
  end

  def agg_drawdown_prior_notice_investor
    @cache[:agg_drawdown_prior_notice_investor] ||= cash_prior_notice_investor + fees_prior_notice_investor
  end

  def agg_drawdown_prior_notice_investor_percent
    percentage(agg_drawdown_prior_notice_investor, agg_drawdown_prior_notice_total)
  end

  def agg_drawdown_current_notice_lp
    @cache[:agg_drawdown_current_notice_lp] ||= cash_current_notice_lp + fees_current_notice_lp
  end

  def agg_drawdown_current_notice_gp
    @cache[:agg_drawdown_current_notice_gp] ||= cash_current_notice_gp + fees_current_notice_gp
  end

  def agg_drawdown_current_notice_total
    agg_drawdown_current_notice_lp + agg_drawdown_current_notice_gp
  end

  def agg_drawdown_current_notice_investor
    @cache[:agg_drawdown_current_notice_investor] ||= cash_current_notice_investor + fees_current_notice_investor
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

  # === Undrawn Commitments Calculations ===

  def undrawn_comm_prior_notice_lp
    @cache[:undrawn_comm_prior_notice_lp] ||= begin
      last_call_before = capital_calls.order(:call_date).last
      prior_lp_committment_amt = Money.new(0, @currency)

      if last_call_before
        prior_lp_committment_amt = money_sum(
          prior_calls_lp_remittances.where(capital_call_id: last_call_before.id),
          :committed_amount_cents
        )
      end

      prior_lp_committment_amt = money_sum(current_calls_lp_remittances, :committed_amount_cents) if prior_lp_committment_amt.zero?

      prior_lp_committment_amt = object.committed_amount if prior_lp_committment_amt.zero?
      prior_lp_committment_amt - agg_drawdown_prior_notice_lp
    end
  end

  def undrawn_comm_prior_notice_gp
    @cache[:undrawn_comm_prior_notice_gp] ||= begin
      last_call_before = capital_calls.order(:call_date).last
      prior_gp_committment_amt = Money.new(0, @currency)

      if last_call_before
        prior_gp_committment_amt = money_sum(
          prior_calls_gp_remittances.where(capital_call_id: last_call_before.id),
          :committed_amount_cents
        )
      end

      prior_gp_committment_amt = money_sum(current_calls_gp_remittances, :committed_amount_cents) if prior_gp_committment_amt.zero?

      prior_gp_committment_amt = object.committed_amount if prior_gp_committment_amt.zero?
      prior_gp_committment_amt - agg_drawdown_prior_notice_gp
    end
  end

  def undrawn_comm_prior_notice_total
    undrawn_comm_prior_notice_lp + undrawn_comm_prior_notice_gp
  end

  def undrawn_comm_prior_notice_investor
    @cache[:undrawn_comm_prior_notice_investor] ||= object.committed_amount - agg_drawdown_prior_notice_investor
  end

  def undrawn_comm_prior_notice_investor_percent
    percentage(undrawn_comm_prior_notice_investor, undrawn_comm_prior_notice_total)
  end

  def undrawn_comm_current_notice_lp
    @cache[:undrawn_comm_current_notice_lp] ||= begin
      current_lp_committment_amt = money_sum(
        current_calls_lp_remittances.where(capital_call_id: object.capital_call_id),
        :committed_amount_cents
      )
      current_lp_committment_amt = object.committed_amount if current_lp_committment_amt.zero?
      current_lp_committment_amt - agg_drawdown_incl_current_notice_lp
    end
  end

  def undrawn_comm_current_notice_gp
    @cache[:undrawn_comm_current_notice_gp] ||= begin
      current_gp_committment_amt = money_sum(
        current_calls_gp_remittances.where(capital_call_id: object.capital_call_id),
        :committed_amount_cents
      )
      current_gp_committment_amt = object.committed_amount if current_gp_committment_amt.zero?
      current_gp_committment_amt - agg_drawdown_incl_current_notice_gp
    end
  end

  def undrawn_comm_current_notice_total
    undrawn_comm_current_notice_lp + undrawn_comm_current_notice_gp
  end

  def undrawn_comm_current_notice_investor
    @cache[:undrawn_comm_current_notice_investor] ||= object.committed_amount - agg_drawdown_incl_current_notice_investor
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
