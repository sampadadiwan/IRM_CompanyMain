module KpisHelper
  # Builds the Highcharts-compatible data array for the chart switcher.
  #
  # Returns an array of series hashes:
  #   [{ name: "Company - Tag - KPI Name", data: [["01/03/2024", 1.5], ...] }, ...]
  #
  # Each series corresponds to one unique (portfolio_company, entity, tag, kpi_name) combination.
  # Values are cast to Float so JSON serialises them as numbers (not BigDecimal strings).
  def build_kpi_chart_data(kpis, investor_kpi_mappings: nil, date_format: :month_year)
    dates = kpi_chart_dates(kpis)
    date_labels = dates.index_by { |d| d }.transform_values { |d| date_with_ordinal(d, format: date_format) }

    loaded_kpis = kpis.includes(:kpi_report, :entity, :owner, :portfolio_company)
    grouped_kpis = loaded_kpis.group_by { |k| [k.portfolio_company_id, k.entity_id, k.kpi_report.tag_list] }
    single_company = grouped_kpis.keys.filter_map(&:first).uniq.one?

    grouped_kpis.flat_map do |(_portfolio_company_id, _entity_id, tags), group_kpis|
      portfolio_company = group_kpis.first.portfolio_company
      entity            = group_kpis.first.entity
      series_prefix     = kpi_chart_series_prefix(portfolio_company, entity, tags, single_company)

      group_kpis.group_by(&:name).map do |_name, kpis_by_name|
        standard_kpi = get_standard_kpi_name(investor_kpi_mappings, kpis_by_name.first)
        full_name    = series_prefix.present? ? "#{series_prefix} - #{standard_kpi}" : standard_kpi

        {
          name: full_name,
          data: kpi_chart_series_data(kpis_by_name, dates, date_labels)
        }
      end
    end
  end

  # ── Private chart-data helpers ───────────────────────────────────────────

  # Returns unique, ascending dates that have KPI data in the given scope.
  def kpi_chart_dates(kpis)
    KpiReport.where(id: kpis.unscope(:order).pluck("kpis.kpi_report_id")).order(as_of: :asc).pluck(:as_of).uniq
  end

  # Builds the "[Company] - [Tags]" prefix for a chart series name.
  # Returns an empty string when there is only one portfolio company (no disambiguation needed).
  def kpi_chart_series_prefix(portfolio_company, entity, tags, single_company)
    label = single_company ? "" : (portfolio_company&.investor_name || entity&.name || "")
    label += " - " if label.present? && tags.present?
    label += tags  if tags.present?
    label
  end

  # Builds the [[date_label, float_value], ...] data array for a single KPI series.
  # Uses a hash lookup (O(1) per date) instead of Array#find (O(n) per date).
  def kpi_chart_series_data(kpis_by_name, dates, date_labels)
    # Index kpis by their report date for fast lookup
    kpis_by_date = kpis_by_name.index_by { |k| k.kpi_report.as_of }
    dates.map do |date|
      kpi = kpis_by_date[date]
      # Cast to Float: BigDecimal#to_json outputs a quoted string ("0.3e5"),
      # which Highcharts cannot plot as a numeric data point.
      [date_labels[date], kpi&.value&.to_f]
    end
  end

  def multiple_entity_kpi_lines_by_date(kpis, id: nil, investor_kpi_mappings: nil, date_format: :month_year)
    data_map = build_kpi_chart_data(kpis, investor_kpi_mappings:, date_format:)

    line_chart data_map, id:, library: {
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

  def flexible_kpi_chart(kpis, id: nil, investor_kpi_mappings: nil, chart_config: [], date_format: :month_year)
    data_map = build_kpi_chart_data(kpis, investor_kpi_mappings: investor_kpi_mappings, date_format: date_format)

    # Convert chart_config to an array if it's a hash
    config_array = chart_config.is_a?(Hash) || chart_config.respond_to?(:values) ? chart_config.values : chart_config

    # Sort configs by name length descending to match more specific names first
    sorted_configs = config_array.sort_by { |c| (c["name"] || c[:name]).to_s.length }.reverse

    # Apply custom types from chart_config
    data_map.each do |series|
      series_name = series[:name].to_s.downcase

      # Robust matching: look for the config that matches this series name
      config = sorted_configs.find do |c|
        c_name = (c["name"] || c[:name]).to_s.downcase
        series_name == c_name ||
          series_name.include?(" - #{c_name}") ||
          series_name.end_with?(" - #{c_name}")
      end

      if config
        assigned_type = config["type"] || config[:type]
        Rails.logger.debug { "KPI Chart: Matching series '#{series[:name]}' with config type '#{assigned_type}'" }

        series[:type] = assigned_type
        series[:type] = "column" if series[:type] == "bar"
        series[:type] = "pie" if series[:type] == "donut"
        series[:innerSize] = "50%" if assigned_type == "donut"

        if series[:type] == "line"
          series[:marker] = { enabled: true, radius: 4 }
          series[:lineWidth] = 2
        end
        Rails.logger.debug { "KPI Chart: Series '#{series[:name]}' data count: #{series[:data].count}" }
      else
        series[:type] = "column"
        Rails.logger.debug { "KPI Chart: No config found for series '#{series[:name]}', using default column" }
      end
    end

    line_chart data_map, id: id, library: {
      plotOptions: {
        column: { pointWidth: 40 },
        series: { dataLabels: { enabled: false } }
      },
      **chart_theme_color
    }
  end

  def display_kpi(kpi, investor_kpi_mapping, params: {})
    return if kpi.value.blank?

    decimals = params[:decimals]&.to_i || 2
    result = number_with_precision(kpi.value, precision: decimals, delimiter: ',')
    percentage_value = (kpi.value * 100).round(decimals)

    if investor_kpi_mapping.present?
      case investor_kpi_mapping.data_type
      when "money"
        result = if params[:units].present?
                   money_to_currency(kpi.value, params)
                 else
                   money_to_currency(kpi.value, params, true)
                 end
      when "percentage"
        result = "#{percentage_value} %"
      end
    end
    result
  end

  def kpi_percentage_class(kpi, investor_kpi_mapping)
    css_class = if  investor_kpi_mapping&.lower_threshold&.positive? &&
                    kpi.percentage_change < investor_kpi_mapping.lower_threshold
                  "text-danger"
                elsif investor_kpi_mapping&.upper_threshold&.positive? &&
                      kpi.percentage_change > investor_kpi_mapping.upper_threshold
                  "text-success"
                end
    percentage_change_display_val = kpi.percentage_change.nil? ? "-" : "#{kpi.percentage_change} %"

    "<small class='fs-1 #{css_class}'> #{percentage_change_display_val}</small>"
  end

  def get_investor_kpi_mapping(investor_kpi_mappings, kpi)
    if investor_kpi_mappings
      mapping = investor_kpi_mappings[[kpi.portfolio_company_id, kpi&.name]]
      mapping.present? ? mapping[0] : nil
    end
  end

  def get_standard_kpi_name(investor_kpi_mappings, kpi)
    if investor_kpi_mappings
      # Use portfolio_company_id as the primary lookup key to match mapping.investor_id
      mapping = investor_kpi_mappings[[kpi.portfolio_company_id, kpi&.name&.downcase]]
      mapping.present? ? mapping[0].standard_kpi_name : kpi&.name
    else
      kpi&.name
    end
  end

  include ActionView::Helpers::NumberHelper

  def grid_view_array(portfolio_company, end_date)
    kpi_reports = portfolio_company.portfolio_kpi_reports
                                   .where(as_of: ..end_date)
                                   .order(:as_of)

    investor_kpi_mappings = portfolio_company.investor_kpi_mappings

    header_data = { "val_0" => "KPI" }
    kpi_reports.each_with_index do |kr, i|
      header_data["val_#{i + 1}"] = "#{I18n.l(kr.as_of)} #{kr.tag_list}"
    end
    headers = [OpenStruct.new(header_data)]

    rows = investor_kpi_mappings.map do |ikm|
      row_data = { "val_0" => ikm.standard_kpi_name }

      kpi_reports.each_with_index do |kr, i|
        kpi = kr.kpis.find { |k| k.name.casecmp?(ikm.standard_kpi_name) }
        row_data["val_#{i + 1}"] = kpi ? number_with_delimiter(kpi.value.round(2)) : "N/A"
      end

      OpenStruct.new(row_data)
    end

    headers + rows
  end

  def tag_badge_class(tag)
    case tag.to_s.strip.downcase
    when "actual"    then "bg-primary-subtle text-primary badge-tag-actual"
    when "projected" then "bg-info-subtle text-info badge-tag-projected"
    when /^ic /      then "bg-warning-subtle text-warning badge-tag-ic-case"
    when /^audited/  then "bg-danger-subtle text-danger badge-tag-audited"
    when "budget"    then "bg-success-subtle text-success badge-tag-budget"
    else                  "bg-secondary-subtle text-secondary badge-tag-other"
    end
  end

  def set_investor_kpi_mappings(kpi_reports, investor, current_user, category: nil)
    mappings = if ["Investment Fund", "Angel Fund"].include? current_user.entity.entity_type
                 investor&.investor_kpi_mappings || []
               else
                 Kpi.where(kpi_report_id: kpi_reports.unscope(:order).pluck("kpi_reports.id")).pluck(:name).uniq.map do |kpi_name|
                   InvestorKpiMapping.new(standard_kpi_name: kpi_name, reported_kpi_name: kpi_name, category: "General")
                 end
               end

    mappings = mappings.select { |ikm| ikm.category == category } if category.present?
    mappings
  end
end
