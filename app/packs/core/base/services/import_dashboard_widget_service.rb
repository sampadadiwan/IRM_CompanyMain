class ImportDashboardWidgetService < ImportServiceBase
  step :read_file
  step Subprocess(ImportDashboardWidget)
  step :save_results_file
end
