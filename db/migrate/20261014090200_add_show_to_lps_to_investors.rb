# The company-level "Show to LPs" switch that replaces the per-holding Show Portfolio flag. Only meaningful for
# portfolio companies; read by primary key on each LP company render, so no index.
# openspec/changes/lp-folio-portfolio-dashboard/design.md#data-model-and-schema-changes (H9)
class AddShowToLpsToInvestors < ActiveRecord::Migration[8.1]
  def change
    add_column :investors, :show_to_lps, :boolean, default: false, null: false
  end
end
