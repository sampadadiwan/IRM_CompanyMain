class FundPortfolioCalcs
  def initialize(fund, end_date)
    @fund = fund
    @end_date = end_date
  end

  def total_investment_costs_cents
    @total_investment_costs_cents ||= PortfolioInvestment.total_investment_costs_cents(@fund, @end_date)
  end

  def fmv_cents
    @fmv_cents ||= fmv_on_date
  end

  def total_investment_sold_cents
    @total_investment_sold_cents ||= PortfolioInvestment.total_investment_sold_cents(@fund, @end_date)
  end

  def distribution_cents
    @distribution_cents ||= @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:gross_payable_cents) -
                            @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents)
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
    if collected_cents.positive? # ? (fmv_cents / collected_cents).round(2) : 0
      ((fmv_cents + net_current_assets_cents + cash_in_hand_cents) / collected_cents)
    else
      0
    end
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
      cf = XirrCashflow.new

      # Get the buy cash flows
      @fund.portfolio_investments.buys.where(investment_date: ..@end_date).find_each do |buy|
        cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Bought Amount") if buy.amount_cents.positive?
      end

      # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
      Rails.logger.debug "#########StockConversion#########"
      @fund.stock_conversions.where(conversion_date: ..@end_date).find_each do |sc|
        quantity = sc.from_quantity
        pi = sc.from_portfolio_investment
        cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
      end

      # Get the sell cash flows
      @fund.portfolio_investments.sells.where(investment_date: ..@end_date).find_each do |sell|
        cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sold Amount") if sell.amount_cents.positive?
      end

      # Get the FMV
      cf << XirrTransaction.new(fmv_on_date, date: @end_date, notes: "FMV on Date") if fmv_on_date.positive?

      # loop over all apis
      @fund.aggregate_portfolio_investments.each do |api|
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
        end
      end

      lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
      (lxirr * 100).round(2)
    end
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil)
    @portfolio_company_irr_map ||= {}

    if @portfolio_company_irr_map.empty?
      # Get all the Portfolio companies
      @fund.portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id| # rubocop:disable Metrics/BlockLength
        portfolio_company = Investor.find(portfolio_company_id)
        # Get all the portfolio investments for this portfolio company before the end date
        portfolio_investments = @fund.portfolio_investments.where(portfolio_company_id:, investment_date: ..@end_date)
        cf = XirrCashflow.new

        # Get the buy cash flows
        Rails.logger.debug "#########BUYS#########"
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        Rails.logger.debug "#########StockConversion#########"
        @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        Rails.logger.debug "#########SELLS#########"
        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        Rails.logger.debug "#########FMV & Portfolio CF#########"

        # Get the FMV for this specific portfolio_company
        @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
          # Get the portfolio income cash flows
          portfolio_cashflows = api.portfolio_cashflows.actual.where(portfolio_company_id:, payment_date: ..@end_date)
          portfolio_cashflows.each do |pcf|
            cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
          end

          # Get the FMV for this specific portfolio_company
          fmv_val = fmv_on_date(api, scenarios:).round(4)
          cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0
          Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
        end

        # Calculate and store the xirr
        lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "#{portfolio_company_id} xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @portfolio_company_irr_map[portfolio_company_id] = { name: portfolio_company.investor_name, xirr: xirr_val, cash_flows: }
      end

    end

    @portfolio_company_irr_map
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/BlockLength

  def portfolio_company_cost_to_value
    @portfolio_company_cost_map ||= {}

    @fund.aggregate_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
      portfolio_company = Investor.find(portfolio_company_id)
      portfolio_investments = @fund.portfolio_investments.where(portfolio_company_id:, investment_date: ..@end_date)
      # Get the bought
      bought_amount = portfolio_investments.filter { |pi| pi.quantity.positive? }.sum(&:cost_of_remaining_cents)

      # Calc the total fmv for the portfolio_company
      total_fmv = 0
      @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
        total_fmv += fmv_on_date(api)
      end

      # Store the value to cost ratio
      @portfolio_company_cost_map[portfolio_company_id] = { name: portfolio_company.investor_name, value_to_cost: total_fmv / bought_amount } if bought_amount.positive?
    end

    @portfolio_company_cost_map
  end

  # Compute the XIRR for each API
  def api_irr(return_cash_flows: false, scenarios: nil)
    @api_irr_map ||= {}

    if @api_irr_map.empty?

      @fund.aggregate_portfolio_investments.each do |api|
        api.portfolio_company_id

        portfolio_investments = api.portfolio_investments.where(investment_date: ..@end_date)
        cf = XirrCashflow.new

        # Get the buy cash flows
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        # Get the portfolio income cash flows
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
        end

        # Get the FMV for this specific portfolio_company
        fmv_val = fmv_on_date(api, scenarios:).round(4)
        cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0

        Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
        # Calculate and store the xirr

        lxirr = XirrApi.new.xirr(cf, "api_irr:#{api.id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "#{api.id} xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @api_irr_map[api.id] = { name: api.to_s, xirr: xirr_val, cash_flows: }
      end

    end

    Rails.logger.debug @api_irr_map
    @api_irr_map
  end

  def api_cost_to_value
    @api_cost_map ||= {}

    @fund.aggregate_portfolio_investments.each do |api|
      portfolio_investments = api.portfolio_investments.where(investment_date: ..@end_date)

      bought_amount = portfolio_investments.filter { |pi| pi.quantity.positive? }.sum(&:cost_of_remaining_cents)

      fmv = fmv_on_date(api)

      @api_cost_map[api.id] = { name: api.to_s, value_to_cost: (fmv / bought_amount) } if bought_amount.positive?
    end

    @api_cost_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0

    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : @fund.aggregate_portfolio_investments

    Rails.logger.debug apis

    apis.each do |api|
      # We hold in our portfolio only the buys and specifically thier net_quantity. Hence use only that for fmv
      portfolio_investments = api.portfolio_investments.buys.where(investment_date: ..@end_date)
      next if portfolio_investments.blank?

      net_quantity = portfolio_investments.inject(0) { |sum, pi| sum + pi.net_quantity }
      Rails.logger.debug { "#{api.portfolio_company.investor_name}: net_quantity = #{net_quantity}" }
      portfolio_company_id = api.portfolio_company_id

      valuation = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", investment_instrument: api.investment_instrument, valuation_date: ..@end_date).order(valuation_date: :asc).last

      # We cannot proceed without a valid valuation
      raise "No valuation found for #{Investor.find(portfolio_company_id).investor_name} prior to date #{@end_date}" unless valuation

      # Get the fmv for this portfolio_company on the @end_date
      fmv_on_end_date_cents = net_quantity * valuation.per_share_value_in(@fund.currency, @end_date)
      # Applied only if there is a scenario
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
    cf = XirrCashflow.new

    @fund.capital_remittance_payments.includes(:capital_remittance).where(capital_remittance_payments: { payment_date: ..@end_date }).find_each do |cr|
      cf << XirrTransaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id} ")
    end

    @fund.capital_distribution_payments.includes(:investor).where(capital_distribution_payments: { payment_date: ..@end_date }).find_each do |cdp|
      # Include the gross payable, but this contains the reinvestment amount
      cf << XirrTransaction.new(cdp.gross_payable_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Gross Distribution #{cdp.id}")
      # Reduce by the reinvestment amount
      cf << XirrTransaction.new(-1 * cdp.reinvestment_with_fees_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Reinvestment from Distribution #{cdp.id}")
    end

    cf << XirrTransaction.new(fmv_on_date(scenarios:), date: @end_date, notes: "FMV") if fmv_on_date != 0
    cf << XirrTransaction.new(cash_in_hand_cents, date: @end_date, notes: "Cash in Hand") if cash_in_hand_cents != 0
    cf << XirrTransaction.new(net_current_assets_cents, date: @end_date, notes: "Net Current Assets") if net_current_assets_cents != 0

    cf << XirrTransaction.new(estimated_carry_cents * -1, date: @end_date, notes: "Estimated carry") if net_irr
    cf << XirrTransaction.new(adjustment_cash, date: @end_date, notes: "Adjustment Cash") if adjustment_cash != 0

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    cf.each do |cash_flow|
      Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}"
    end

    lxirr = XirrApi.new.xirr(cf, "xirr_#{@fund.id}_#{@end_date}") || 0
    Rails.logger.debug { "fund.xirr irr: #{lxirr}" }
    if return_cash_flows
      [(lxirr * 100).round(2), cf]
    else
      [(lxirr * 100).round(2), nil]
    end
  end

  def sample_xirr(count)
    cf = XirrCashflow.new
    (1..count).each do |_i|
      cf << XirrTransaction.new(-1 * rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)

      cf << XirrTransaction.new(rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)
    end

    Rails.logger.debug cf

    XirrApi.new.xirr(cf, "sample_xirr")
  end
end
