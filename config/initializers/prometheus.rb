unless Rails.env.test?

  require 'prometheus_exporter/middleware'
  require 'prometheus_exporter/instrumentation'

  # This reports basic process stats like RSS and GC times
  PrometheusExporter::Instrumentation::Process.start(type: 'web')

  # Use middleware to measure request durations
  Rails.application.middleware.use PrometheusExporter::Middleware

  PrometheusExporter::Instrumentation::ActiveRecord.start if defined?(ActiveRecord)

end
