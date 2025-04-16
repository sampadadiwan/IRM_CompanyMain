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

  def generate
    package = Axlsx::Package.new
    workbook = package.workbook

    add_pis_tab(workbook)
    add_apis_tab(workbook)
    add_portfolio_companies_tab(workbook)

    package
  end

  # This is required to enable adding Money objects in different currencies
  def setup_exchange_rates
    @bank = ExchangeRate.setup_variable_exchange(@as_of, @current_user.entity_id)
  end

  def add_apis_tab(workbook)
    form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers = get_form_type("AggregatePortfolioInvestment", entity_id: @current_user.entity_id)
    inv_inst_form_type, inv_inst_custom_field_names, inv_inst_custom_headers = get_form_type("InvestmentInstrument", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "AggregatePortfolioInvestments") do |sheet|
      # Create the header row

      sheet.add_row(["Fund", "Portfolio Company", "Instrument", "Bought Quantity", "Bought Amount", "Avg Cost / Share", "Transfer Quantity", "Transfer Amount", "Sold Quantity", "Sold Amount", "FIFO Cost", "Realized Gain", "Current Quantity", "Currency", "Cost of Remaining", "FMV", "Unrealized Gain"] + custom_headers + custom_calc_headers + ["Category", "Sub Category", "Sector"] + inv_inst_custom_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.each do |api|
        api = api.as_of(@as_of) if @as_of.present? && @as_of != Time.zone.today

        # Get the custom fields
        custom_field_values = get_custom_values(api, form_type, custom_field_names)
        custom_calc_values = get_custom_calc_values(api, form_type, custom_calcs)

        # We display the CFs for investor and investment_instrument
        inv_inst_custom_field_values = get_custom_values(api.investment_instrument, inv_inst_form_type, inv_inst_custom_field_names)

        # Add row to XL
        sheet.add_row [api.fund.name, api.portfolio_company_name, api.investment_instrument&.name, api.bought_quantity, api.bought_amount.to_d, api.avg_cost.to_d, api.transfer_quantity, api.transfer_amount.to_d, api.sold_quantity, api.sold_amount.to_d, api.cost_of_sold.to_d, api.gain.to_d, api.quantity, api.fund.currency.to_s, api.cost_of_remaining.to_d, api.fmv.to_d, api.unrealized_gain.to_d] +
                      custom_field_values + custom_calc_values +
                      [api.investment_instrument&.category, api.investment_instrument&.sub_category, api.investment_instrument&.sector] + inv_inst_custom_field_values
      end
    end
  end

  def add_pis_tab(workbook)
    form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers = get_form_type("PortfolioInvestment", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "PortfolioInvestments") do |sheet|
      # Create the header row
      sheet.add_row(["Id", "Fund", "Portfolio Company", "Instrument", "Investment Date", "Quantity", "Instrument Currency", "Amount in Instrument Currency", "Fund Currency", "Amount", "Cost", "FMV", "Realized Gain", "Unrealized Gain", "Sold Quantity", "Transfer Quantity", "Net Quantity Available", "Total Qty As Of Investment Date", "Cost Of Sold", "Cost of Remaining", "Notes"] + custom_headers + custom_calc_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.includes(portfolio_investments: %i[fund investment_instrument]).find_each do |api|
        api = api.as_of(@as_of) if @as_of.present? && @as_of != Time.zone.today

        api.portfolio_investments.each do |pi|
          custom_field_values = get_custom_values(pi, form_type, custom_field_names)
          custom_calc_values = get_custom_calc_values(pi, form_type, custom_calcs)

          pi = pi.as_of(@as_of) if @as_of.present? && @as_of != Time.zone.today

          if pi.buy?
            net_qty = pi.net_quantity
            unrealized_gain = pi.unrealized_gain
            gain = ""
          else
            net_qty = ""
            unrealized_gain = ""
            gain = pi.gain
          end

          sheet.add_row [pi.id, pi.fund.name, pi.portfolio_company_name, pi.investment_instrument, pi.investment_date, pi.quantity, pi.investment_instrument&.currency&.to_s, pi.base_amount.to_d, pi.fund.currency.to_s, pi.amount.to_d, pi.cost.to_d, pi.fmv.to_d, gain.to_d, unrealized_gain.to_d, pi.sold_quantity, pi.transfer_quantity, net_qty, pi.quantity_as_of_date, pi.cost_of_sold.to_d, pi.cost_of_remaining.to_d, pi.notes] + custom_field_values + custom_calc_values
        end
      end
    end
  end

  # rubocop:disable Metrics/BlockLength
  # rubocop:disable Metrics/MethodLength
  def add_portfolio_companies_tab(workbook)
    inv_form_type, inv_custom_field_names, inv_custom_headers = get_form_type("Investor", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "Portfolio Company") do |sheet|
      # Create the header row
      sheet.add_row(["Fund", "Portfolio Company", "Bought Quantity", "Bought Amount", "Avg Cost / Share", "Transfer Quantity", "Transfer Amount", "Sold Quantity", "Sold Amount", "FIFO Cost", "Realized Gain", "Current Quantity", "Currency", "Cost of Remaining", "FMV", "Unrealized Gain"] + inv_custom_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.group_by(&:portfolio_company).each do |pc, apis|
        fund = nil
        bought_quantity = 0
        bought_amount = 0
        sold_quantity = 0
        sold_amount = 0
        transfer_quantity = 0
        transfer_amount = 0
        quantity = 0
        fmv = 0
        cost_of_remaining = 0
        avg_cost = 0
        cost_of_sold = 0
        gain = 0
        unrealized_gain = 0

        apis.each do |api|
          fund = api.fund
          api = api.as_of(@as_of) if @as_of.present? && @as_of != Time.zone.today
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

        inv_custom_field_values = get_custom_values(pc, inv_form_type, inv_custom_field_names)

        # Add row to XL
        sheet.add_row [fund, pc.investor_name, bought_quantity, bought_amount.to_d, avg_cost.to_d, transfer_quantity, transfer_amount.to_d, sold_quantity, sold_amount.to_d, cost_of_sold.to_d, gain.to_d, quantity, fund.currency.to_s, cost_of_remaining.to_d, fmv.to_d, unrealized_gain.to_d] + inv_custom_field_values
      end
    end
  end
  # rubocop:enable Metrics/BlockLength
  # rubocop:enable Metrics/MethodLength

  def save_to_file(path)
    package = generate
    package.serialize(path)
  end

  delegate :to_stream, to: :generate
end
