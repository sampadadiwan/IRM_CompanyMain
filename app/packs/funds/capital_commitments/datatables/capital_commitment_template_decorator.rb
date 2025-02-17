class CapitalCommitmentTemplateDecorator < TemplateDecorator
  include CurrencyHelper

  attr_reader :committed_cash_lp, :committed_cash_gp, :committed_cash_total, :committed_cash_investor, :committed_cash_investor_percent,
              :committed_reinvest_lp, :committed_reinvest_gp, :committed_reinvest_total, :committed_reinvest_investor, :committed_reinvest_investor_percent,
              :drawdown_cash_lp, :drawdown_cash_gp, :drawdown_cash_total, :drawdown_cash_investor, :drawdown_cash_investor_percent,
              :drawdown_reinvest_lp, :drawdown_reinvest_gp, :drawdown_reinvest_total, :drawdown_reinvest_investor, :drawdown_reinvest_investor_percent,
              :dist_cash_lp, :dist_cash_gp, :dist_cash_total, :dist_cash_investor, :dist_cash_investor_percent,
              :dist_reinvest_lp, :dist_reinvest_gp, :dist_reinvest_total, :dist_reinvest_investor, :dist_reinvest_investor_percent,
              :percentage_drawdown_cash_lp, :percentage_drawdown_cash_gp, :percentage_drawdown_cash_total, :percentage_drawdown_cash_investor,
              :undrawn_comm_lp, :undrawn_comm_gp, :undrawn_comm_total, :undrawn_comm_investor, :undrawn_comm_investor_percent,
              :percentage_unpaid_comm_lp, :percentage_unpaid_comm_gp, :percentage_unpaid_comm_total, :percentage_unpaid_comm_investor

  def initialize(object)
    super
    init_amounts(object)
  end

  def init_amounts(object)
    @end_date = Time.zone.now.end_of_day
    initialize_committed_amounts
    initialize_drawdown_amounts
    initialize_distribution_amounts
    calculate_totals(object)
  end

  private

  def initialize_committed_amounts
    @committed_cash_lp = 0
    @committed_cash_gp = 0
    @committed_reinvest_lp = 0
    @committed_reinvest_gp = 0
  end

  def initialize_drawdown_amounts
    @drawdown_cash_lp = 0
    @drawdown_cash_gp = 0
    @drawdown_reinvest_lp = 0
    @drawdown_reinvest_gp = 0
  end

  def initialize_distribution_amounts
    @dist_cash_lp = 0
    @dist_cash_gp = 0
    @dist_reinvest_lp = 0
    @dist_reinvest_gp = 0
  end

  def calculate_totals(object)
    object.fund.capital_commitments.includes(:fund, :fund_unit_setting).where(committment_date: ..@end_date).find_each do |comm|
      if comm.fund_unit_setting.gp_units
        calculate_gp_totals(comm)
      else
        calculate_lp_totals(comm)
      end
    end
    calculate_investor_totals(object)
  end

  def calculate_gp_totals(comm)
    @committed_cash_gp += comm.committed_amount
    @drawdown_cash_gp += comm.call_amount

    committed_reinvest_gp_cents = comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents)
    @committed_reinvest_gp = Money.new(committed_reinvest_gp_cents, comm.fund.currency)

    @drawdown_reinvest_gp = @committed_reinvest_gp
    dist_cash_gp_cents = comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents)
    @dist_cash_gp = Money.new(dist_cash_gp_cents, comm.fund.currency)
    @dist_reinvest_gp = @committed_reinvest_gp
  end

  def calculate_lp_totals(comm)
    @committed_cash_lp += comm.committed_amount
    @drawdown_cash_lp += comm.call_amount
    committed_reinvest_lp_cents = comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents)
    @committed_reinvest_lp = Money.new(committed_reinvest_lp_cents, comm.fund.currency)
    @drawdown_reinvest_lp = @committed_reinvest_lp
    dist_cash_lp_cents = comm.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents)
    @dist_cash_lp = Money.new(dist_cash_lp_cents, comm.fund.currency)
    @dist_reinvest_lp = @committed_reinvest_lp
  end

  def calculate_investor_totals(object) # rubocop:disable Metrics/CyclomaticComplexity
    @committed_cash_total = @committed_cash_gp + @committed_cash_lp
    @committed_cash_investor = object.committed_amount
    @committed_cash_investor_percent = @committed_cash_total.zero? ? 0 : (@committed_cash_investor / @committed_cash_total) * 100

    @committed_reinvest_total = @committed_reinvest_gp + @committed_reinvest_lp
    @committed_reinvest_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents), object.fund.currency)
    @committed_reinvest_investor_percent = @committed_reinvest_total.zero? ? 0 : (@committed_reinvest_investor / @committed_reinvest_total) * 100

    @drawdown_cash_total = @drawdown_cash_gp + @drawdown_cash_lp
    @drawdown_cash_investor = object.call_amount
    @drawdown_cash_investor_percent = @drawdown_cash_total.zero? ? 0 : (@drawdown_cash_investor / @drawdown_cash_total) * 100

    @drawdown_reinvest_total = @drawdown_reinvest_gp + @drawdown_reinvest_lp
    @drawdown_reinvest_investor = @committed_reinvest_investor
    @drawdown_reinvest_investor_percent = @drawdown_reinvest_total.zero? ? 0 : (@drawdown_reinvest_investor / @drawdown_reinvest_total) * 100

    @percentage_drawdown_cash_lp = @committed_cash_lp.zero? ? 0 : (@drawdown_cash_lp / @committed_cash_lp) * 100
    @percentage_drawdown_cash_gp = @committed_cash_gp.zero? ? 0 : (@drawdown_cash_gp / @committed_cash_gp) * 100
    @percentage_drawdown_cash_total = @committed_cash_total.zero? ? 0 : (@drawdown_cash_total / @committed_cash_total) * 100
    @percentage_drawdown_cash_investor = @committed_cash_investor.zero? ? 0 : (@drawdown_cash_investor / @committed_cash_investor) * 100

    @undrawn_comm_lp = @committed_cash_lp - @drawdown_cash_lp
    @undrawn_comm_gp = @committed_cash_gp - @drawdown_cash_gp
    @undrawn_comm_total = @committed_cash_total - @drawdown_cash_total
    @undrawn_comm_investor = @committed_cash_investor - @drawdown_cash_investor
    @undrawn_comm_investor_percent = @undrawn_comm_total.zero? ? 0 : (@undrawn_comm_investor / @undrawn_comm_total) * 100

    @percentage_unpaid_comm_lp = @committed_cash_lp.zero? ? 0 : (@undrawn_comm_lp / @committed_cash_lp) * 100
    @percentage_unpaid_comm_gp = @committed_cash_gp.zero? ? 0 : (@undrawn_comm_gp / @committed_cash_gp) * 100
    @percentage_unpaid_comm_total = @committed_cash_total.zero? ? 0 : (@undrawn_comm_total / @committed_cash_total) * 100
    @percentage_unpaid_comm_investor = @committed_cash_investor.zero? ? 0 : (@undrawn_comm_investor / @committed_cash_investor) * 100

    @dist_cash_total = @dist_cash_gp + @dist_cash_lp
    @dist_cash_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:gross_payable_cents), object.fund.currency)
    @dist_cash_investor_percent = @dist_cash_total.zero? ? 0 : (@dist_cash_investor / @dist_cash_total) * 100

    @dist_reinvest_total = @dist_reinvest_gp + @dist_reinvest_lp
    @dist_reinvest_investor = Money.new(object.capital_distribution_payments.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents), object.fund.currency)
    @dist_reinvest_investor_percent = @dist_reinvest_total.zero? ? 0 : (@dist_reinvest_investor / @dist_reinvest_total) * 100
  end
end
