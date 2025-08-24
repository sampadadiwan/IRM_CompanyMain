class AddInvestorKpiMappingToKpis < ActiveRecord::Migration[8.0]
  def change
    add_reference :kpis, :investor_kpi_mapping, null: true, foreign_key: true

    Kpi.all.each do |kpi|
      # Assuming that the investor_kpi_mapping can be derived from the kpi's name or some other attribute
      if kpi.portfolio_company.present?
        mapping = kpi.portfolio_company.investor_kpi_mappings.find_by(standard_kpi_name: kpi.name)
        if mapping
          kpi.update_column(:investor_kpi_mapping_id, mapping.id)
        else
          Rails.logger.warn "No InvestorKpiMapping found for KPI #{kpi.name}"
        end
      end
    end
  end
end
