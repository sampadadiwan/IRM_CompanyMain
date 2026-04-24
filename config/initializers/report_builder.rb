Rails.application.config.to_prepare do
  ReportBuilderModelDiscovery.reset_cache!
end
