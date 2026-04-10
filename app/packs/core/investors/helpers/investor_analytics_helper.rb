module InvestorAnalyticsHelper
  # Renders a donut chart showing the distribution of investors by category.
  # Clickable: Filters the table by category.
  def investor_category_distribution_chart(records)
    data = records.group(:category).count

    pie_chart data, donut: true, title: "Investor Category Distribution", id: "investor_category_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[category_eq]")
    }
  end

  # Renders a donut chart showing the top 10 cities where investors are located.
  # Clickable: Filters the table by city.
  def investor_city_distribution_chart(records)
    data = records.where.not(city: [nil, ""]).group(:city).count.sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Top 10 Cities", id: "investor_city_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[city_eq]")
    }
  end

  # Renders a donut chart showing the distribution of the top 10 tags.
  # Processes the comma-separated tag_list field.
  # Clickable: Filters the table by tag (contains).
  def investor_tag_distribution_chart(records)
    # Extract and count individual tags from the comma-separated tag_list
    all_tags = records.pluck(:tag_list).compact.flat_map { |list| list.split(",").map(&:strip) }.compact_blank
    data = all_tags.group_by(&:itself).transform_values(&:count).sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Top 10 Tags", id: "investor_tag_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[tag_list_cont]")
    }
  end

  # Renders a donut chart showing sector distribution for Portfolio Companies.
  # Clickable: Filters the table by sector (contains).
  def investor_sector_distribution_chart(records)
    # Filter for Portfolio Companies and non-empty sectors
    data = records.where(category: "Portfolio Company").where.not(sector: [nil, ""]).group(:sector).count.sort_by { |_k, v| -v }.first(10).to_h

    pie_chart data, donut: true, title: "Sector Distribution (Portfolio Companies)", id: "investor_sector_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[sector_cont]")
    }
  end
end
