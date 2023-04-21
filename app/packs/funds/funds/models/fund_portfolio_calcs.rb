class FundPortfolioCalcs
  def initialize(fund, end_date)
    @fund = fund
    @end_date = end_date
  end

  def total_investment_costs_cents
    PortfolioInvestment.total_investment_costs_cents(@fund, @end_date)
  end

  def fmv_cents
    PortfolioInvestment.fmv_cents(@fund, @end_date)
  end

  def total_investment_sold_cents
    PortfolioInvestment.total_investment_sold_cents(@fund, @end_date)
  end

  def distribution_cents
    @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:amount_cents)
  end

  def reinvested_capital_cents
    total_investment_sold_cents - distribution_cents
  end

  def cash_in_hand_cents
    ae = @fund.fund_account_entries.where(name: "Cash In Hand", reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def net_current_assets_cents
    ae = @fund.fund_account_entries.where(name: "Net Current Assets", reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def estimated_carry_cents
    ae = @fund.fund_account_entries.where(name: "Estimated Carry", reporting_date: ..@end_date).order(reporting_date: :asc).last
    ae&.amount_cents || 0
  end

  def total_value_cents
    fmv_cents + distribution_cents + cash_in_hand_cents + net_current_assets_cents
  end

  def net_total_value_cents
    total_value_cents - estimated_carry_cents
  end

  def collected_cents
    @fund.capital_remittances.verified.where(payment_date: ..@end_date).sum(:collected_amount_cents)
  end

  def committed_cents
    @fund.capital_commitments.sum(:committed_amount_cents)
  end

  def dpi
    cc = collected_cents
    cc.positive? ? (distribution_cents / cc) : 0
  end

  def rvpi
    collected_cents.positive? ? (fmv_cents / collected_cents).round(2) : 0
  end

  def tvpi
    dpi + rvpi
  end

  def fund_utilization
    committed_cents.positive? ? (total_investment_costs_cents / committed_cents) : 0
  end

  def portfolio_value_to_cost
    total_investment_costs_cents.positive? ? fmv_cents / total_investment_costs_cents : 0
  end

  # TODO
  def paid_in_to_committed_capital
    committed_cents.positive? ? collected_cents / committed_cents : 0
  end

  def gross_portfolio_irr
    cf = Xirr::Cashflow.new

    @fund.portfolio_investments.buys.where(investment_date: ..@end_date).each do |buy|
      cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date)
    end

    @fund.portfolio_investments.sells.where(investment_date: ..@end_date).each do |sell|
      cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date)
    end

    cf << Xirr::Transaction.new(fmv_on_date, date: @end_date)

    (cf.xirr * 100).round(2)
  end

  # Compute the XIRR for each portfolio company
  def portfolio_company_irr
    portfolio_companies_map = {}

    # Group all fund investments by the portfolio_company
    @fund.portfolio_investments.pool.where(investment_date: ..@end_date).order(investment_date: :asc).group_by(&:portfolio_company_id)
         .each do |portfolio_company_id, portfolio_investments|
      cf = Xirr::Cashflow.new

      # Get the buy cash flows
      Rails.logger.debug "######################"
      Rails.logger.debug "#########BUYS#########"
      portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
        cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date)
        Rails.logger.debug { "#{buy.portfolio_company_name}, #{buy.amount}, #{buy.investment_date}, #{buy.quantity}" }
      end
      Rails.logger.debug "######################"
      Rails.logger.debug "#########SELLS#########"
      # Get the sell cash flows
      portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
        cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date)
        Rails.logger.debug { "#{sell.portfolio_company_name}, #{sell.amount}, #{sell.investment_date}, #{sell.quantity}" }
      end
      Rails.logger.debug "######################"
      Rails.logger.debug "#########FMV#########"
      # Get the FMV for this specific portfolio_company
      fmv_val = fmv_on_date(portfolio_company_id)
      cf << Xirr::Transaction.new(fmv_val, date: @end_date)
      Rails.logger.debug fmv_val.to_s
      Rails.logger.debug "######################"
      Rails.logger.debug "#########XIRR#########"
      # Calculate and store the xirr
      xirr_val = (cf.xirr * 100).round(2)
      portfolio_companies_map[portfolio_company_id] = { name: portfolio_investments[0].portfolio_company_name,
                                                        xirr: xirr_val }
      Rails.logger.debug xirr
    end

    portfolio_companies_map
  end

  def portfolio_company_cost_to_value
    portfolio_companies_map = {}

    @fund.portfolio_investments.where(investment_date: ..@end_date).group_by(&:portfolio_company_id)
         .each do |portfolio_company_id, portfolio_investments|
      bought_amount = portfolio_investments.filter { |pi| pi.quantity.positive? }.sum(&:amount_cents)
      sold_amount = portfolio_investments.filter { |pi| pi.quantity.negative? }.sum(&:amount_cents)
      fmv = fmv_on_date(portfolio_company_id)

      portfolio_companies_map[portfolio_company_id] =
        { name: portfolio_investments[0].portfolio_company_name,
          value_to_cost: (sold_amount + fmv) / bought_amount }
    end

    portfolio_companies_map
  end

  def fmv_on_date(portfolio_company_id = nil)
    total_fmv_on_end_date_cents = 0
    portfolio_investments = @fund.portfolio_investments.pool.where(investment_date: ..@end_date)
    portfolio_investments = portfolio_investments.where(portfolio_company_id:) if portfolio_company_id
    portfolio_investments.group(:portfolio_company_id, :investment_type).sum(:quantity).each do |k, quantity|
      # Get the valuation as of the end date
      portfolio_company_id = k[0]
      instrument_type = k[1]
      valuation = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor",
                                  instrument_type:, valuation_date: ..@end_date).order(valuation_date: :asc).last

      # We cannot proceed without a valid valuation
      raise "No valuation found for #{Investor.find(portfolio_company_id).investor_name} prior to date #{@end_date}" unless valuation

      # Get the fmv for this portfolio_company on the @end_date
      fmv_on_end_date_cents = quantity * valuation.per_share_value_cents
      # Aggregate the fmv across the fun
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end
    total_fmv_on_end_date_cents
  end

  def xirr(net_irr: false)
    cf = Xirr::Cashflow.new

    @fund.capital_remittance_payments.where("capital_remittance_payments.payment_date <= ?", @end_date).each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date)
    end

    @fund.capital_distribution_payments.where("capital_distribution_payments.payment_date <= ?", @end_date).each do |cdp|
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date)
    end

    cf << Xirr::Transaction.new(fmv_on_date, date: @end_date)
    cf << Xirr::Transaction.new(cash_in_hand_cents, date: @end_date)
    cf << Xirr::Transaction.new(net_current_assets_cents, date: @end_date)

    cf << Xirr::Transaction.new(estimated_carry_cents, date: @end_date) if net_irr

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    Rails.logger.debug { "fund.xirr irr: #{cf.xirr}" }
    (cf.xirr * 100).round(2)
  end
end
