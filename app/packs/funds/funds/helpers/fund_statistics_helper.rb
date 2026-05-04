module FundStatisticsHelper
  PIE_CHART_COLORS = [
    "#5d87ff", "#65C18C", "#9ADCFF", "#364F6B", "#3FC1C9", "#54BAB9", "#FC5185", "#FFBCBC", "#EDF6E5", "#FF964F"
  ].freeze

  # Only pass custom colors as true if we are sure the css has these colors defined otherwise the chart will have all black color (no color actually but looks black)
  def pie_chart_with_options(data, chart_type: "donut", descending: true, **extra_options) # rubocop:disable Metrics/CyclomaticComplexity
    chart_type = chart_type.to_s.downcase
    inner_size = chart_type == "pie" ? nil : "50%"
    semi       = chart_type == "half_donut"

    # Sort data in descending order if requested
    data = if descending && data.is_a?(Hash)
             data.sort_by { |_, v| -v }.to_h
           elsif descending && data.is_a?(Array)
             data.sort_by { |_, v| -v }
           else
             data
           end

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

    # When use_custom_colors?: true , use CSS vars
    # --pie-color-1..15 defined in the custom stylesheet (e.g. kedaara.css).
    # Otherwise fall back to pie-colors in styles.css.
    base_colors = use_custom_colors? ? (pie_chart_colors_from_css.presence || PIE_CHART_COLORS.dup) : PIE_CHART_COLORS.dup
    extended_colors = base_colors.dup
    if extended_colors.size < data.size
      loop do
        extended_colors += base_colors[1..] # Always start from index 1 to avoid adjacency
        break if extended_colors.size >= data.size
      end
    end
    options[:colors] = extended_colors

    pie_chart data, **options.deep_merge(extra_options)
  end

  def fund_ratios_donut_charts(fund)
    ratios = FundRatio.for_fund(fund.id).default
    latest_date = ratios.latest.any? ? ratios.latest.first.end_date : ratios.maximum(:end_date)
    return if latest_date.blank?

    latest_ratios = ratios.where(end_date: latest_date).group_by(&:name)
    return if latest_ratios.blank?

    charts = []

    # Fund Utilization
    util_ratio = latest_ratios["Fund Utilization"]&.first
    if util_ratio
      util = util_ratio.value.to_f
      data = { "Utilized" => util, "Remaining" => [100.0 - util, 0].max }
      charts << content_tag(:div, class: "col-md-6 mb-4") do
        content_tag(:div, class: "card shadow h-100") do
          content_tag(:div, class: "card-body") do
            pie_chart_with_options(data, title: "Fund Utilization (%)", id: "fund_utilization_chart_#{fund.id}", descending: false)
          end
        end
      end
    end

    return if charts.empty?

    content_tag(:div, class: "row") do
      charts.join.html_safe
    end
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

    pie_chart_with_options grouped, id: "fund_commitment_amounts_chart_#{fund.id}"
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

    pie_chart_with_options grouped, id: "fund_commitments_collected_chart_#{fund.id}"
  end

  def quarter(date)
    ((date.month - 1) / 3) + 1
  end

  def fund_commitments_collected_by_quarter(fund)
    capital_calls = fund.capital_calls.where("due_date > ?", Time.zone.today - 1.year)
    capital_calls = capital_calls.group_by { |cc| "Q#{quarter(cc.due_date)}" }
                                 .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.collected_amount_cents / 100) }] }

    column_chart capital_calls, id: "fund_commitments_collected_by_quarter_chart_#{fund.id}", library: {
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

    column_chart capital_distributions, id: "fund_distributions_by_quarter_chart_#{fund.id}", library: {
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
