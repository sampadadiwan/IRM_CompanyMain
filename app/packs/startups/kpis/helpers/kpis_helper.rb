module KpisHelper
  def multiple_entity_kpi_lines_by_date(kpis, id: nil, investor_kpi_mappings: nil)
    dates = KpiReport.where(id: kpis.pluck(:kpi_report_id)).order(as_of: :asc).pluck(:as_of).uniq
    grouped_kpis = kpis.includes(:kpi_report, :entity, :owner, :portfolio_company).group_by { |k| [k.portfolio_company, k.entity, k.kpi_report.tag_list] }

    data_map = []
    grouped_kpis.each do |key, portfolio_company_kpis|
      portfolio_company, entity, tags = key
      portfolio_company_kpis.group_by(&:name).each_value do |kpis_by_name|
        standard_kpi = get_standard_kpi_name(investor_kpi_mappings, kpis_by_name.first)
        data = []
        dates.each do |date|
          kpi = kpis_by_name.find { |k| k.kpi_report.as_of == date }
          data << [date.strftime("%m/%y"), kpi&.value]
        end

        label = portfolio_company&.investor_name || entity.name
        label += " - #{tags}" if tags.present?

        data_map << { name: "#{label} - #{standard_kpi}", data: }
      end
    end

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

  def display_kpi(kpi, investor_kpi_mapping, params: {})
    return if kpi.value.blank?

    number_with_delimiter(kpi.value.round(1))
    percentage_value = (kpi.value.round(4) * 100)

    if investor_kpi_mapping.present?
      case investor_kpi_mapping.data_type
      when "money"
        result = params[:units].present? && params[:units] == "Common" ? kpi.common_size_value : money_to_currency(kpi.value, params)
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

    "<small class='fs-1 #{css_class}'> #{kpi.percentage_change} %</small>"
  end

  def get_invester_kpi_mapping(investor_kpi_mappings, kpi)
    if investor_kpi_mappings
      mapping = investor_kpi_mappings[[kpi.portfolio_company_id, kpi&.name]]
      mapping.present? ? mapping[0] : nil
    end
  end

  def get_standard_kpi_name(investor_kpi_mappings, kpi)
    if investor_kpi_mappings
      mapping = investor_kpi_mappings[[kpi.entity_id, kpi&.name]]
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

    # Build header row
    header_data = { "val_0" => "KPI" }
    kpi_reports.each_with_index do |kr, i|
      header_data["val_#{i + 1}"] = "#{I18n.l(kr.as_of)} #{kr.tag_list}"
    end
    headers = [OpenStruct.new(header_data)]

    # Build data rows
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
end
