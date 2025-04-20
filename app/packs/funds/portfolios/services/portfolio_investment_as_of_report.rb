class PortfolioInvestmentAsOfReport
  include FormTypeHelper

  def initialize(aggregate_portfolio_investments, current_user, as_of: nil, currency: nil)
    @aggregate_portfolio_investments = aggregate_portfolio_investments
    @current_user = current_user
    @as_of = as_of
    @currency = currency

    raise "No currency provided" unless @currency

    setup_exchange_rates
  end

  # Entry point: builds the Excel package with all tabs
  def generate
    package = Axlsx::Package.new
    workbook = package.workbook

    add_pis_tab(workbook)
    add_apis_tab(workbook)
    add_portfolio_companies_tab(workbook)

    package
  end

  def save_to_file(path)
    generate.serialize(path)
  end

  delegate :to_stream, to: :generate

  private

  def setup_exchange_rates
    @bank = ExchangeRate.setup_variable_exchange(@as_of, @current_user.entity_id)
  end

  def add_apis_tab(workbook)
    form_type, custom_fields, custom_headers, custom_calcs, custom_calc_headers = get_form_type("AggregatePortfolioInvestment", entity_id: @current_user.entity_id)
    inst_form_type, inst_custom_fields, inst_custom_headers = get_form_type("InvestmentInstrument", entity_id: @current_user.entity_id)

    headers = build_apis_headers(custom_headers, custom_calc_headers, inst_custom_headers)

    workbook.add_worksheet(name: "AggregatePortfolioInvestments") do |sheet|
      sheet.add_row(headers)

      @aggregate_portfolio_investments.includes(:portfolio_investments, :fund, :investment_instrument).find_each do |api|
        api = api.as_of(@as_of) if as_of_override?

        sheet.add_row(build_apis_row(api, form_type, custom_fields, custom_calcs, inst_form_type, inst_custom_fields))
      end
    end
  end

  def build_apis_headers(custom_headers, custom_calc_headers, inst_custom_headers)
    [
      "Fund", "Portfolio Company", "Instrument", "Bought Quantity", "Bought Amount", "Avg Cost / Share",
      "Transfer Quantity", "Transfer Amount", "Sold Quantity", "Sold Amount", "FIFO Cost", "Realized Gain",
      "Current Quantity", "Currency", "Cost of Remaining", "FMV", "Unrealized Gain"
    ] + custom_headers + custom_calc_headers + ["Category", "Sub Category", "Sector"] + inst_custom_headers
  end

  def build_apis_row(api, form_type, custom_fields, custom_calcs, inst_form_type, inst_custom_fields)
    cf_values = get_custom_values(api, form_type, custom_fields)
    calc_values = get_custom_calc_values(api, form_type, custom_calcs)
    inst_cf_values = get_custom_values(api.investment_instrument, inst_form_type, inst_custom_fields)

    [
      api.fund.name, api.portfolio_company_name, api.investment_instrument&.name,
      api.bought_quantity, api.bought_amount.to_d, api.avg_cost.to_d,
      api.transfer_quantity, api.transfer_amount.to_d, api.sold_quantity, api.sold_amount.to_d,
      api.cost_of_sold.to_d, api.gain.to_d, api.quantity, api.fund.currency.to_s,
      api.cost_of_remaining.to_d, api.fmv.to_d, api.unrealized_gain.to_d
    ] + cf_values + calc_values + [
      api.investment_instrument&.category, api.investment_instrument&.sub_category, api.investment_instrument&.sector
    ] + inst_cf_values
  end

  def add_pis_tab(workbook)
    form_type, custom_fields, custom_headers, custom_calcs, custom_calc_headers = get_form_type("PortfolioInvestment", entity_id: @current_user.entity_id)

    headers = build_pis_headers(custom_headers, custom_calc_headers)

    workbook.add_worksheet(name: "PortfolioInvestments") do |sheet|
      sheet.add_row(headers)

      @aggregate_portfolio_investments.includes(portfolio_investments: %i[fund investment_instrument]).find_each do |api|
        api = api.as_of(@as_of) if as_of_override?

        api.portfolio_investments.each do |pi|
          sheet.add_row(build_pis_row(pi, form_type, custom_fields, custom_calcs))
        end
      end
    end
  end

  def build_pis_headers(custom_headers, custom_calc_headers)
    [
      "Id", "Fund", "Portfolio Company", "Instrument", "Investment Date", "Quantity", "Instrument Currency",
      "Amount in Instrument Currency", "Fund Currency", "Amount", "Cost", "Cost Of Sold", "Cost of Remaining",
      "Transfer Amount", "FMV", "Realized Gain", "Unrealized Gain", "Sold Quantity", "Transfer Quantity",
      "Net Quantity Available", "Total Qty As Of Investment Date", "Notes"
    ] + custom_headers + custom_calc_headers
  end

  def build_pis_row(portfolio_investment, form_type, custom_fields, custom_calcs)
    cf_values = get_custom_values(portfolio_investment, form_type, custom_fields)
    calc_values = get_custom_calc_values(portfolio_investment, form_type, custom_calcs)

    pi = portfolio_investment

    if pi.buy?
      net_qty = pi.net_quantity
      unrealized_gain = pi.unrealized_gain
      gain = ""
    else
      net_qty = ""
      unrealized_gain = ""
      gain = pi.gain
    end

    [
      pi.id, pi.fund.name, pi.portfolio_company_name, pi.investment_instrument,
      pi.investment_date, pi.quantity, pi.investment_instrument&.currency&.to_s,
      pi.base_amount.to_d, pi.fund.currency.to_s, pi.amount.to_d, pi.cost.to_d,
      pi.cost_of_sold.to_d, pi.cost_of_remaining.to_d, pi.transfer_amount.to_d,
      pi.fmv.to_d, gain.to_d, unrealized_gain.to_d, pi.sold_quantity, pi.transfer_quantity,
      net_qty, pi.quantity_as_of_date, pi.notes
    ] + cf_values + calc_values
  end

  def add_portfolio_companies_tab(workbook)
    form_type, custom_fields, custom_headers = get_form_type("Investor", entity_id: @current_user.entity_id)

    headers = build_company_headers(custom_headers)

    workbook.add_worksheet(name: "Portfolio Company") do |sheet|
      sheet.add_row(headers)

      @aggregate_portfolio_investments.group_by(&:portfolio_company).each do |company, apis|
        sheet.add_row(build_company_row(company, apis, form_type, custom_fields))
      end
    end
  end

  def build_company_headers(custom_headers)
    [
      "Fund", "Portfolio Company", "Bought Quantity", "Bought Amount", "Avg Cost / Share", "Transfer Quantity",
      "Transfer Amount", "Sold Quantity", "Sold Amount", "FIFO Cost", "Realized Gain", "Current Quantity",
      "Currency", "Cost of Remaining", "FMV", "Unrealized Gain"
    ] + custom_headers
  end

  def build_company_row(company, apis, form_type, custom_fields)
    fund = nil
    bought_quantity = sold_quantity = transfer_quantity = quantity = 0
    bought_amount = sold_amount = transfer_amount = fmv = cost_of_remaining = avg_cost = 0
    cost_of_sold = gain = unrealized_gain = 0

    apis.each do |api|
      fund = api.fund
      api = api.as_of(@as_of) if as_of_override?

      bought_quantity += api.bought_quantity
      bought_amount += @bank.exchange_with(api.bought_amount, @currency)
      sold_quantity += api.sold_quantity
      sold_amount += @bank.exchange_with(api.sold_amount, @currency)
      transfer_quantity += api.transfer_quantity
      transfer_amount += @bank.exchange_with(api.transfer_amount, @currency)
      quantity += api.quantity
      fmv += @bank.exchange_with(api.fmv, @currency)
      cost_of_remaining += @bank.exchange_with(api.cost_of_remaining, @currency)
      avg_cost += @bank.exchange_with(api.avg_cost, @currency)
      cost_of_sold += api.cost_of_sold
      gain += api.gain
      unrealized_gain += api.unrealized_gain
    end

    cf_values = get_custom_values(company, form_type, custom_fields)

    [
      fund, company.investor_name, bought_quantity, bought_amount.to_d, avg_cost.to_d,
      transfer_quantity, transfer_amount.to_d, sold_quantity, sold_amount.to_d,
      cost_of_sold.to_d, gain.to_d, quantity, fund.currency.to_s,
      cost_of_remaining.to_d, fmv.to_d, unrealized_gain.to_d
    ] + cf_values
  end

  def as_of_override?
    @as_of.present? && @as_of != Time.zone.today
  end
end
