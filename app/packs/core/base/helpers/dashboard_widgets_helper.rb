module DashboardWidgetsHelper
  def dashboard_widgets(dashboard_name, entity_id, name: "Default", owner: nil)
    # These are the available widgets for the dashboard_name
    available_widgets = DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)
    # Fetch the enabled widgets for the dashboard_name
    widgets = DashboardWidget.enabled.where(dashboard_name:, name:, entity_id:)
    # Apply owner filter if provided
    widgets = widgets.where(owner: owner) if owner
    if widgets.empty?
      # Return the available widgets if there are no custom widgets
      DashboardWidget::WIDGETS[dashboard_name].index_by(&:widget_name)
    else
      # Return the custom widgets defined by the user
      dashboard_widgets = []
      widgets.order(:position).each do |widget|
        if available_widgets[widget.widget_name]
          widget.path = available_widgets[widget.widget_name].path
          dashboard_widgets << ["#{widget.widget_name} #{widget.tags}", widget]
        else
          Rails.logger.debug { "Widget #{widget.widget_name} not found in available widgets for #{dashboard_name}" }
        end
      end

      dashboard_widgets.to_h
    end
  end

  def report_url(dashboard_name, report)
    case dashboard_name
    when "Portfolio Company Dashboard"
      dynamic_report_path(report, portfolio_company_name: @investor.investor_name, investor_name: @investor.investor_name)
    else
      report_path(report)
    end
  end
end
