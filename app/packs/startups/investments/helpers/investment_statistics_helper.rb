module InvestmentStatisticsHelper
  PIE_CHART_COLORS = [
    "#5d87ff", "#65C18C", "#9ADCFF", "#364F6B", "#3FC1C9", "#54BAB9", "#FC5185", "#FFBCBC", "#EDF6E5", "#FF964F"
  ].freeze

  def pie_chart_with_options(data)
    options = {
      library: {
        **chart_theme_color,
        plotOptions: {
          pie: {
            dataLabels: {
              enabled: true,
              format: '{point.name}:<br>{point.percentage:.1f} %'
            }
          }
        }
      },
      prefix: ""
    }

    # Extend colors if more than 10 data points
    if data.size > 10
      extended_colors = PIE_CHART_COLORS.dup
      loop do
        extended_colors += PIE_CHART_COLORS[1..] # Start from index 1
        break if extended_colors.size >= data.size
      end
      options[:colors] = extended_colors
    end

    pie_chart data, **options
  end

  # 1. Column Chart for Amount by Funding Round
  def investment_amount_by_funding_round(investments, category: nil)
    investments = investments.where(category: category) if category.present?
    grouped_data = investments.group(:funding_round)
                              .sum("amount_cents/100") # Compute total amount

    column_chart grouped_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }, prefix: "$"
  end

  # 2. Pie Chart for Fully Diluted Holding Across Investors
  def fully_diluted_holdings(investments)
    # Calculate total equity holdings
    equity_holdings = investments.where(investment_type: "Equity").group(:investor_name).sum(:quantity)

    # Calculate total convertible investments
    convertibles = investments.where(investment_type: "Convertible").group(:investor_name).sum(:quantity)

    # Merge holdings (ensure all investors appear)
    all_investors = (equity_holdings.keys + convertibles.keys).uniq

    # Compute fully diluted numbers
    fully_diluted = all_investors.map do |investor|
      total_holdings = (equity_holdings[investor] || 0) + (convertibles[investor] || 0)
      [investor, total_holdings]
    end

    pie_chart_with_options fully_diluted
  end

  # 3. Column Chart for Amount Per Investor
  def investment_amount_by_investor(investments)
    grouped_data = investments.group(:investor_name)
                              .sum("amount_cents/100") # Compute total amount

    column_chart grouped_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }, prefix: "$"
  end
end
