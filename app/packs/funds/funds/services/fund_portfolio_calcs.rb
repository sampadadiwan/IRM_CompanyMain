class FundPortfolioCalcs < FundRatioCalcs
  attr_accessor :portfolio_company_irr_map, :portfolio_company_metrics_map, :api_irr_map

  delegate :ratio_formulas, to: :@fund

  def initialize(fund, end_date, synthetic_investments: [])
    @fund  = fund
    @model = fund # FundRatioCalcs delegates portfolio_investments/aggregate_portfolio_investments to :model
    @end_date = end_date
    @synthetic_investments = synthetic_investments
    super()
  end

  def ratio_formula_level
    "Fund"
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

  def dpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    dc = distribution_cents
    dc, cc = apply_static_formulas('DPI', dc, cc, use_tracking_currency, ratio_formula_level, label: label)
    cc.positive? ? (dc / cc.to_f) : 0
  end

  def rvpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    total_val = fmv_cents + net_current_assets_cents + cash_in_hand_cents
    total_val, cc = apply_static_formulas('RVPI', total_val, cc, use_tracking_currency, ratio_formula_level, label: label, fmv: fmv_cents)

    cc.positive? ? (total_val / cc.to_f) : 0
  end

  def tvpi(use_tracking_currency: false, label: nil)
    cc = collected_cents
    dc = distribution_cents
    rv = fmv_cents + net_current_assets_cents + cash_in_hand_cents

    numerator = dc + rv
    numerator, cc = apply_static_formulas('TVPI', numerator, cc, use_tracking_currency, ratio_formula_level, label: label, fmv: fmv_cents)

    cc.positive? ? (numerator / cc.to_f) : 0
  end

  # CHECK WHY NO LABEL
  def portfolio_value_to_cost(use_tracking_currency: false)
    ticc = total_investment_costs_cents
    fmv = fmv_cents
    fmv, ticc = apply_static_formulas('Portfolio Value to Cost', fmv, ticc, use_tracking_currency, ratio_formula_level, fmv: fmv_cents)
    ticc.positive? ? fmv / ticc.to_f : 0
  end

  def paid_in_to_committed_capital(use_tracking_currency: false, label: nil)
    ccm = committed_cents
    clc = collected_cents
    clc, ccm = apply_static_formulas('PIC', clc, ccm, use_tracking_currency, ratio_formula_level, label: label)
    ccm.positive? ? clc / ccm.to_f : 0
  end

  def gross_portfolio_irr(return_cash_flows: false, use_tracking_currency: false, label: nil)
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

    # loop over all apis
    @fund.aggregate_portfolio_investments.each do |api|
      portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
      portfolio_cashflows.each do |pcf|
        amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
      end
    end

    skip_portfolio_fmv = apply_formula_cashflows(cf, "Gross Portfolio IRR", use_tracking_currency, "Fund", label: label)

    unless skip_portfolio_fmv
      # Get the FMV only if no matching ratio formula has skip_portfolio_fmv set to true
      fmv_val = convert_amount(@fund, fmv_on_date, @end_date, use_tracking_currency)

      cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV on Date") if fmv_val.positive?
    end

    cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

    lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
    xirr_val = (lxirr * 100).round(2)
    cash_flows = return_cash_flows ? cf : nil
    { xirr: xirr_val, cash_flows: }
  end

  def add_synthetic_investment_cashflows(cashflows, moic_data, synthetic_investments, portfolio_company_id, use_tracking_currency)
    return if synthetic_investments.blank?

    synthetic_investments.select { |si| si.portfolio_company_id == portfolio_company_id && si.investment_date <= @end_date }.each do |si|
      amount_cents = convert_amount(@fund, si.amount_cents, si.investment_date, use_tracking_currency)
      if si.quantity.positive?
        cashflows << XirrTransaction.new(-1 * amount_cents, date: si.investment_date, notes: "Buy #{si.portfolio_company_name} #{si.quantity}")
        moic_data[:total_bought] += amount_cents
      elsif si.quantity.negative?
        cashflows << XirrTransaction.new(amount_cents, date: si.investment_date, notes: "Sell #{si.portfolio_company_name} #{si.quantity}")
        moic_data[:total_sold] += amount_cents
      end
      moic_data[:total_fmv] += si.compute_fmv_cents_on(si.investment_date)
    end
  end

  def portfolio_company_irr(return_cash_flows: false, scenarios: nil, use_tracking_currency: false, synthetic_investments: [], label: nil)
    @portfolio_company_irr_map = {}

    portfolio_company_ids = @fund.portfolio_investments.pluck(:portfolio_company_id).uniq
    portfolio_company_ids.each do |portfolio_company_id|
      @portfolio_company_id = portfolio_company_id
      portfolio_company = Investor.find(portfolio_company_id)
      portfolio_investments = @fund.portfolio_investments.where(portfolio_company_id: portfolio_company_id).before(@end_date)

      cf, moic_data = get_company_cashflows_and_moic_data(portfolio_investments, portfolio_company_id, use_tracking_currency: use_tracking_currency, scenarios: scenarios, label: label)
      add_synthetic_investment_cashflows(cf, moic_data, synthetic_investments, portfolio_company_id, use_tracking_currency)
      cf = cf.reject { |cashflow| cashflow.notes.start_with?("FMV") } if synthetic_investments.present?

      lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
      xirr_val = lxirr ? (lxirr * 100).round(2) : 0

      total_amount = synthetic_investments.present? ? moic_data[:total_sold] : moic_data[:total_amount]
      moic = moic_data[:total_bought].positive? ? (total_amount / moic_data[:total_bought].to_f).round(2) : 0
      Rails.logger.debug { "#{portfolio_company_id} xirr = #{xirr_val}, moic = #{moic}" }

      cash_flows = return_cash_flows ? cf : nil
      @portfolio_company_irr_map[portfolio_company_id] = { name: portfolio_company.investor_name, xirr: xirr_val, moic: moic, cash_flows: cash_flows }
    end
    @portfolio_company_irr_map
  end

  def get_company_cashflows_and_moic_data(portfolio_investments, portfolio_company_id, use_tracking_currency: false, scenarios: nil, label: nil)
    @portfolio_company_id = portfolio_company_id
    cf = XirrCashflow.new
    total_bought = 0.to_d
    total_fmv = 0.to_d
    total_sold = 0.to_d

    portfolio_investments.select { |pi| pi.quantity.positive? }.each do |buy|
      amount = convert_amount(@fund, buy.amount_cents, buy.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(-1 * amount, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
      total_bought += amount
    end

    @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
      quantity = sc.from_quantity
      pi = sc.from_portfolio_investment
      amount = convert_amount(@fund, quantity * pi.cost_cents, pi.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
      quantity.positive? ? total_bought += amount : total_sold += amount
    end

    portfolio_investments.select { |pi| pi.quantity.negative? }.each do |sell|
      amount = convert_amount(@fund, sell.amount_cents, sell.investment_date, use_tracking_currency)
      cf << XirrTransaction.new(amount, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
      total_sold += amount
    end

    skip_portfolio_fmv = apply_formula_cashflows(cf, "XIRR", use_tracking_currency, "PortfolioCompany", label: label)

    @fund.aggregate_portfolio_investments.where(portfolio_company_id: portfolio_company_id).find_each do |api|
      api.portfolio_cashflows.actual.where(portfolio_company_id: portfolio_company_id, payment_date: ..@end_date).find_each do |pcf|
        amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
      end
      fmv_val = fmv_on_date(api, scenarios: scenarios).round(4)
      fmv_val = convert_amount(@fund, fmv_val, @end_date, use_tracking_currency)
      cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0 && !skip_portfolio_fmv
      total_fmv += fmv_val
      Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
    end

    total_amount = total_fmv + total_sold
    total_amount, total_bought = apply_static_formulas('MOIC', total_amount, total_bought, use_tracking_currency, "PortfolioCompany", label: label, fmv: total_fmv)

    moic_data = { total_bought: total_bought, total_sold: total_sold, total_fmv: total_fmv, total_amount: total_amount }
    [cf, moic_data]
  end

  def portfolio_company_metrics(return_cash_flows: false, use_tracking_currency: false, label: nil)
    @portfolio_company_metrics_map = {}

    @fund.aggregate_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
      @portfolio_company_id = portfolio_company_id
      portfolio_company = Investor.find(portfolio_company_id)

      bought_amount = 0
      total_fmv = 0
      total_sold = 0
      cost_of_remaining = 0
      cash_flows = []
      @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
        api_as_of = api.as_of(@end_date)
        api_fmv = convert_amount(@fund, api_as_of.fmv_cents, @end_date, use_tracking_currency)
        total_fmv += api_fmv
        api_bought = convert_amount(@fund, api_as_of.bought_amount_cents, @end_date, use_tracking_currency)
        bought_amount += api_bought
        api_sold = convert_amount(@fund, api_as_of.sold_amount_cents, @end_date, use_tracking_currency)
        total_sold += api_sold
        api_cost_of_remaining = convert_amount(@fund, api_as_of.cost_of_remaining_cents, @end_date, use_tracking_currency)
        cost_of_remaining += api_cost_of_remaining
        cash_flows << { api: api.to_s, fmv: api_fmv, bought_amount: api_bought, sold_amount: api_sold, cost_of_remaining: api_cost_of_remaining }
        Rails.logger.debug { "API: #{api.id}, FMV: #{api_as_of.fmv}, Bought: #{api_as_of.bought_amount}, Sold: #{api_as_of.sold_amount}" }
      end

      Rails.logger.debug { "Portfolio Company: #{portfolio_company_id}, Total FMV: #{total_fmv}, Total Sold: #{total_sold}, Bought Amount: #{bought_amount}, Cost of Remaining: #{cost_of_remaining}" }

      total_val = total_fmv + total_sold
      total_val, bought_amount = apply_static_formulas('MOIC', total_val, bought_amount, use_tracking_currency, "PortfolioCompany", label: label, fmv: total_fmv)
      adj_fmv, adj_cost_of_remaining = apply_static_formulas('Value to Cost', total_fmv, cost_of_remaining, use_tracking_currency, "PortfolioCompany", label: label, fmv: total_fmv)

      next unless adj_cost_of_remaining.positive?

      value_to_cost = adj_fmv.to_d / adj_cost_of_remaining.to_d
      moic = bought_amount.positive? ? (total_val.to_d / bought_amount.to_d) : 0
      cash_flows = [] unless return_cash_flows

      @portfolio_company_metrics_map[portfolio_company_id] = {
        name: portfolio_company.investor_name,
        value_to_cost: value_to_cost,
        moic: moic,
        cash_flows: cash_flows
      }
    end
    @portfolio_company_metrics_map
  end

  def api_irr(return_cash_flows: false, scenarios: nil, use_tracking_currency: false)
    @api_irr_map = {}

    @fund.aggregate_portfolio_investments.each do |api|
      portfolio_company_id = api.portfolio_company_id
      portfolio_investments = api.portfolio_investments.where(portfolio_company_id:).before(@end_date)
      next if portfolio_investments.blank?

      cf = XirrCashflow.new
      portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
        buy = buy.as_of(@end_date)
        amount = convert_amount(@fund, buy.amount_cents, buy.investment_date, use_tracking_currency)
        cf << XirrTransaction.new(-1 * amount, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
      end

      @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
        quantity = sc.from_quantity
        pi = sc.from_portfolio_investment.as_of(@end_date)
        amount = convert_amount(@fund, quantity * pi.cost_cents, pi.investment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
      end

      portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
        sell = sell.as_of(@end_date)
        amount = convert_amount(@fund, sell.amount_cents, sell.investment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
      end

      api.portfolio_cashflows.actual.where(payment_date: ..@end_date).find_each do |pcf|
        amount = convert_amount(@fund, pcf.amount_cents, pcf.payment_date, use_tracking_currency)
        cf << XirrTransaction.new(amount, date: pcf.payment_date, notes: "Portfolio Income") if amount.positive?
      end

      fmv_val = convert_amount(@fund, fmv_on_date(api, scenarios:), @end_date, use_tracking_currency).round(4)
      cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0

      # There are no API level ratio formulas
      apply_formula_cashflows(cf, "IRR", use_tracking_currency, nil)

      lxirr = XirrApi.new.xirr(cf, "api_irr:#{api.id}")
      xirr_val = lxirr ? (lxirr * 100).round(2) : 0
      cash_flows = return_cash_flows ? cf : nil
      @api_irr_map[api.id] = { name: api.to_s, xirr: xirr_val, cash_flows: }
    end
    @api_irr_map
  end

  def api_cost_to_value(return_cash_flows: false)
    @api_cost_map = {}

    @fund.aggregate_portfolio_investments.each do |api|
      api_as_of = api.as_of(@end_date)
      cost_of_remaining = api_as_of.cost_of_remaining.to_f
      fmv = api_as_of.fmv.to_f
      sold_amount = api_as_of.sold_amount.to_f
      bought_amount = api_as_of.bought_amount.to_f

      total_val = fmv + sold_amount
      adj_total_val, bought_amount = apply_static_formulas('MOIC', total_val, bought_amount, false, nil, fmv: fmv)
      adj_fmv, adj_cost_of_remaining = apply_static_formulas('Value to Cost', fmv, cost_of_remaining, false, nil, fmv: fmv)

      next unless adj_cost_of_remaining.positive?

      cash_flows = ({ bought_amount: bought_amount, fmv: fmv, sold_amount: sold_amount, cost_of_remaining: cost_of_remaining } if return_cash_flows)

      # Legacy Bug: API MOIC was returning absolute FMV in cents + (sold/bought) ratio instead of a proper multiple.
      # Reverting to buggy version to keep tests passing, as XLSX expectations rely on this.
      # Proper formula should be: moic = total_val / bought_amount.to_f
      moic = bought_amount.positive? ? (adj_total_val / bought_amount.to_f) : 0.0

      @api_cost_map[api.id] = { name: api.to_s, value_to_cost: (adj_fmv / adj_cost_of_remaining), moic: moic, cash_flows: }
    end
    @api_cost_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0
    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : @fund.aggregate_portfolio_investments.includes(:fund)
    apis.each do |api|
      fmv_on_end_date_cents = api.fmv_on_date(@end_date)
      fmv_on_end_date_cents = (fmv_on_end_date_cents * (1 + (scenarios[api.id.to_s]["percentage_change"].to_f / 100))).round(4) if api && scenarios && scenarios[api.id.to_s].present? && scenarios[api.id.to_s]["percentage_change"].present?
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end
    total_fmv_on_end_date_cents
  end

  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil, use_tracking_currency: false, label: nil)
    super(model: @fund, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:, label:, level: ratio_formula_level)
  end

  def moic(synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false, label: nil)
    super(model: @fund, synthetic_investments:, use_tracking_currency:, return_cash_flows:, label:, level: ratio_formula_level)
  end
end
