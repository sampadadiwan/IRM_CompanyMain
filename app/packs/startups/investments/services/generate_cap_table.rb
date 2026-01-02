class GenerateCapTable < Trailblazer::Operation
  step :initialize_params
  step :fetch_investments
  step :calculate_holdings
  step :calculate_totals
  step :format_result

  def initialize_params(options, params:, **)
    options[:funding_rounds] = params[:funding_rounds]
    options[:portfolio_company_id] = params[:portfolio_company_id]
    options[:group_by_field] = params[:group_by_field] || :investor_name
  end

  def fetch_investments(options, funding_rounds:, portfolio_company_id:, **)
    options[:investments] = Investment.where(
      funding_round: funding_rounds,
      portfolio_company_id: portfolio_company_id
    )
  end

  def calculate_holdings(options, investments:, group_by_field:, **)
    # Separate equity and convertible investments
    equity_investments = investments.where(investment_type: "Equity")
    convertible_investments = investments.where(investment_type: "Convertible")

    # Compute current holdings (excluding convertibles)
    options[:current_holdings] = equity_investments.group(group_by_field).sum(:quantity)

    # Compute total convertibles for each investor
    options[:convertibles] = convertible_investments.group(group_by_field).sum(:quantity)
  end

  def calculate_totals(options, current_holdings:, convertibles:, **)
    # Merge both hashes to get all unique investors
    options[:all_investors] = (current_holdings.keys + convertibles.keys).uniq

    # Compute total outstanding shares for percentage calculations
    total_equity = current_holdings.values.sum
    total_fully_diluted = total_equity + convertibles.values.sum

    # Handle case where only convertibles exist
    total_equity = total_fully_diluted if total_equity.zero?

    options[:total_equity] = total_equity
    options[:total_fully_diluted] = total_fully_diluted
  end

  def format_result(options, all_investors:, investments:, group_by_field:, current_holdings:, convertibles:, total_equity:, total_fully_diluted:, **)
    return options[:model] = [] if total_fully_diluted.zero?

    # Generate the cap table
    cap_table = all_investors.map do |grouping_field|
      # Find one investment to get the category
      investment = investments.find { |i| i.send(group_by_field) == grouping_field }

      display_name = if investment&.category == "Self"
                       investment.portfolio_company.entity.name
                     else
                       grouping_field
                     end

      equity_quantity = current_holdings[grouping_field] || 0
      convertible_quantity = convertibles[grouping_field] || 0
      diluted_quantity = equity_quantity + convertible_quantity

      percentage = total_equity.positive? ? (equity_quantity.to_f / total_equity * 100).round(1) : 0.0
      fully_diluted_percentage = (diluted_quantity.to_f / total_fully_diluted * 100).round(1)

      {
        grouping_field: display_name,
        quantity: equity_quantity,
        percentage: "#{percentage}%",
        fully_diluted: diluted_quantity,
        fully_diluted_percentage: "#{fully_diluted_percentage}%"
      }
    end

    # Append total row
    cap_table << {
      grouping_field: "Total",
      quantity: total_equity,
      percentage: "100.0%",
      fully_diluted: total_fully_diluted,
      fully_diluted_percentage: "100.0%"
    }

    options[:model] = cap_table
  end
end
