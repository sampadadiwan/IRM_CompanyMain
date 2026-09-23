# frozen_string_literal: true

# Adds FX conversion method to investor_kpi_mappings for KPI currency conversion.
# @see InvestorKpiMapping
class AddFxConversionMethodToInvestorKpiMappings < ActiveRecord::Migration[8.1]

  def change
    add_column :investor_kpi_mappings, :fx_conversion_method, :string, limit: 20, default: 'not_applicable', null: false
  end
end
