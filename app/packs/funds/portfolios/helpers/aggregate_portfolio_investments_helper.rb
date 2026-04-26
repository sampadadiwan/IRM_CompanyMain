module AggregatePortfolioInvestmentsHelper
  def investment_fmv_by_company(fund, **options)
    portfolio_investments = fund.portfolio_investments.includes(:portfolio_company).group(:investor_name).sum(:fmv_cents)
    grouped = portfolio_investments.map { |name, fmv_cents| [name, fmv_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    options[:id] ||= "investment_fmv_by_company_chart_#{fund.id}"
    pie_chart_with_options(chart_data, **options)
  end

  def investment_fmv_by_companies(fund, portfolio_company_ids, **options)
    portfolio_investments = fund.portfolio_investments.includes(:portfolio_company).where(portfolio_company_id: portfolio_company_ids).group(:portfolio_company_name).sum(:fmv_cents)
    grouped = portfolio_investments.map { |name, fmv_cents| [name, fmv_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    options[:id] ||= "investment_fmv_by_companies_chart_#{fund.id}"
    custom_colors = options.delete(:custom_colors) || false
    pie_chart_with_options(chart_data, custom_colors: custom_colors, **options)
  end

  # Generate a pie chart for portfolio investments grouped by sector
  # Filters out zero values and applies smart grouping:
  # - If ≤ limit non-zero sectors: shows all
  # - If > limit non-zero sectors: shows (limit-1) + "Others"
  #
  # @param entity [Entity] The entity to fetch investments for
  # @param fund_ids [Array<Integer>] Fund IDs to filter by
  # @param portfolio_company_ids [Array<Integer>] Portfolio company IDs to filter by
  # @param sectors_to_include [Array<String>, String] Sectors to include (comma-separated or array)
  # @param attr [String] Attribute to sum ('fmv' or 'bought_amount')
  # @param limit [Integer] Maximum number of slices to show (default: 10)
  # @return [String] HTML for pie chart
  def investment_chart_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr, limit: 10, **options)
    grouped = investment_grouped_data_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr)
    chart_data = group_chart_data_for_pie(grouped, limit: limit)

    options[:id] ||= "investment_chart_by_sectors_chart_#{entity.id}"
    custom_colors = options.delete(:custom_colors) || false
    pie_chart_with_options(chart_data, custom_colors: custom_colors, **options)
  end

  # Generate a pie chart for portfolio investments grouped by company
  # Filters out zero values and applies smart grouping:
  # - If ≤ limit non-zero companies: shows all
  # - If > limit non-zero companies: shows (limit-1) + "Others"
  #
  # @param entity [Entity] The entity to fetch investments for
  # @param fund_ids [Array<Integer>] Fund IDs to filter by
  # @param attr [String] Attribute to sum ('fmv' or 'bought_amount')
  # @param portfolio_company_ids [Array<Integer>] Portfolio company IDs to filter by
  # @param limit [Integer] Maximum number of slices to show (default: 10)
  # @return [String] HTML for pie chart
  def investment_chart_by_companies(entity, fund_ids, attr, portfolio_company_ids = [], limit: 10, **options)
    grouped = investment_grouped_data_by_companies(entity, fund_ids, attr, portfolio_company_ids)
    chart_data = group_chart_data_for_pie(grouped, limit: limit)

    options[:id] ||= "investment_chart_by_companies_chart_#{entity.id}"
    pie_chart_with_options(chart_data, **options)
  end

  def investment_bought_by_company(fund, **options)
    portfolio_investments = fund.portfolio_investments.buys.where(quantity: 0..).includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    options[:id] ||= "investment_bought_by_company_chart_#{fund.id}"
    pie_chart_with_options(chart_data, **options)
  end

  def investment_sold_by_company(fund, **options)
    portfolio_investments = fund.portfolio_investments.sells.includes(:portfolio_company).group(:investor_name).sum(:amount_cents)
    grouped = portfolio_investments.map { |name, amount_cents| [name, amount_cents / 100.0] }
    chart_data = group_chart_data_for_pie(grouped, limit: 10)

    options[:id] ||= "investment_sold_by_company_chart_#{fund.id}"
    pie_chart_with_options(chart_data, **options)
  end

  def investment_holding_cost_by_company(fund, **options)
    portfolio_investments = fund.portfolio_investments.buys.group_by(&:portfolio_company_name)

    grouped = portfolio_investments.transform_values do |pis|
      pis.sum { |pi| pi.net_quantity * pi.cost.to_d }
    end

    # transform_values returns a hash keyed by company name -> value
    chart_ready = grouped.map { |name, value| [name, value.to_f] }
    chart_data = group_chart_data_for_pie(chart_ready, limit: 10)

    options[:id] ||= "investment_holding_cost_by_company_chart_#{fund.id}"
    pie_chart_with_options(chart_data, **options)
  end

  def bought_sold_fmv(fund, **options)
    aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    grouped = aggregate_portfolio_investments
              .map { |k| [k.portfolio_company_name, k.fmv.to_d, k.bought_amount.to_d, k.sold_amount.to_d] }

    options[:id] ||= "bought_sold_fmv_chart_#{fund.id}"
    options[:library] ||= {}
    options[:library].deep_merge!({
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
                                  })

    column_chart [
      { name: "Bought", data: grouped.map { |k| [k[0], k[2]] } },
      { name: "Sold", data: grouped.map { |k| [k[0], k[3]] } },
      { name: "FMV", data: grouped.map { |k| [k[0], k[1]] } }
    ], **options
  end

  def buy_sell_timeline(fund, **options)
    buy_data = fund.portfolio_investments.buys.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    sell_data = fund.portfolio_investments.sells.group_by { |pi| pi.investment_date.year }.map { |k, arr| [k, arr.inject(0) { |sum, element| sum + element.amount.to_d }] }

    options[:id] ||= "buy_sell_timeline_chart_#{fund.id}"
    options[:library] ||= {}
    options[:library].deep_merge!({
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
                                  })

    column_chart [{ name: "Buys", data: buy_data }, { name: "Sells", data: sell_data }], **options
  end

  # Return grouped data for sectors as array of [sector_name, value_in_dollars]
  # Fetches buy transactions only and groups by sector(s).
  # Supports filtering by funds, companies, and specific sectors.
  # Note: A company can have multiple sectors (comma-separated), so totals may exceed 100%.
  #
  # @param entity [Entity] The entity to fetch investments for
  # @param fund_ids [Array<Integer>] Fund IDs to filter by
  # @param portfolio_company_ids [Array<Integer>] Portfolio company IDs to filter by
  # @param sectors_to_include [Array<String>, String] Sectors to include (comma-separated or array), empty means all
  # @param attr [String] Attribute to sum ('fmv' or 'bought_amount')
  # @return [Array<Array>] Array of [sector_name, value_in_dollars] pairs
  def investment_grouped_data_by_sectors(entity, fund_ids, portfolio_company_ids, sectors_to_include, attr) # rubocop:disable Metrics/CyclomaticComplexity
    attr = if attr.to_s.downcase == "fmv"
             "fmv_cents"
           else
             "amount_cents"
           end

    # Fetch all portfolio investments with their associated portfolio_company (buys only, like companies)
    portfolio_investments = filter_investments(entity.portfolio_investments.buys.includes(:portfolio_company), fund_ids, portfolio_company_ids)

    # Normalize sectors_to_include for case-insensitive comparison (support comma-separated input)
    sectors_arr = sectors_to_include.is_a?(Array) ? sectors_to_include : Array(sectors_to_include.to_s.split(','))
    allowed = sectors_arr.map { |s| s.to_s.strip.downcase }.reject(&:empty?)

    # Initialize a hash to store the aggregated value for each sector
    sector_data = Hash.new(0)

    # Iterate through the portfolio investments and group by sector(s)
    portfolio_investments.each do |investment|
      pc = investment.portfolio_company
      next unless pc && pc.sector.present?

      if sectors_to_include.present?
        pc.sector.to_s.split(',').map(&:strip).reject(&:empty?).each do |sector|
          normalized = sector.downcase
          next if allowed.any? && allowed.exclude?(normalized)

          sector_data[sector] += investment.send(attr).to_i
        end
      else
        pc.sector.to_s.split(',').map(&:strip).reject(&:empty?).each do |sector|
          sector_data[sector] += investment.send(attr).to_i
        end
      end
    end

    sector_data.map { |sector, cents| [sector, cents / 100.0] }
  end

  def filter_investments(investments, fund_ids = [], portfolio_company_ids = [])
    investments = investments.where(fund_id: fund_ids) if fund_ids.present?
    investments = investments.where(portfolio_company_id: portfolio_company_ids) if portfolio_company_ids.present?
    investments
  end

  # Return grouped data for companies as array of [company_name, value_in_dollars]
  # Fetches buy transactions only and groups by portfolio company name.
  # Supports filtering by funds and specific companies.
  #
  # @param entity [Entity] The entity to fetch investments for
  # @param fund_ids [Array<Integer>] Fund IDs to filter by
  # @param attr [String] Attribute to sum ('fmv' or 'bought_amount')
  # @param portfolio_company_ids [Array<Integer>] Portfolio company IDs to filter by
  # @return [Array<Array>] Array of [company_name, value_in_dollars] pairs
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

  # Process grouped data for table display with smart non-zero filtering
  # Returns: { top: [[name, value], ...], others: [[name, value], ...], total: float }
  # When there are more than `limit` items, shows (limit-1) items + "Others" row to match chart behavior
  def process_table_data(grouped_data, limit: 10)
    sorted = grouped_data.sort_by { |_, v| -v }

    # Filter out zero values
    non_zero = sorted.reject { |_, value| value.to_f.zero? }

    total = non_zero.sum { |_, v| v.to_f }

    # If we have limit or fewer non-zero items, show them all without "Others"
    if non_zero.size <= limit
      { top: non_zero, others: [], total: total }
    else
      # We have more than limit non-zero items, so show (limit-1) + "Others" row to match chart
      { top: non_zero.first(limit - 1), others: non_zero.drop(limit - 1), total: total }
    end
  end

  private

  # Smart grouping: show up to `limit` non-zero items
  # If there are more than `limit` non-zero items, show (limit-1) items plus 'Others'
  # If there are exactly `limit` or fewer non-zero items, show them all without 'Others'
  def group_chart_data_for_pie(data, limit: 10)
    sorted = Array(data).map { |name, value| [name, value.to_f] }
                        .sort_by { |_, value| -value }

    return sorted if sorted.blank?

    # Filter out zero values
    non_zero = sorted.reject { |_, value| value.zero? }

    # If we have limit or fewer non-zero items, return them all
    return non_zero if non_zero.size <= limit

    # We have more than limit non-zero items, so show (limit-1) + 'Others'
    top = non_zero.first(limit - 1)
    other_sum = non_zero.drop(limit - 1).sum { |_, value| value }

    top + [["Others", other_sum]]
  end
end
