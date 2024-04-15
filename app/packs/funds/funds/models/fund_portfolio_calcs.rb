class FundPortfolioCalcs
  def initialize(fund, end_date)
    @fund = fund
    @end_date = end_date
  end

  def total_investment_costs_cents
    @total_investment_costs_cents ||= PortfolioInvestment.total_investment_costs_cents(@fund, @end_date)
  end

  def fmv_cents
    @fmv_cents ||= PortfolioInvestment.fmv_cents(@fund, @end_date)
  end

  def total_investment_sold_cents
    @total_investment_sold_cents ||= PortfolioInvestment.total_investment_sold_cents(@fund, @end_date)
  end

  def distribution_cents
    @distribution_cents ||= @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:amount_cents)
  end

  def reinvested_capital_cents
    total_investment_sold_cents - distribution_cents
  end

  def cash_in_hand_cents
    @cash_in_hand_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Cash In Hand", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def net_current_assets_cents
    @net_current_assets_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Net Current Assets", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def estimated_carry_cents
    @estimated_carry_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Estimated Carry", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def total_value_cents
    fmv_cents + distribution_cents + cash_in_hand_cents + net_current_assets_cents
  end

  def net_total_value_cents
    total_value_cents - estimated_carry_cents
  end

  def collected_cents
    @collected_cents ||= @fund.capital_remittances.verified.where(payment_date: ..@end_date).sum(:collected_amount_cents)
  end

  def committed_cents
    @committed_cents ||= @fund.capital_commitments.sum(:committed_amount_cents)
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
    @gross_portfolio_irr ||= begin
      cf = Xirr::Cashflow.new

      # Get the buy cash flows
      @fund.portfolio_investments.buys.where(investment_date: ..@end_date).find_each do |buy|
        cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Bought Amount") if buy.amount_cents.positive?
      end

      # Get the sell cash flows
      @fund.portfolio_investments.sells.where(investment_date: ..@end_date).find_each do |sell|
        cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sold Amount") if sell.amount_cents.positive?
      end

      # Get the FMV
      cf << Xirr::Transaction.new(fmv_on_date, date: @end_date, notes: "FMV on Date") if fmv_on_date.positive?

      lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
      (lxirr * 100).round(2)
    end
  end

  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil)
    @api_map ||= {}

    if @api_map.empty?

      @fund.aggregate_portfolio_investments.pool.each do |api|
        portfolio_company_id = api.portfolio_company_id

        portfolio_investments = api.portfolio_investments.where(investment_date: ..@end_date)
        cf = Xirr::Cashflow.new

        # Get the buy cash flows
        Rails.logger.debug "#########BUYS#########"
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        Rails.logger.debug "#########SELLS#########"
        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        Rails.logger.debug "#########Portfolio CF#########"
        # Get the portfolio income cash flows, but only for pool and for this investment_type
        portfolio_cashflows = api.portfolio_cashflows.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          cf << Xirr::Transaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
        end

        # Get the FMV for this specific portfolio_company
        fmv_val = fmv_on_date(api, scenarios:).round(4)
        cf << Xirr::Transaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0

        Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
        # Calculate and store the xirr

        lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "#{api.id} xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @api_map[api.id] = { name: api.to_s, xirr: xirr_val, cash_flows: }
      end

    end

    @api_map
  end

  def portfolio_company_cost_to_value
    @api_map ||= {}

    @fund.aggregate_portfolio_investments.pool.each do |api|
      portfolio_investments = api.portfolio_investments.where(investment_date: ..@end_date)

      bought_amount = portfolio_investments.filter { |pi| pi.quantity.positive? }.sum(&:amount_cents)
      sold_amount = portfolio_investments.filter { |pi| pi.quantity.negative? }.sum(&:amount_cents)
      fmv = fmv_on_date(api)

      @api_map[api.id] = { name: api.to_s, value_to_cost: (sold_amount + fmv) / bought_amount } if bought_amount.positive?
    end

    @api_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0

    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : @fund.aggregate_portfolio_investments.pool

    Rails.logger.debug apis

    apis.each do |api|
      portfolio_investments = api.portfolio_investments.where(investment_date: ..@end_date)
      quantity = portfolio_investments.inject(0) { |sum, pi| sum + pi.quantity }

      portfolio_company_id = api.portfolio_company_id

      valuation = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", investment_instrument: api.investment_instrument, valuation_date: ..@end_date).order(valuation_date: :asc).last

      # We cannot proceed without a valid valuation
      raise "No valuation found for #{Investor.find(portfolio_company_id).investor_name} prior to date #{@end_date}" unless valuation

      # Get the fmv for this portfolio_company on the @end_date
      fmv_on_end_date_cents = quantity * valuation.per_share_value_in(@fund.currency, @end_date)
      fmv_on_end_date_cents = (fmv_on_end_date_cents * (1 + (scenarios[api.id.to_s]["percentage_change"].to_f / 100))).round(4) if api && scenarios && scenarios[api.id.to_s]["percentage_change"].present?

      # Aggregate the fmv across the fun
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end

    total_fmv_on_end_date_cents
  end

  # Calculate the IRR for the fund
  # net_irr: true/false - if true, then the IRR is calculated net of Estimated Carry
  # return_cash_flows: true/false - if true, then the cash flows used in computation are returned
  # adjustment_cash: amount to be added to the cash flows, used specifically for scenarios. see PortfolioScenarioJob
  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil)
    cf = Xirr::Cashflow.new

    @fund.capital_remittance_payments.includes(:capital_remittance).where("capital_remittance_payments.payment_date <= ?", @end_date).find_each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id} ")
    end

    @fund.capital_distribution_payments.includes(:investor).where("capital_distribution_payments.payment_date <= ?", @end_date).find_each do |cdp|
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Distribution #{cdp.id}")
    end

    cf << Xirr::Transaction.new(fmv_on_date(scenarios:), date: @end_date, notes: "FMV") if fmv_on_date != 0
    cf << Xirr::Transaction.new(cash_in_hand_cents, date: @end_date, notes: "Cash in Hand") if cash_in_hand_cents != 0
    cf << Xirr::Transaction.new(net_current_assets_cents, date: @end_date, notes: "Net Current Assets") if net_current_assets_cents != 0

    cf << Xirr::Transaction.new(estimated_carry_cents, date: @end_date, notes: "Estimated carry") if net_irr
    cf << Xirr::Transaction.new(adjustment_cash, date: @end_date, notes: "Adjustment Cash") if adjustment_cash != 0

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    cf.each do |cash_flow|
      Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}"
    end

    lxirr = XirrApi.new.xirr(cf, "xirr_#{@fund.id}_#{@end_date}") || 0
    Rails.logger.debug { "fund.xirr irr: #{lxirr}" }
    if return_cash_flows
      [(lxirr * 100).round(2), cf]
    else
      (lxirr * 100).round(2)
    end
  end

  def sample_xirr(count)
    cf = Xirr::Cashflow.new
    (1..count).each do |_i|
      cf << Xirr::Transaction.new(-1 * rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)

      cf << Xirr::Transaction.new(rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)
    end

    Rails.logger.debug cf

    XirrApi.new.xirr(cf, "sample_xirr")
  end
end
