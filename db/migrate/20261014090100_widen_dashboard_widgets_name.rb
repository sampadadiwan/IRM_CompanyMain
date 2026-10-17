# Layout names now carry company tags ("LP, FinTech", "LP, Enterprise Infrastructure - Software"), so the layout
# name outgrows 20 characters. ~300 rows; instant.
# openspec/changes/lp-folio-portfolio-dashboard/design.md#data-model-and-schema-changes (E89)
class WidenDashboardWidgetsName < ActiveRecord::Migration[8.1]
  def up
    change_column :dashboard_widgets, :name, :string, limit: 100, default: "Default"
  end

  def down
    change_column :dashboard_widgets, :name, :string, limit: 20, default: "Default"
  end
end
