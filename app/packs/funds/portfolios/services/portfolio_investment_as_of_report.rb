class PortfolioInvestmentAsOfReport
  include FormTypeHelper

  def initialize(aggregate_portfolio_investments, current_user, as_of: nil)
    @aggregate_portfolio_investments = aggregate_portfolio_investments
    @current_user = current_user
    @as_of = as_of
    setup_exchange_rates
  end

  def generate
    package = Axlsx::Package.new
    workbook = package.workbook

    add_apis_tab(workbook)
    add_pis_tab(workbook)
    add_portfolio_companies_tab(workbook)

    package
  end

  # This is required to enable adding Money objects in different currencies
  def setup_exchange_rates
    latest_rates = ExchangeRate.latest_rates_before(@as_of, @current_user.entity_id)
    latest_rates.each do |(from, to), rate|
      Money.add_rate(from, to, rate.rate)
    end
  end

  def add_apis_tab(workbook)
    form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers = get_form_type("AggregatePortfolioInvestment", entity_id: @current_user.entity_id)
    inv_form_type, inv_custom_field_names, inv_custom_headers = get_form_type("Investor", entity_id: @current_user.entity_id)
    inv_inst_form_type, inv_inst_custom_field_names, inv_inst_custom_headers = get_form_type("InvestmentInstrument", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "AggregatePortfolioInvestments") do |sheet|
      # Create the header row
      sheet.add_row(["Fund", "Bought Quantity", "Bought Amount", "Sold Quantity", "Sold Amount", "Current Quantity", "FMV", "Cost", "Avg Cost / Share", "FIFO Cost"] + custom_headers + custom_calc_headers + ["Portfolio Company"] + inv_custom_headers + ["Instrument", "Category", "Sub Category", "Sector"] + inv_inst_custom_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.each do |api|
        api = api.as_of(@as_of) if @as_of.present? && @as_of != Date.today

        # Get the custom fields
        custom_field_values = get_custom_values(api, form_type, custom_field_names)
        custom_calc_values = get_custom_calc_values(api, form_type, custom_calcs)

        # We display the CFs for investor and investment_instrument
        inv_custom_field_values = get_custom_values(api.portfolio_company, inv_form_type, inv_custom_field_names)
        inv_inst_custom_field_values = get_custom_values(api.investment_instrument, inv_inst_form_type, inv_inst_custom_field_names)

        # Add row to XL
        sheet.add_row [api.fund.name, api.bought_quantity, api.bought_amount.to_d, api.sold_quantity, api.sold_amount.to_d, api.quantity, api.fmv, api.cost_of_remaining.to_d, api.avg_cost.to_d, api.cost_of_sold.to_d] +
                      custom_field_values + custom_calc_values +
                      [api.portfolio_company_name] + inv_custom_field_values +
                      [api.investment_instrument&.name, api.investment_instrument&.category, api.investment_instrument&.sub_category, api.investment_instrument&.sector] + inv_inst_custom_field_values
      end
    end
  end

  def add_pis_tab(workbook)
    form_type, custom_field_names, custom_headers, custom_calcs, custom_calc_headers = get_form_type("PortfolioInvestment", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "PortfolioInvestments") do |sheet|
      # Create the header row
      sheet.add_row(["Id", "Fund", "Portfolio Company", "Investment Date", "Amount", "Quantity", "Net Quantity", "Total Qty As Of Date", "Cost", "Cost Of Sold", "FMV", "Gain", "Unrealized Gain", "Instrument", "Notes"] + custom_headers + custom_calc_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.includes(portfolio_investments: %i[fund investment_instrument]).find_each do |api|
        api.portfolio_investments.each do |pi|
          custom_field_values = get_custom_values(pi, form_type, custom_field_names)
          custom_calc_values = get_custom_calc_values(pi, form_type, custom_calcs)

          if pi.buy?
            net_qty = pi.net_quantity
            unrealized_gain = pi.unrealized_gain
            gain = ""
          else
            net_qty = ""
            unrealized_gain = ""
            gain = pi.gain
          end

          pi = pi.as_of(@as_of) if @as_of.present? && @as_of != Date.today

          sheet.add_row [pi.id, pi.fund.name, pi.portfolio_company_name, pi.investment_date, pi.amount, pi.quantity, net_qty, pi.quantity_as_of_date, pi.cost, pi.cost_of_sold, pi.fmv, gain, unrealized_gain, pi.investment_instrument, pi.notes] + custom_field_values + custom_calc_values
        end
      end
    end
  end

  def add_portfolio_companies_tab(workbook)
    inv_form_type, inv_custom_field_names, inv_custom_headers = get_form_type("Investor", entity_id: @current_user.entity_id)

    workbook.add_worksheet(name: "Portfolio Company") do |sheet|
      # Create the header row
      sheet.add_row(["Portfolio Company", "Bought Quantity", "Bought Amount", "Sold Quantity", "Sold Amount", "Current Quantity", "FMV", "Cost", "Avg Cost / Share", "Cost of Remaining"] + inv_custom_headers)

      # Create entries for each item
      @aggregate_portfolio_investments.group_by(&:portfolio_company).each do |pc, apis|
        bought_quantity = 0
        bought_amount = 0
        sold_quantity = 0
        sold_amount = 0
        quantity = 0
        fmv = 0
        cost_of_remaining = 0
        avg_cost = 0

        apis.each do |api|
          api = api.as_of(@as_of) if @as_of.present? && @as_of != Date.today
          bought_quantity += api.bought_quantity
          bought_amount += api.bought_amount
          sold_quantity += api.sold_quantity
          sold_amount += api.sold_amount
          quantity += api.quantity
          fmv += api.fmv
          cost_of_remaining += api.cost_of_remaining
          avg_cost += api.avg_cost
        end

        inv_custom_field_values = get_custom_values(pc, inv_form_type, inv_custom_field_names)

        # Add row to XL
        sheet.add_row [pc.investor_name, bought_quantity, bought_amount.to_d, sold_quantity, sold_amount.to_d, quantity, fmv, cost_of_remaining.to_d, avg_cost.to_d, cost_of_remaining.to_d] + inv_custom_field_values
      end
    end
  end

  def save_to_file(path)
    package = generate
    package.serialize(path)
  end

  delegate :to_stream, to: :generate
end
