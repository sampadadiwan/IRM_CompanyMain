module AggregatePortfolioInvestmentsHelper
  def investment_fmv_by_company(fund)
    portfolio_investments = fund.portfolio_investments.includes(:portfolio_company).group(:investor_name).sum(:fmv_cents)
    grouped = portfolio_investments.map { |name, fmv_cents| [name, fmv_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def investment_fmv_by_companies(fund, portfolio_company_ids)
    portfolio_investments = fund.portfolio_investments.includes(:portfolio_company).where(portfolio_company_id: portfolio_company_ids).group(:portfolio_company_name).sum(:fmv_cents)
    grouped = portfolio_investments.map { |name, fmv_cents| [name, fmv_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def investment_chart_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr)
    # Convert FMV from cents to dollars and prepare data for the pie chart
    grouped = investment_grouped_data_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr)

    # Group small sectors into 'Others' for pie chart while leaving table data intact
    chart_data = group_chart_data_for_pie(grouped, limit: 7)

    pie_chart_with_options(chart_data)
  end

  # better name
  def investment_chart_by_companies(entity, fund_ids, attr, portfolio_company_ids = [])
    attr = if attr.downcase == "fmv"
             "fmv_cents"
           else
             "amount_cents"
           end

    portfolio_investments = entity.portfolio_investments.buys.includes(:portfolio_company)
    portfolio_investments = portfolio_investments.where(fund_id: fund_ids) if fund_ids.present?
    portfolio_investments = portfolio_investments.where(portfolio_company_id: portfolio_company_ids) if portfolio_company_ids.present?

    portfolio_investments = portfolio_investments.group(:portfolio_company_name).sum(attr.to_sym)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def investment_bought_by_company(fund)
    portfolio_investments = fund.portfolio_investments.buys.where(quantity: 0..).includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def investment_sold_by_company(fund)
    portfolio_investments = fund.portfolio_investments.sells.includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def investment_holding_cost_by_company(fund)
    portfolio_investments = fund.portfolio_investments.buys.group_by(&:portfolio_company_name)

    grouped = portfolio_investments.transform_values do |pis|
      pis.sum { |pi| pi.net_quantity * pi.cost.to_d }
    end

    # transform_values returns a hash keyed by company name -> value
    chart_ready = grouped.map { |name, value| [name, value.to_f] }
    chart_data = group_chart_data_for_pie(chart_ready, limit: 10)

    pie_chart_with_options(chart_data)
  end

  def bought_sold_fmv(fund)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d, k.bought_amount.to_d, k.sold_amount.to_d] }

    column_chart [
      { name: "Bought", data: grouped.map { |k| [k[0], k[2]] } },
      { name: "Sold", data: grouped.map { |k| [k[0], k[3]] } },
      { name: "FMV", data: grouped.map { |k| [k[0], k[1]] } }
    ], library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  def buy_sell_timeline(fund)
    buy_data = fund.portfolio_investments.buys.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    sell_data = fund.portfolio_investments.sells.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    column_chart [{ name: "Buys", data: buy_data }, { name: "Sells", data: sell_data }], library: {
      plotOptions: {
        column: {
          pointWidth: 40,
          dataLabels: {
            enabled: false,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  # Return grouped data for sectors as array of [sector_name, value_in_dollars]
  # Returns data so views can render tables alongside charts.
  def investment_grouped_data_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr) # rubocop:disable Metrics/CyclomaticComplexity
    attr = if attr.to_s.downcase == "fmv"
             "fmv_cents"
           else
             "amount_cents"
           end

    # Fetch all portfolio investments with their associated portfolio_company
    portfolio_investments = filter_investments(entity.portfolio_investments.includes(:portfolio_company), fund_ids, portfolio_company_ids)

    # Normalize sectors_to_include for case-insensitive comparison (support comma-separated input)
    sectors_arr = sectors_to_include.is_a?(Array) ? sectors_to_include : Array(sectors_to_include.to_s.split(','))
    allowed = sectors_arr.map { |s| s.to_s.strip.downcase }.reject(&:empty?)

    # Initialize a hash to store the aggregated FMV for each sector
    sector_fmv = Hash.new(0)

    # Iterate through the portfolio investments and group by sector(s)
    portfolio_investments.each do |investment|
      pc = investment.portfolio_company
      next unless pc && pc.sector.present?

      if sectors_to_include.present?
        pc.sector.to_s.split(',').map(&:strip).reject(&:empty?).each do |sector|
          normalized = sector.downcase
          next if allowed.any? && allowed.exclude?(normalized)

          sector_fmv[sector] += investment.send(attr).to_i
        end
      else
        pc.sector.to_s.split(',').map(&:strip).reject(&:empty?).each do |sector|
          sector_fmv[sector] += investment.send(attr).to_i
        end
      end
    end

    sector_fmv.map { |sector, fmv_cents| [sector, fmv_cents / 100.0] }
  end

  def filter_investments(investments, fund_ids = [], portfolio_company_ids = [])
    investments = investments.where(fund_id: fund_ids) if fund_ids.present?
    investments = investments.where(portfolio_company_id: portfolio_company_ids) if portfolio_company_ids.present?
    investments
  end

  # Return grouped data for companies as array of [company_name, value_in_dollars]
  def investment_grouped_data_by_companies(entity, fund_ids, attr, portfolio_company_ids = [])
    attr = if attr.to_s.downcase == "fmv"
             "fmv_cents"
           else
             "amount_cents"
           end

    portfolio_investments = entity.portfolio_investments.buys.includes(:portfolio_company)
    portfolio_investments = portfolio_investments.where(fund_id: fund_ids) if fund_ids.present?
    portfolio_investments = portfolio_investments.where(portfolio_company_id: portfolio_company_ids) if portfolio_company_ids.present?

    grouped = portfolio_investments.group(:portfolio_company_name).sum(attr.to_sym)
    grouped.map { |name, amount_cents| [name, amount_cents / 100.0] }
  end

  private

  def group_chart_data_for_pie(data, limit: 10)
    sorted = Array(data).map { |name, value| [name, value.to_f] }
                        .sort_by { |_, value| -value }

    return sorted if sorted.blank? || sorted.size <= limit

    top = sorted.first(limit)
    other_sum = sorted.drop(limit).sum { |_, value| value }

    top + [["Others", other_sum]]
  end
end
