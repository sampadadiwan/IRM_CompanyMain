class FundRatioMultiFundCalcs < FundRatioCalcs
  def initialize(scenario, end_date, entity, funds: nil, portfolio_companies: nil, portfolio_companies_tags: nil, currency: nil) # rubocop:disable Metrics/ParameterLists
    @scenario = scenario
    # All funds must be in the same entity
    @funds = funds
    @fund_ids = @funds.pluck(:id) if funds
    # The end date is the date of the scenario, all calculations are done as of this date
    @end_date = end_date
    # The entity for which we are calculating the ratios
    @entity = entity
    # The portfolio companies for which we are calculating the ratios
    @portfolio_companies = portfolio_companies
    # Sometimes we are passed only the tags, and not the portfolio companies
    @portfolio_companies = entity.investors.portfolio_companies.with_any_tags(portfolio_companies_tags) if portfolio_companies_tags.present?

    @portfolio_company_ids = @portfolio_companies.present? ? @portfolio_companies.pluck(:id) : []

    # The currency for which we are calculating the ratios
    @currency = currency || @entity.currency
    # Setup the exchange rate bank, to convert across currencies
    @bank = ExchangeRate.setup_variable_exchange(@end_date, @entity.id)
    super()
  end

  def convert_to_base_currency(amount)
    @bank.exchange_with(amount, @currency)
  end

  # Returns all the Aggregate portfolio investments for the funds
  def aggregate_portfolio_investments
    apis = @entity.aggregate_portfolio_investments
    apis = apis.where(fund_id: @fund_ids) if @funds
    apis = apis.where(portfolio_company_id: @portfolio_company_ids) if @portfolio_companies
    apis
  end

  def all_portfolio_investments
    pis = @entity.portfolio_investments
    pis = pis.where(fund_id: @fund_ids) if @funds
    pis = pis.where(portfolio_company_id: @portfolio_company_ids) if @portfolio_companies
    pis
  end

  def stock_conversions
    sc = @entity.stock_conversions
    sc = sc.where(fund_id: @fund_ids) if @funds
    sc = sc.includes(:from_portfolio_investment).where(from_portfolio_investment: { portfolio_company_id: @portfolio_company_ids }) if @portfolio_companies
    sc
  end

  def capital_remittance_payments
    @entity.capital_remittance_payments.where(fund_id: @fund_ids)
  end

  def capital_distribution_payments
    @entity.capital_distribution_payments.where(fund_id: @fund_ids)
  end

  def total_investment_costs_cents
    ticc = Money.new(0, @currency)
    aggregate_portfolio_investments.each do |api|
      api_as_of = api.as_of(@end_date)
      ticc += convert_to_base_currency(api_as_of.cost_of_remaining)
    end
    ticc.cents
  end

  def sum_account_entries(account_entry_name)
    total = Money.new(0, @currency)

    @funds.each do |fund|
      ae = fund.fund_account_entries.where(name: account_entry_name, reporting_date: ..@end_date).order(reporting_date: :asc).last
      total += convert_to_base_currency(ae.amount) if ae
    end

    total
  end

  def cash_in_hand_cents
    @cash_in_hand ||= sum_account_entries("Cash In Hand")
    @cash_in_hand.cents
  end

  def net_current_assets_cents
    @net_current_assets ||= sum_account_entries("Net Current Assets")
    @net_current_assets.cents
  end

  def estimated_carry_cents
    @estimated_carry ||= sum_account_entries("Estimated Carry")
    @estimated_carry.cents
  end

  def fmv_cents
    @fmv_cents ||= fmv_on_date
  end

  def portfolio_value_to_cost
    total_investment_costs_cents.positive? ? fmv_cents / total_investment_costs_cents : 0
  end

  def gross_portfolio_irr
    cf = XirrCashflow.new

    # Get the buy cash flows
    buy_pis = all_portfolio_investments.buys.before(@end_date)
    buy_pis.find_each do |buy|
      bought_amount_cents_bc = convert_to_base_currency(buy.amount).cents
      cf << XirrTransaction.new(-1 * bought_amount_cents_bc, date: buy.investment_date, notes: "Bought Amount") if buy.amount_cents.positive?
    end

    # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
    Rails.logger.debug "#########StockConversion#########"
    binding.pry
    stock_conversions.where(conversion_date: ..@end_date).find_each do |sc|
      quantity = sc.from_quantity
      pi = sc.from_portfolio_investment
      cost_cents_bc = convert_to_base_currency(pi.cost).cents
      cf << XirrTransaction.new(quantity * cost_cents_bc, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
    end

    # Get the sell cash flows
    all_portfolio_investments.sells.where(investment_date: ..@end_date).find_each do |sell|
      sold_amount_cents_bc = convert_to_base_currency(sell.amount).cents
      cf << XirrTransaction.new(sold_amount_cents_bc, date: sell.investment_date, notes: "Sold Amount") if sell.amount_cents.positive?
    end

    # Get the FMV
    cf << XirrTransaction.new(fmv_on_date, date: @end_date, notes: "FMV on Date") if fmv_on_date.positive?

    # loop over all apis
    aggregate_portfolio_investments.each do |api|
      portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
      portfolio_cashflows.each do |pcf|
        pcf_amount_cents_bc = convert_to_base_currency(pcf.amount).cents
        cf << XirrTransaction.new(pcf_amount_cents_bc, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
      end
    end

    cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

    lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
    # lxirr ? (lxirr * 100).round(2) : 0
    (lxirr * 100).round(2)
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil)
    @portfolio_company_irr_map ||= {}

    if @portfolio_company_irr_map.empty?
      # Get all the Portfolio companies
      all_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id| # rubocop:disable Metrics/BlockLength
        portfolio_company = Investor.find(portfolio_company_id)
        # Get all the portfolio investments for this portfolio company before the end date
        portfolio_investments = all_portfolio_investments.where(portfolio_company_id:).before(@end_date)

        cf = XirrCashflow.new

        # Get the buy cash flows
        Rails.logger.debug "#########BUYS#########"
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          buyt_amount_cents_bc = convert_to_base_currency(buy.amount).cents
          cf << XirrTransaction.new(-1 * buyt_amount_cents_bc, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        Rails.logger.debug "#########StockConversion#########"
        stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          pi_cost_cents_bc = convert_to_base_currency(pi.cost).cents
          cf << XirrTransaction.new(quantity * pi_cost_cents_bc, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        Rails.logger.debug "#########SELLS#########"
        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          sellt_amount_cents_bc = convert_to_base_currency(sell.amount).cents
          cf << XirrTransaction.new(sellt_amount_cents_bc, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        Rails.logger.debug "#########FMV & Portfolio CF#########"

        # Get the FMV for this specific portfolio_company
        aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
          # Get the portfolio income cash flows
          portfolio_cashflows = api.portfolio_cashflows.actual.where(portfolio_company_id:, payment_date: ..@end_date)
          portfolio_cashflows.each do |pcf|
            pcf_amount_cents_bc = convert_to_base_currency(pcf.amount).cents
            cf << XirrTransaction.new(pcf_amount_cents_bc, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
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

  def portfolio_company_metrics
    @portfolio_company_metrics_map ||= {}

    aggregate_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
      portfolio_company = Investor.find(portfolio_company_id)

      bought_amount = 0
      total_fmv = 0
      total_sold = 0
      cost_of_remaining = 0

      aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
        api_as_of = api.as_of(@end_date)
        total_fmv += convert_to_base_currency(api_as_of.fmv)
        bought_amount += convert_to_base_currency(api_as_of.bought_amount)
        total_sold += convert_to_base_currency(api_as_of.sold_amount)
        cost_of_remaining += convert_to_base_currency(api_as_of.cost_of_remaining)

        Rails.logger.debug { "API: #{api.id}, FMV: #{api_as_of.fmv}, Bought: #{api_as_of.bought_amount}, Sold: #{api_as_of.sold_amount}" }
      end

      Rails.logger.debug { "Portfolio Company: #{portfolio_company_id}, Total FMV: #{total_fmv}, Total Sold: #{total_sold}, Bought Amount: #{bought_amount}, Cost of Remaining: #{cost_of_remaining}" }

      next unless bought_amount.positive? && cost_of_remaining.positive?

      value_to_cost = total_fmv / cost_of_remaining.to_f
      moic = (total_fmv + total_sold) / bought_amount.to_f

      @portfolio_company_metrics_map[portfolio_company_id] = {
        name: portfolio_company.investor_name,
        value_to_cost: value_to_cost,
        moic: moic
      }
    end

    @portfolio_company_metrics_map
  end

  # Compute the XIRR for each API
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  def api_irr(return_cash_flows: false, scenarios: nil)
    @api_irr_map ||= {}

    if @api_irr_map.empty?

      aggregate_portfolio_investments.each do |api|
        portfolio_company_id = api.portfolio_company_id

        portfolio_investments = api.portfolio_investments.where(portfolio_company_id:).before(@end_date)
        # If there are no portfolio investments for this API, then skip
        next if portfolio_investments.blank?

        cf = XirrCashflow.new

        # Get the buy cash flows
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          buyt_amount_cents_bc = convert_to_base_currency(buy.amount).cents
          cf << XirrTransaction.new(-1 * buyt_amount_cents_bc, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          pi_cost_cents_bc = convert_to_base_currency(pi.cost).cents
          cf << XirrTransaction.new(quantity * pi_cost_cents_bc, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          sell_amount_cents_bc = convert_to_base_currency(sell.amount).cents
          cf << XirrTransaction.new(sell_amount_cents_bc, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        # Get the portfolio income cash flows
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          pcf_amount_cents_bc = convert_to_base_currency(pcf.amount).cents
          cf << XirrTransaction.new(pcf_amount_cents_bc, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
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
  # rubocop:enable Metrics/BlockLength
  # rubocop:enable Metrics/MethodLength

  def api_cost_to_value
    @api_cost_map ||= {}

    aggregate_portfolio_investments.each do |api|
      api.portfolio_investments.where(investment_date: ..@end_date)

      api_as_of = api.as_of(@end_date)
      convert_to_base_currency(api_as_of.bought_amount)
      cost_of_remaining = convert_to_base_currency(api_as_of.cost_of_remaining)
      fmv = api_as_of.fmv

      @api_cost_map[api.id] = { name: api.to_s, value_to_cost: (fmv / cost_of_remaining) } if cost_of_remaining.positive?
    end

    @api_cost_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0

    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : aggregate_portfolio_investments

    Rails.logger.debug apis

    apis.each do |api|
      fmv_on_end_date_cents = convert_to_base_currency(Money.new(api.fmv_on_date(@end_date), api.fund.currency))

      # Applied only if there is a scenario
      fmv_on_end_date_cents = (fmv_on_end_date_cents * (1 + (scenarios[api.id.to_s]["percentage_change"].to_f / 100))).round(4) if api && scenarios && scenarios[api.id.to_s]["percentage_change"].present?

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
    super(model: @entity, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:)
  end
end
