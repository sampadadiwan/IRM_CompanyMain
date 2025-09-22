class FundPortfolioCalcs < FundRatioCalcs
  attr_accessor :portfolio_company_irr_map, :portfolio_company_metrics_map, :api_irr_map

  def initialize(fund, end_date, synthetic_investments: [])
    @fund = fund
    @end_date = end_date
    @synthetic_investments = synthetic_investments
    super()
  end

  def total_investment_costs_cents
    ticc = 0
    @fund.aggregate_portfolio_investments.each do |api|
      api_as_of = api.as_of(@end_date)
      ticc += api_as_of.cost_of_remaining_cents
    end
    ticc
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

  def portfolio_value_to_cost
    total_investment_costs_cents.positive? ? fmv_cents / total_investment_costs_cents : 0
  end

  # TODO
  def paid_in_to_committed_capital
    committed_cents.positive? ? collected_cents / committed_cents : 0
  end

  def gross_portfolio_irr(return_cash_flows: false, use_tracking_currency: false)
    cf = XirrCashflow.new

    # Get the buy cash flows
    buy_pis = @fund.portfolio_investments.buys.before(@end_date)
    buy_pis.find_each do |buy|
      amount = convert_amount(@fund, buy.amount_cents, buy.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(-1 * amount, date: buy.investment_date, notes: "Bought Amount") if amount.positive?
    end

    # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
    Rails.logger.debug "#########StockConversion#########"
    @fund.stock_conversions.where(conversion_date: ..@end_date).find_each do |sc|
      quantity = sc.from_quantity
      pi = sc.from_portfolio_investment
      amount = convert_amount(@fund, quantity * pi.cost_cents, pi.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
    end

    # Get the sell cash flows
    @fund.portfolio_investments.sells.where(investment_date: ..@end_date).find_each do |sell|
      amount = convert_amount(@fund, sell.amount_cents, sell.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: sell.investment_date, notes: "Sold Amount") if amount.positive?
    end

    # Get the FMV
    fmv_val = convert_amount(@fund, fmv_on_date, @end_date, use_tracking_currency)

    cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV on Date") if fmv_val.positive?

    # loop over all apis
    @fund.aggregate_portfolio_investments.each do |api|
      portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
      portfolio_cashflows.each do |pcf|
        amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
      end
    end

    cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

    lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
    xirr_val = (lxirr * 100).round(2)
    cash_flows = return_cash_flows ? cf : nil
    { xirr: xirr_val, cash_flows: }
  end

  # Adds synthetic investment cashflows to the cashflow array and updates MOIC data.
  #
  # This method processes synthetic investments for a given portfolio company, converting amounts to tracking currency if needed.
  # For each synthetic investment:
  #   - If quantity is positive, it's treated as a buy and added as a negative cashflow.
  #   - If quantity is negative, it's treated as a sell and added as a positive cashflow.
  #   - FMV for the investment date is added to total_fmv for MOIC calculation.
  #
  # Params:
  # cashflows:: XirrCashflow array to append transactions to
  # moic_data:: Hash tracking total_bought, total_sold, total_fmv
  # synthetic_investments:: Array of synthetic investment objects
  # portfolio_company_id:: Integer, portfolio company identifier
  # use_tracking_currency:: Boolean, whether to convert amounts to tracking currency
  def add_synthetic_investment_cashflows(cashflows, moic_data, synthetic_investments, portfolio_company_id, use_tracking_currency)
    return if synthetic_investments.blank?

    synthetic_investments.select { |si| si.portfolio_company_id == portfolio_company_id && si.investment_date <= @end_date }.each do |si|
      amount_cents = convert_amount(@fund, si.amount_cents, si.investment_date, use_tracking_currency)
      if si.quantity.positive?
        # Treat as buy: negative cashflow
        cashflows << XirrTransaction.new(-1 * amount_cents, date: si.investment_date, notes: "Buy #{si.portfolio_company_name} #{si.quantity}")
        moic_data[:total_bought] += amount_cents
      elsif si.quantity.negative?
        # Treat as sell: positive cashflow
        cashflows << XirrTransaction.new(amount_cents, date: si.investment_date, notes: "Sell #{si.portfolio_company_name} #{si.quantity}")
        moic_data[:total_sold] += amount_cents
      end
      # Add FMV for MOIC calculation
      moic_data[:total_fmv] += si.compute_fmv_cents_on(si.investment_date)
    end
  end

  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil, use_tracking_currency: false, synthetic_investments: [])
    @portfolio_company_irr_map ||= {}
    return @portfolio_company_irr_map unless @portfolio_company_irr_map.empty?

    portfolio_company_ids = @fund.portfolio_investments.pluck(:portfolio_company_id).uniq
    portfolio_company_ids.each do |portfolio_company_id|
      # Fetch the portfolio company
      portfolio_company = Investor.find(portfolio_company_id)
      # Fetch the portfolio investments for this company up to the end date
      portfolio_investments = @fund.portfolio_investments.where(portfolio_company_id: portfolio_company_id).before(@end_date)

      # Get the cash flows and MOIC data (bought, sold and fmv)
      cf, moic_data = get_company_cashflows_and_moic_data(portfolio_investments, portfolio_company_id, use_tracking_currency: use_tracking_currency, scenarios: scenarios)
      # Add synthetic investment cashflows
      add_synthetic_investment_cashflows(cf, moic_data, synthetic_investments, portfolio_company_id, use_tracking_currency)
      # we do not take fmv into consideration in case of portfolio scenario computations using synthetic investments
      cf = cf.reject { |cashflow| cashflow.notes.start_with?("FMV") } if synthetic_investments.present?

      # Get and store the XIRR
      lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
      xirr_val = lxirr ? (lxirr * 100).round(2) : 0

      # Calculate and store the MOIC
      # Don't use fmv here if we have synthetic investments
      total_amount = synthetic_investments.present? ? moic_data[:total_sold] : (moic_data[:total_fmv] + moic_data[:total_sold])
      moic = moic_data[:total_bought].positive? ? (total_amount / moic_data[:total_bought].to_f).round(2) : 0
      Rails.logger.debug { "#{portfolio_company_id} xirr = #{xirr_val}, moic = #{moic}" }

      cash_flows = return_cash_flows ? cf : nil
      @portfolio_company_irr_map[portfolio_company_id] = { name: portfolio_company.investor_name, xirr: xirr_val, moic: moic, cash_flows: cash_flows }
    end
    @portfolio_company_irr_map
  end

  def get_company_cashflows_and_moic_data(portfolio_investments, portfolio_company_id, use_tracking_currency: false, scenarios: nil)
    cf = XirrCashflow.new
    total_bought = 0.to_d
    total_fmv = 0.to_d
    total_sold = 0.to_d

    # Buy cash flows
    portfolio_investments.select { |pi| pi.quantity.positive? }.each do |buy|
      amount = convert_amount(@fund, buy.amount_cents, buy.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(-1 * amount, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
      total_bought += amount
    end

    # Stock conversions
    @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
      quantity = sc.from_quantity
      pi = sc.from_portfolio_investment
      amount = convert_amount(@fund, quantity * pi.cost_cents, pi.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
      quantity.positive? ? total_bought += amount : total_sold += amount
    end

    # Sell cash flows
    portfolio_investments.select { |pi| pi.quantity.negative? }.each do |sell|
      amount = convert_amount(@fund, sell.amount_cents, sell.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
      total_sold += amount
    end

    # FMV and portfolio income cash flows
    @fund.aggregate_portfolio_investments.where(portfolio_company_id: portfolio_company_id).find_each do |api|
      api.portfolio_cashflows.actual.where(portfolio_company_id: portfolio_company_id, payment_date: ..@end_date).find_each do |pcf|
        amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
      end
      fmv_val = fmv_on_date(api, scenarios: scenarios).round(4)
      fmv_val = convert_amount(@fund, fmv_val, @end_date, use_tracking_currency)
      cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0
      # Add to total fmv for moic
      total_fmv += fmv_val
      Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
    end
    moic_data = { total_bought: total_bought, total_sold: total_sold, total_fmv: total_fmv }
    [cf, moic_data]
  end

  def portfolio_company_metrics(return_cash_flows: false, use_tracking_currency: false)
    @portfolio_company_metrics_map ||= {}

    @fund.aggregate_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
      portfolio_company = Investor.find(portfolio_company_id)

      bought_amount = 0
      total_fmv = 0
      total_sold = 0
      cost_of_remaining = 0

      @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
        api_as_of = api.as_of(@end_date)

        total_fmv += convert_amount(@fund, api_as_of.fmv_cents, @end_date, use_tracking_currency)
        bought_amount += convert_amount(@fund, api_as_of.bought_amount_cents, @end_date, use_tracking_currency)
        total_sold += convert_amount(@fund, api_as_of.sold_amount_cents, @end_date, use_tracking_currency)
        cost_of_remaining += convert_amount(@fund, api_as_of.cost_of_remaining_cents, @end_date, use_tracking_currency)

        Rails.logger.debug { "API: #{api.id}, FMV: #{api_as_of.fmv}, Bought: #{api_as_of.bought_amount}, Sold: #{api_as_of.sold_amount}" }
      end

      Rails.logger.debug { "Portfolio Company: #{portfolio_company_id}, Total FMV: #{total_fmv}, Total Sold: #{total_sold}, Bought Amount: #{bought_amount}, Cost of Remaining: #{cost_of_remaining}" }

      next unless cost_of_remaining.positive?

      value_to_cost = total_fmv / cost_of_remaining.to_f
      moic = (total_fmv + total_sold) / bought_amount.to_f

      cash_flows = if return_cash_flows
                     {
                       bought_amount: bought_amount,
                       total_fmv: total_fmv,
                       total_sold: total_sold,
                       cost_of_remaining: cost_of_remaining
                     }
                   end

      @portfolio_company_metrics_map[portfolio_company_id] = {
        name: portfolio_company.investor_name,
        value_to_cost: value_to_cost,
        moic: moic,
        cash_flows: cash_flows
      }
    end

    @portfolio_company_metrics_map
  end

  # Compute the XIRR for each API
  def api_irr(return_cash_flows: false, scenarios: nil, use_tracking_currency: false)
    @api_irr_map ||= {}

    if @api_irr_map.empty?
      @fund.aggregate_portfolio_investments.each do |api|
        portfolio_company_id = api.portfolio_company_id

        portfolio_investments = api.portfolio_investments.where(portfolio_company_id:).before(@end_date)
        # If there are no portfolio investments for this API, then skip
        next if portfolio_investments.blank?

        cf = XirrCashflow.new

        # Get the buy cash flows
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          buy = buy.as_of(@end_date)
          amount = convert_amount(@fund, buy.amount_cents, buy.investment_date, use_tracking_currency)
          cf << XirrTransaction.new(-1 * amount, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end
        # TODO: check with aseem if we need to use AS_OF here

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          pi = pi.as_of(@end_date)
          amount = convert_amount(@fund, quantity * pi.cost_cents, pi.investment_date, use_tracking_currency)
          cf << XirrTransaction.new(amount, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          sell = sell.as_of(@end_date)
          amount = convert_amount(@fund, sell.amount_cents, sell.investment_date, use_tracking_currency)
          cf << XirrTransaction.new(amount, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        # Get the portfolio income cash flows
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
          cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
        end

        # Get the FMV for this specific portfolio_company
        fmv_val = convert_amount(@fund, fmv_on_date(api, scenarios:), @end_date, use_tracking_currency).round(4)
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

  def api_cost_to_value(return_cash_flows: false)
    @api_cost_map ||= {}

    @fund.aggregate_portfolio_investments.each do |api|
      api.portfolio_investments.where(investment_date: ..@end_date)

      api_as_of = api.as_of(@end_date)

      cost_of_remaining = api_as_of.cost_of_remaining.to_f
      fmv = api_as_of.fmv.to_f
      sold_amount = api_as_of.sold_amount.to_f
      bought_amount = api_as_of.bought_amount.to_f

      cash_flows = if return_cash_flows
                     {
                       bought_amount: bought_amount,
                       fmv: fmv,
                       sold_amount: sold_amount,
                       cost_of_remaining: cost_of_remaining
                     }
                   end

      @api_cost_map[api.id] = { name: api.to_s, value_to_cost: (fmv / cost_of_remaining), moic: (fmv + (sold_amount / bought_amount)), cash_flows: } if cost_of_remaining.positive?
    end

    @api_cost_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0

    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : @fund.aggregate_portfolio_investments

    Rails.logger.debug apis

    apis.each do |api|
      fmv_on_end_date_cents = api.fmv_on_date(@end_date)

      # Applied only if there is a scenario
      fmv_on_end_date_cents = (fmv_on_end_date_cents * (1 + (scenarios[api.id.to_s]["percentage_change"].to_f / 100))).round(4) if api && scenarios && scenarios[api.id.to_s].present? && scenarios[api.id.to_s]["percentage_change"].present?

      Rails.logger.debug { "FMV on End Date: #{fmv_on_end_date_cents}, API: #{api.id}" }
      # Aggregate the fmv across the fun
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end

    total_fmv_on_end_date_cents
  end

  # Calculate the IRR for the fund
  # net_irr: true/false - if true, then the IRR is calculated net of Estimated Carry
  # return_cash_flows: true/false - if true, then the cash flows used in computation are returned
  # adjustment_cash: amount to be added to the cash flows, used specifically for scenarios. see PortfolioScenarioJob
  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil, use_tracking_currency: false)
    super(model: @fund, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:)
  end

  def moic(synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false)
    super(model: @fund, synthetic_investments:, use_tracking_currency:, return_cash_flows:)
  end
end
