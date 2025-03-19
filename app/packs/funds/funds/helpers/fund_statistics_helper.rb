module FundStatisticsHelper
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

    # Add colors only if there are more than 10 data points
    if data.size > 10
      extended_colors = PIE_CHART_COLORS.dup
      loop do
        extended_colors += PIE_CHART_COLORS[1..] # Always start from index 1
        break if extended_colors.size >= data.size
      end
      options[:colors] = extended_colors
    end

    pie_chart data, **options
  end

  def fund_commitment_amounts(fund)
    commitments = fund.capital_commitments
    if commitments.length <= 10
      commitments = commitments.order(committed_amount_cents: :desc).joins(:investor).includes(:investor)
      grouped = commitments.group_by(&:investor_name)
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.committed_amount_cents / 100) }] }

    else
      commitments = commitments.limit(10).order(committed_amount_cents: :desc).joins(:investor).includes(:investor)
      grouped = commitments.group_by(&:investor_name)
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.committed_amount_cents / 100) }] }

      # This is to get the sum of the other
      # https://stackoverflow.com/questions/2623853/how-to-sum-from-an-offset-through-the-end-of-the-table
      row = CapitalCommitment.connection.select_one("select sum(committed_amount_cents) from (#{fund.capital_commitments.order(committed_amount_cents: :desc).offset(10).to_sql}) q")
      others_cents = row["sum(committed_amount_cents)"]

      grouped << ["Others", others_cents / 100]
    end

    pie_chart_with_options grouped
  end

  def fund_commitments_collected(fund)
    commitments = fund.capital_commitments
    if commitments.length <= 10
      commitments = commitments.order(committed_amount_cents: :desc).joins(:investor).includes(:investor)
      grouped = commitments.group_by(&:investor_name)
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.collected_amount_cents / 100) }] }

    else
      commitments = commitments.limit(10).order(committed_amount_cents: :desc).joins(:investor).includes(:investor)
      grouped = commitments.group_by(&:investor_name)
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.collected_amount_cents / 100) }] }

      # This is to get the sum of the other
      # https://stackoverflow.com/questions/2623853/how-to-sum-from-an-offset-through-the-end-of-the-table
      row = CapitalCommitment.connection.select_one("select sum(committed_amount_cents) from (#{fund.capital_commitments.order(committed_amount_cents: :desc).offset(10).to_sql}) q")
      others_cents = row["sum(committed_amount_cents)"]
      grouped << ["Others", others_cents / 100]
    end

    pie_chart_with_options grouped
  end

  def quarter(date)
    ((date.month - 1) / 3) + 1
  end

  def fund_commitments_collected_by_quarter(fund)
    capital_calls = fund.capital_calls.where("due_date > ?", Time.zone.today - 1.year)
    capital_calls = capital_calls.group_by { |cc| "Q#{quarter(cc.due_date)}" }
                                 .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.collected_amount_cents / 100) }] }

    column_chart capital_calls, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"
  end

  def fund_distributions_by_quarter(fund)
    capital_distributions = fund.capital_distributions.where("distribution_date > ?", Time.zone.today - 1.year)
    capital_distributions = capital_distributions.group_by { |cc| "Q#{quarter(cc.distribution_date)}" }
                                                 .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.gross_amount_cents / 100) }] }

    column_chart capital_distributions, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } },
      **chart_theme_color
    }, prefix: "#{fund.currency}:"
  end
end
