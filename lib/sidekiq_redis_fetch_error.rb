# frozen_string_literal: true

# Classifies exceptions arriving at the Sidekiq error handler registered in
# config/initializers/exception_notification.rb.
#
# Sidekiq's error_handlers chain is not a job-failure chain. Sidekiq's own BRPOP
# poll loop reports Redis failures through it too: Processor#get_one rescues into
# #handle_fetch_exception, which calls handle_exception(ex) with NO context, sleeps
# a second and goes straight back to polling. So a Redis blip that Sidekiq had
# already recovered from arrived at the handler looking exactly like a failed job
# and was emailed as a production error, carrying no job, no arguments and no
# request. See docs/incidents/2026-08-14-2d7eca43-sidekiq-redis-fetch-timeout.md.
#
# Those fetch-loop failures are counted for Prometheus instead of emailed. The
# count is what makes suppressing the email safe rather than blind: Sidekiq notifies
# once per processor thread per downtime episode (the @down flag in Processor), so an
# isolated stall increments the counter once or twice, while a genuine Redis outage
# trips every thread of every capsule on every app server within seconds. The
# "Sidekiq Cannot Reach Redis" rule in observability/grafana_provision.yml thresholds
# on precisely that difference.
module SidekiqRedisFetchError
  # Only failures raised inside Sidekiq's own fetcher qualify. A Redis timeout raised
  # by application code has a different backtrace and keeps emailing, because nothing
  # else is going to retry it.
  FETCH_LOOP_FRAME = %r{sidekiq/fetch\.rb}

  class << self
    # True when this exception should be counted instead of emailed. Recording is a
    # side effect of the predicate on purpose: a caller cannot suppress the email
    # without also emitting the metric that replaces it.
    def suppress?(exception, context)
      return false unless fetch_loop_failure?(exception, context)

      record(exception)
      true
    rescue StandardError, ScriptError => e
      # Fail open on our own bugs too. Anything raised here propagates into Sidekiq's
      # error_handlers chain, which aborts the whole chain and drops the report — so a
      # crash in the classifier would silently stop production alerting rather than
      # merely misclassify one exception. ScriptError covers LoadError/NotImplementedError,
      # neither of which is a StandardError.
      Sidekiq.logger.error("[SidekiqRedisFetchError] classification failed, not suppressing: #{e.class}: #{e.message}") if defined?(Sidekiq)
      false
    end

    # Every condition below fails OPEN — anything we cannot positively identify as a
    # self-healing fetch-loop blip still gets emailed.
    def fetch_loop_failure?(exception, context)
      # ConnectionError is the transient family: read/write timeouts, checkout timeout
      # and cannot-connect all descend from it. A CommandError (bad command, OOM, wrong
      # type) does not and is never suppressed.
      return false unless defined?(RedisClient::ConnectionError)
      return false unless exception.is_a?(RedisClient::ConnectionError)

      # In Sidekiq 8.1.6 the fetch loop is the only handle_exception call site that
      # passes an empty context. Job failures carry :job/:jobstr, lifecycle, watchdog
      # and retry-scheduling failures carry :context — all of them name something a
      # human can act on, so all of them are left alone.
      return false unless empty_context?(context)

      # With no backtrace we cannot prove where it came from, so `any?` on an empty
      # array correctly refuses to suppress.
      Array(exception.backtrace).any? { |frame| frame.match?(FETCH_LOOP_FRAME) }
    end

    private

    def empty_context?(context)
      context.nil? || (context.respond_to?(:empty?) && context.empty?)
    end

    # Metrics and logging must never swallow an error report, hence rescue-all.
    def record(exception)
      Sidekiq.logger.warn("[SidekiqRedisFetchError] #{exception.class}: #{exception.message} — Sidekiq is retrying the fetch, not emailing") if defined?(Sidekiq)
      counter&.observe(1, error_class: exception.class.name)
    rescue StandardError
      nil
    end

    # Registered lazily so this module can load before PrometheusExporter's client
    # exists. The exporter applies the global "ruby_" prefix, so this is scraped as
    # ruby_sidekiq_redis_fetch_errors — same convention as the counters in
    # config/initializers/sidekiq.rb.
    def counter
      # prometheus_exporter is not started under test (see initializers/prometheus.rb),
      # and registering here would open a client socket the test run has no server for.
      return nil if Rails.env.test? || !defined?(PrometheusExporter::Client)

      @counter ||= PrometheusExporter::Client.default.register(
        :counter, 'sidekiq_redis_fetch_errors',
        'Transient Redis failures inside the Sidekiq fetch loop, suppressed from email alerting'
      )
    end
  end
end
