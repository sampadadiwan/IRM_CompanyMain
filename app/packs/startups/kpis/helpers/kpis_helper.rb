module KpisHelper
  def multiple_entity_kpi_lines_by_date(kpis, id: nil, investor_kpi_mappings: nil)
    dates = KpiReport.where(id: kpis.pluck(:kpi_report_id)).order(as_of: :asc).pluck(:as_of).uniq
    grouped_kpis = kpis.includes(:kpi_report, :entity, :owner).group_by { |k| [k.entity, k.owner, k.kpi_report.tag_list] }

    data_map = []
    grouped_kpis.each do |key, entity_kpis|
      entity, owner, tags = key
      entity_kpis.group_by(&:name).each_value do |kpis_by_name|
        standard_kpi = get_standard_kpi_name(investor_kpi_mappings, kpis_by_name.first)
        data = []
        dates.each do |date|
          kpi = kpis_by_name.find { |k| k.kpi_report.as_of == date }
          data << [date.strftime("%m/%y"), kpi&.value]
        end

        label = owner&.name || entity.name
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
      mapping = investor_kpi_mappings[[kpi.entity_id, kpi&.name]]
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
    kpi_reports = portfolio_company.portfolio_kpi_reports.where(as_of: ..end_date).order(as_of: :asc)
    investor_kpi_mappings = portfolio_company.investor_kpi_mappings

    # Generate headers as OpenStruct with index keys
    header_data = { "val_0" => 'KPI' }
    kpi_reports.each_with_index do |kr, index|
      header_data["val_#{index + 1}"] = "#{I18n.l(kr.as_of)} #{kr.tag_list}"
    end
    headers = [OpenStruct.new(header_data)]

    # Generate rows as OpenStructs with index keys
    rows = investor_kpi_mappings.map do |ikm|
      row_data = { "val_0" => ikm.standard_kpi_name } # First column is the KPI name

      kpi_reports.each_with_index do |kr, index|
        kpi_hash = kr.kpis.index_by { |kpi| kpi.name.downcase }
        kpi = kpi_hash[ikm.reported_kpi_name.downcase]

        row_data["val_#{index + 1}"] = kpi ? number_with_delimiter(kpi.value.round(2)) : "N/A"
      end

      OpenStruct.new(row_data)
    end

    headers + rows
  end
end
