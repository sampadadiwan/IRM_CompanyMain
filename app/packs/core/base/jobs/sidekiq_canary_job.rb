# Proves Sidekiq is PROCESSING jobs, not merely alive. sidekiq-cron enqueues it
# every minute (config/initializers/sidekiq.rb) and each run records the time it
# ran; the "Sidekiq Canary Stale" rule in observability/grafana_provision.yml
# fires when that time falls behind.
#
# Why "Sidekiq Down" is not enough: it checks that some Sidekiq on each host is
# pushing process metrics, and that metrics thread keeps running whether or not
# the process fetches jobs — a worker stuck shutting down, wedged, or running from
# a deleted release still counts as up. That is how a post-deploy duplicate-worker
# state sat unalerted while no jobs ran. The canary only advances if a job was
# actually fetched and executed. (It cannot catch a Sidekiq pointed at the wrong
# Redis: sidekiq-cron would enqueue the canary into that same Redis.)
#
# On its own single-thread capsule (config/initializers/sidekiq.rb) so it
# measures whether Sidekiq is processing at all, never whether the shared
# threads happen to be busy: queue priority alone cannot free a thread that five
# long jobs already hold. Backlog is the "Sidekiq Queue Latency Critical" alert's
# job.
class SidekiqCanaryJob < ApplicationJob
  queue_as :canary

  def perform
    self.class.last_run_gauge&.observe(Time.now.to_i)
  end

  # Registered lazily so the class can load before PrometheusExporter's client
  # exists. The exporter applies the global "ruby_" prefix, so this is scraped as
  # ruby_sidekiq_canary_last_run_timestamp_seconds — same convention as the
  # counters in config/initializers/sidekiq.rb.
  def self.last_run_gauge
    # prometheus_exporter is not started under test (see initializers/prometheus.rb).
    return nil if Rails.env.test? || !defined?(PrometheusExporter::Client)

    @last_run_gauge ||= PrometheusExporter::Client.default.register(
      :gauge, 'sidekiq_canary_last_run_timestamp_seconds',
      'Unix time the Sidekiq canary job last ran; stale means no jobs are being processed'
    )
  end
end
