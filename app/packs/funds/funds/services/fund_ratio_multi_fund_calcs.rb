class FundRatioMultiFundCalcs < FundRatioCalcs
  # See docs/features/fund_ratio_run.md for full parameter documentation.
  #
  # portfolio_companies, portfolio_companies_tags, and portfolio_companies_sectors are
  # all optional. All three filter types are unioned: each contributes independently
  # to the pool of companies. Explicit IDs are always included; tags and sectors each
  # add any companies they match. The result is resolved here so the rest of the class
  # works with a single @portfolio_companies relation regardless of how companies
  # were selected.
  def initialize(scenario, end_date, entity, funds: nil, portfolio_companies: nil, portfolio_companies_tags: nil, portfolio_companies_sectors: nil, currency: nil)
    @scenario = scenario
    # All funds must belong to the same entity.
    @funds    = funds
    @fund_ids = @funds.pluck(:id) if funds
    # All calculations are snapshotted at this date.
    @end_date = end_date
    @entity   = entity

    pc_ids = Set.new
    # 1. Explicitly selected company IDs are always additive.
    pc_ids.merge(portfolio_companies.pluck(:id)) if portfolio_companies.present?
    # 2. Tags contribute independently — all companies matching any tag are unioned in.
    pc_ids.merge(entity.investors.portfolio_companies.with_any_tags(portfolio_companies_tags).pluck(:id)) if portfolio_companies_tags.present?
    # 3. Sectors contribute independently — all companies in any sector are unioned in.
    pc_ids.merge(entity.investors.portfolio_companies.in_sector(portfolio_companies_sectors).pluck(:id)) if portfolio_companies_sectors.present?

    # If no filter produced any IDs, fall back to the raw relation (may be nil,
    # meaning "no portfolio-company filter — use all companies").
    @portfolio_companies   = pc_ids.any? ? entity.investors.where(id: pc_ids.to_a) : portfolio_companies
    @portfolio_company_ids = @portfolio_companies.present? ? @portfolio_companies.pluck(:id) : []

    @currency = currency || @entity.currency
    # Variable exchange-rate bank: rates are looked up as of @end_date so historical
    # runs use the correct FX rates, not today's.
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

  def collected_cents
    total = Money.new(0, @currency)
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      total += convert_to_base_currency(Money.new(fpc.collected_cents, fund.currency))
    end
    total.cents
  end

  def distribution_cents
    total = Money.new(0, @currency)
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      total += convert_to_base_currency(Money.new(fpc.distribution_cents, fund.currency))
    end
    total.cents
  end

  def committed_cents
    total = Money.new(0, @currency)
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      total += convert_to_base_currency(Money.new(fpc.committed_cents, fund.currency))
    end
    total.cents
  end

  def dpi
    collected_cents
    dc = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_cc = fpc.collected_cents
      fund_dc = fpc.distribution_cents
      # Apply this fund's DPI rules to its own components before aggregation
      fund_dc, = fpc.apply_static_formulas('DPI', fund_dc, fund_cc, false)
      dc += convert_to_base_currency(Money.new(fund_dc, fund.currency)).cents
    end
    # The aggregated CC used as denominator is already converted, but we use the total adjusted CC for consistency?
    # Actually, if we want to reflect the formulas accurately, we should aggregate the ADJUSTED numerators and denominators.
    # Recalculating aggregated adjusted denominator:
    adj_cc = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_cc = fpc.collected_cents
      fund_dc = fpc.distribution_cents
      _, fund_cc = fpc.apply_static_formulas('DPI', fund_dc, fund_cc, false)
      adj_cc += convert_to_base_currency(Money.new(fund_cc, fund.currency)).cents
    end

    adj_cc.positive? ? (dc / adj_cc.to_f) : 0
  end

  def rvpi
    numerator = 0
    denominator = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_cc = fpc.collected_cents
      fund_rv = fpc.fmv_cents + fpc.net_current_assets_cents + fpc.cash_in_hand_cents

      fund_rv, fund_cc = fpc.apply_static_formulas('RVPI', fund_rv, fund_cc, false)

      numerator += convert_to_base_currency(Money.new(fund_rv, fund.currency)).cents
      denominator += convert_to_base_currency(Money.new(fund_cc, fund.currency)).cents
    end
    denominator.positive? ? (numerator / denominator.to_f) : 0
  end

  def tvpi
    numerator = 0
    denominator = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_cc = fpc.collected_cents
      fund_dc = fpc.distribution_cents
      fund_rv = fpc.fmv_cents + fpc.net_current_assets_cents + fpc.cash_in_hand_cents

      fund_tv = fund_dc + fund_rv
      fund_tv, fund_cc = fpc.apply_static_formulas('TVPI', fund_tv, fund_cc, false)

      numerator += convert_to_base_currency(Money.new(fund_tv, fund.currency)).cents
      denominator += convert_to_base_currency(Money.new(fund_cc, fund.currency)).cents
    end
    denominator.positive? ? (numerator / denominator.to_f) : 0
  end

  # FMV / total cost basis across all source funds, mirroring FundPortfolioCalcs#portfolio_value_to_cost.
  def portfolio_value_to_cost
    return 0 if @funds.blank?

    numerator = 0
    denominator = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_fmv  = fpc.fmv_cents
      fund_ticc = fpc.total_investment_costs_cents

      fund_fmv, fund_ticc = fpc.apply_static_formulas('Portfolio Value to Cost', fund_fmv, fund_ticc, false)

      numerator   += convert_to_base_currency(Money.new(fund_fmv,  fund.currency)).cents
      denominator += convert_to_base_currency(Money.new(fund_ticc, fund.currency)).cents
    end
    denominator.positive? ? (numerator / denominator.to_f) : 0
  end

  def paid_in_to_committed_capital
    numerator = 0
    denominator = 0
    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      fund_clc = fpc.collected_cents
      fund_ccm = fpc.committed_cents

      fund_clc, fund_ccm = fpc.apply_static_formulas('PIC', fund_clc, fund_ccm, false)

      numerator += convert_to_base_currency(Money.new(fund_clc, fund.currency)).cents
      denominator += convert_to_base_currency(Money.new(fund_ccm, fund.currency)).cents
    end
    denominator.positive? ? (numerator / denominator.to_f) : 0
  end

  def moic(synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false)
    # MOIC = (FMV + Total Sold) / Total Bought
    # For multifund, we aggregate converted adjusted components
    total_numerator = 0
    total_denominator = 0

    @funds.each do |fund|
      fpc = FundPortfolioCalcs.new(fund, @end_date)
      num, den, = fpc.moic_components(synthetic_investments: synthetic_investments, use_tracking_currency: false, return_cash_flows: false)

      total_numerator += convert_to_base_currency(Money.new(num, fund.currency)).cents
      total_denominator += convert_to_base_currency(Money.new(den, fund.currency)).cents
    end

    return 0, nil if total_denominator.zero?

    [(total_numerator / total_denominator.to_f).round(2), nil]
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

  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil)
    Rails.logger.debug { "Portfolio Company IRR for #{@portfolio_company_ids}" }
    @portfolio_company_irr_map ||= {}

    if @portfolio_company_irr_map.empty?
      # Get all the Portfolio companies
      all_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
        @portfolio_company_id = portfolio_company_id
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

  def portfolio_company_metrics
    Rails.logger.debug { "Portfolio Company IRR for #{@portfolio_company_ids}" }
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

      value_to_cost = total_fmv.to_d / cost_of_remaining.to_d
      moic = (total_fmv + total_sold).to_d / bought_amount.to_d

      @portfolio_company_metrics_map[portfolio_company_id] = {
        name: portfolio_company.investor_name,
        value_to_cost: value_to_cost,
        moic: moic
      }
    end

    @portfolio_company_metrics_map
  end

  # Compute the XIRR for each API

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
      fmv_on_end_date_cents = convert_to_base_currency(Money.new(api.fmv_on_date(@end_date), api.fund.currency)).cents

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
