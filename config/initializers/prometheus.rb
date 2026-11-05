# Per-process YJIT gauges, for the YJIT row on the Rails Metrics dashboard and the YJIT alert
# rules (config/initializers/observability/grafana_provision.yml). prometheus_exporter has no
# YJIT collector, so these are remote gauges, shipped the same way as SidekiqJobMemoryMetrics'
# counters (config/initializers/sidekiq.rb); the exporter prefixes them ruby_ (ruby_yjit_enabled).
#
# Labelled by type and puma worker index, never by pid: the exporter keeps a remote gauge's last
# value until it is overwritten, so a pid label would leave a stale series behind on every restart.
class YjitMetrics
  FREQUENCY = 30 # seconds — the same cadence as PrometheusExporter::Instrumentation::Process

  HELP = {
    enabled: 'YJIT is running in this process (1) or not (0)',
    expected: 'config.yjit asks for YJIT in this environment (1) or not (0)',
    code_region_bytes: 'Machine code YJIT has generated (runtime_stats code_region_size)',
    alloc_bytes: "YJIT's own bookkeeping memory (runtime_stats yjit_alloc_size)",
    compiled_iseq_count: 'Methods and blocks YJIT has compiled so far',
    invalidation_count: 'Times compiled code was discarded because an assumption it made changed',
    compilation_failure: 'Failed compilations — these rise once YJIT reaches its memory limit'
  }.freeze

  class << self
    # One reporting thread per process; labels identify the process (type, and worker for puma)
    def start(labels)
      Thread.new do
        Thread.current.name = 'yjit-metrics'
        loop do
          report(labels)
          sleep FREQUENCY
        end
      end
    end

    # RubyVM::YJIT does not exist at all on a Ruby built without YJIT, and runtime_stats is nil
    # while YJIT is off — in both cases only enabled/expected are sent.
    def snapshot
      enabled = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      values = { enabled: enabled ? 1 : 0, expected: Rails.application.config.yjit ? 1 : 0 }
      return values unless enabled

      stats = RubyVM::YJIT.runtime_stats
      values.merge(code_region_bytes: stats[:code_region_size], alloc_bytes: stats[:yjit_alloc_size],
                   compiled_iseq_count: stats[:compiled_iseq_count], invalidation_count: stats[:invalidation_count],
                   compilation_failure: stats[:compilation_failure])
    end

    def report(labels)
      snapshot.each { |name, value| gauge(name).observe(value, labels) unless value.nil? }
    rescue StandardError => e
      # Metrics must never take a worker or Sidekiq down
      Rails.logger.warn("YjitMetrics: #{e.class}: #{e.message}")
    end

    private

    # Registered lazily so this class can load before PrometheusExporter's client exists
    def gauge(name)
      @gauges ||= {}
      @gauges[name] ||= PrometheusExporter::Client.default.register(:gauge, "yjit_#{name}", HELP.fetch(name))
    end
  end
end

unless Rails.env.test?

  require 'prometheus_exporter/middleware'
  require 'prometheus_exporter/instrumentation'

  # This reports basic process stats like RSS and GC times
  PrometheusExporter::Instrumentation::Process.start(type: 'web')

  # Use middleware to measure request durations
  Rails.application.middleware.use PrometheusExporter::Middleware

  PrometheusExporter::Instrumentation::ActiveRecord.start if defined?(ActiveRecord)

  # Puma workers. With preload_app! (config/deploy/templates/puma.rb.erb) this file runs once, in
  # the puma master, and the Process reporter above is a thread — threads do not survive fork, so
  # no worker ever reported its own memory: ruby_rss{type="puma_worker"}, which the "Web Worker
  # Memory" alert watches, did not exist, and type="web" was the master alone. Hooked here rather
  # than in puma.rb because shared/puma.rb is only re-uploaded by IRM:setup, while this ships with
  # every deploy.
  ActiveSupport::ForkTracker.after_fork do
    Thread.new do
      # Puma titles the worker ("puma: cluster worker 2: <master pid> [...]") only after the fork
      # hooks have run, so wait for the title; any fork that is not a puma worker is left alone.
      index = nil
      30.times do
        break if (index = $PROGRAM_NAME[/\Apuma: cluster worker (\d+):/, 1])

        sleep 1
      end
      next unless index

      PrometheusExporter::Instrumentation::Process.start(type: 'puma_worker', labels: { worker: index })
      YjitMetrics.start(type: 'puma_worker', worker: index)
    end
  end

end
