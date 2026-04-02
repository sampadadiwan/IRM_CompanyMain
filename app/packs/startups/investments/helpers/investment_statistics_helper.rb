module InvestmentStatisticsHelper
  PIE_CHART_COLORS = [
    "#5d87ff", "#65C18C", "#9ADCFF", "#364F6B", "#3FC1C9", "#54BAB9", "#FC5185", "#FFBCBC", "#EDF6E5", "#FF964F"
  ].freeze

  # TODO: Identical method exists in FundStatisticsHelper - consider refactoring to a common helper if needed in multiple places
  def pie_chart_with_options(data, chart_type: "pie", custom_colors: false)
    chart_type = chart_type.to_s.downcase
    inner_size = chart_type == "pie" ? nil : "50%"
    semi       = chart_type == "half_donut"

    pie_plot_opts = {
      dataLabels: {
        enabled: true,
        format: '{point.name}:<br>{point.percentage:.1f} %',
        distance: semi ? -30 : 30
      }
    }
    pie_plot_opts[:innerSize]  = inner_size   if inner_size
    pie_plot_opts[:startAngle] = -90          if semi
    pie_plot_opts[:endAngle]   = 90           if semi
    pie_plot_opts[:center]     = ["50%", "75%"] if semi
    pie_plot_opts[:size]       = "100%" if semi

    options = {
      library: {
        **chart_theme_color,
        plotOptions: { pie: pie_plot_opts }
      },
      prefix: ""
    }

    # When custom_colors: true (e.g. called from a branded widget), use CSS vars
    # --pie-color-1..10 defined in the custom stylesheet (e.g. kedaara.css).
    # Otherwise fall back to PIE_CHART_COLORS for > 8 slices, and let Chartkick's
    # own 8 global colors handle smaller datasets.
    chartkick_default_color_count = 8 # can use Chartkick.options[:colors]&.size but avoiding a method call
    if data.size > chartkick_default_color_count
      base_colors = custom_colors ? (pie_chart_colors_from_css.presence || PIE_CHART_COLORS.dup) : PIE_CHART_COLORS.dup
      extended_colors = base_colors.dup
      loop do
        extended_colors += base_colors[1..] # Always start from index 1 to avoid adjacency
        break if extended_colors.size >= data.size
      end
      options[:colors] = extended_colors
    end

    pie_chart data, **options
  end

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
  # chart_type: :pie (default), :donut, or :half_donut
  def fully_diluted_holdings(investments, chart_type: :pie, custom_colors: false)
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
