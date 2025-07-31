class ChangeWidgetNames < ActiveRecord::Migration[8.0]
  def change
    DashboardWidget.where(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Company Fund Ratios").update_all(widget_name: "Fund Ratios")
    DashboardWidget.where(dashboard_name: "Portfolio Company Dashboard", widget_name: "Portfolio Company KPIs").update_all(widget_name: "Kpis")
    DashboardWidget.where(dashboard_name: "Portfolio Company Dashboard", widget_name: "Key KPIs").update_all(widget_name: "Key Kpis")
  end
end
