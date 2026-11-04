Rails.application.config.to_prepare do
  ReportBuilderModelDiscovery.reset_cache!
  ReportBuilderColumnCatalog.reset_cache!
  ReportBuilderTemplates.reset!
end
