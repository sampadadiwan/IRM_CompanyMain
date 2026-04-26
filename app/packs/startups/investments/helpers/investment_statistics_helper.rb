module InvestmentStatisticsHelper
  # 1. Column Chart for Amount by Funding Round
  def investment_amount_by_funding_round(investments, category: nil)
    investments = investments.where(category: category) if category.present?

    # Get the earliest investment date for each funding round
    funding_round_dates = investments.reorder(nil)
                                     .group(:funding_round)
                                     .minimum(:investment_date) # Get earliest investment date per round

    # Compute the total amount per funding round
    funding_round_amounts = investments.reorder(nil)
                                       .group(:funding_round)
                                       .sum("amount_cents/100")

    # Sort funding rounds by their earliest investment date
    ordered_funding_rounds = funding_round_dates.sort_by { |_round, date| date }.map(&:first)

    # Ensure the funding round amounts are displayed in chronological order
    sorted_data = ordered_funding_rounds.map { |round| [round, funding_round_amounts[round] || 0] }

    column_chart sorted_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  # 4. Line Chart for Self Ownership Trend over Time (%stake fully diluted)
  def self_ownership_trend(investments)
    return if investments.empty?

    # Get funding rounds in chronological order
    ordered_rounds = investments.reorder(nil).group(:funding_round).minimum(:investment_date).sort_by { |_round, date| date }.map(&:first)

    cumulative_rounds = []
    portfolio_company = investments.first.portfolio_company

    sorted_self_data = ordered_rounds.map do |round|
      cumulative_rounds << round

      # Use generate_cap_table logic to get correct fully diluted percentage
      result = GenerateCapTable.call(params: {
                                       funding_rounds: cumulative_rounds,
                                       portfolio_company_id: portfolio_company.id,
                                       group_by_field: :category
                                     })
      cap_table = result[:model]

      # Find the "Self" category row in the generated cap table
      self_row = cap_table.find { |row| row[:grouping_field] == portfolio_company.entity.name }

      percentage = self_row ? self_row[:fully_diluted_percentage].to_f : 0.0
      [round, percentage]
    end

    line_chart sorted_self_data, library: {
      yAxis: {
        title: { text: "Percentage (%)" },
        labels: { format: "{value}%" }
      },
      plotOptions: {
        line: {
          dataLabels: {
            enabled: true,
            format: "{point.y}%"
          }
        }
      },
      **chart_theme_color
    }
  end

  # 2. Pie Chart for Fully Diluted Holding Across Investors
  # chart_type: :pie, :donut (default), or :half_donut
  def fully_diluted_holdings(investments, chart_type: :donut, custom_colors: false)
    # Calculate total equity holdings
    equity_holdings = investments.reorder(nil).where(investment_type: "Equity").group(:investor_name).sum(:quantity)

    # Calculate total convertible investments
    convertibles = investments.reorder(nil).where(investment_type: "Convertible").group(:investor_name).sum(:quantity)

    # Merge holdings (ensure all investors appear)
    all_investors = (equity_holdings.keys + convertibles.keys).uniq

    # Compute fully diluted numbers
    fully_diluted = all_investors.map do |investor|
      total_holdings = (equity_holdings[investor] || 0) + (convertibles[investor] || 0)
      [investor, total_holdings]
    end

    pie_chart_with_options fully_diluted, chart_type:, custom_colors:
  end

  # 3. Column Chart for Amount Per Investor
  def investment_amount_by_investor(investments)
    grouped_data = investments.reorder(nil).group(:investor_name)
                              .sum("amount_cents/100") # Compute total amount

    # Sort the data alphabetically by investor name
    sorted_data = grouped_data.sort_by { |investor_name, _amount| investor_name }

    column_chart sorted_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end
end
