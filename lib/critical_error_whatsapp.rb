# frozen_string_literal: true

require_relative 'ops_whatsapp_alert'

# WhatsApp page for infrastructure-class exceptions (database, Redis, disk). Design and
# rationale: docs/operations/critical_error_whatsapp_alerts.md.
#
# Why this exists: on 2026-09-27 the DB host's disk filled up and Redis went down with it.
# The app emailed ~1000 identical "Mysql2::Error: Error writing file '/tmp/...'
# (Errcode: 28)" errors, while Grafana's WhatsApp path (webhook -> ALB/WAF ->
# /grafana/alert -> WATI) was refused with a 403 at the WAF, so nobody was paged. This
# pages from inside the process that saw the error, straight to WATI over HTTPS, and
# depends on nothing that sits on the DB host:
#
# - no Sidekiq job (Redis may be down), a plain thread instead;
# - no Rails.cache for throttling (it is solid_cache_store, i.e. MySQL), no Redis —
#   throttle state is per-process memory. One incident therefore pages once per process
#   rather than once in total. Deliberate: a few duplicates beat a throttle that fails
#   together with the DB.
#
# It covers "the app is up but its dependencies are broken". A dead app server raises
# nothing and pages nothing — that still needs an outside check.
module CriticalErrorWhatsapp
  # One page per distinct error per process per window.
  THROTTLE_WINDOW = 30.minutes
  # Hard cap per process per window across all errors — a cascade of different
  # messages (DB, then pool timeouts, then Redis) must not flood the phones either.
  MAX_PER_WINDOW = 5

  # Sidekiq's fetch loop reports a Redis failure once per processor thread per outage
  # (the @down flag in Sidekiq::Processor), so every thread reports within the first
  # second of a blip and then goes quiet however long the outage lasts. Counting reports
  # cannot tell a blip from an outage; asking Redis again a minute later can.
  REDIS_RECHECK_AFTER = 60.seconds

  # Matched by name so an adapter that is not loaded (redis vs redis-client) is simply
  # skipped rather than raising NameError.
  #
  # Redis *timeouts* (RedisClient::ReadTimeoutError and friends, all subclasses of
  # RedisClient::ConnectionError) are deliberately absent: they usually heal on their own
  # and are the blips SidekiqRedisFetchError exists to keep quiet. Refused connections page.
  CRITICAL_CLASSES = %w[
    ActiveRecord::ConnectionNotEstablished
    Mysql2::Error::ConnectionError
    RedisClient::CannotConnectError
    Redis::CannotConnectError
    Errno::ENOSPC
    Errno::EMFILE
  ].freeze

  # Rails wraps every MySQL error in ActiveRecord::StatementInvalid, whether the disk is
  # full or a column name is wrong, so for those only the message tells them apart.
  CRITICAL_MESSAGES = Regexp.union(
    /No space left on device/i,
    /Errcode: 28/,
    /Got error 28 from storage engine/i,
    /Error writing file/i,
    # MySQL's usual symptom of its tmpdir filling mid-query (the internal temp table's
    # file is truncated), alongside real index corruption — both need a human.
    /Incorrect key file for table/i,
    /The table '[^']*' is full/i,
    /MySQL server has gone away/i,
    /Lost connection to MySQL server/i,
    /Can't connect to (local )?MySQL server/i,
    /Too many connections/i,
    /running with the --read-only option/i
  )

  # The messages above are only trusted on these classes: "Too many connections" or
  # "Error writing file" from an SMTP server or a PDF converter is not a database outage.
  MESSAGE_CHECKED_CLASSES = %w[Mysql2::Error ActiveRecord::ActiveRecordError].freeze

  # A Redis whose disk is full does not refuse connections — it stays up and answers
  # writes with an error reply (RedisClient::CommandError), which the class list above
  # would never see. These prefixes are Redis saying the server itself cannot serve:
  # MISCONF (cannot persist, e.g. disk full), OOM (maxmemory), READONLY (replica or
  # failover), LOADING (restarting and reading its dataset).
  REDIS_CRITICAL_MESSAGES = /\A(MISCONF|OOM|READONLY|LOADING)\b/
  REDIS_COMMAND_ERROR_CLASSES = %w[RedisClient::CommandError Redis::CommandError].freeze

  CAUSE_DEPTH = 5

  MUTEX = Mutex.new

  # Prepended onto ExceptionNotifier's singleton so the pager sees every reported error
  # BEFORE email grouping decides anything. As a regular notifier it would only run on
  # the occurrences grouping lets through (1, 2, 4, 8...), so a 1000-errors-an-hour
  # outage would page a second time at occurrence 1024, hours later.
  module NotifyHook
    def notify_exception(exception, options = {}, &)
      CriticalErrorWhatsapp.call(exception, options)
      CriticalErrorWhatsapp.enforce_grouping_cache!
      super
    end
  end

  # Email grouping counters, per process. Deliberately not Rails.cache: that is
  # solid_cache_store, i.e. MySQL — during a DB outage its reads fail (every error then
  # counts as the first and emails) and its writes can block on a full disk.
  GROUPING_CACHE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)

  class << self
    # Test seams: enabled overrides the production-only guard, async: false runs inline,
    # transport replaces the WATI call (callable taking phones, message and returning an
    # OpsWhatsappAlert::Result), phones replaces the credentials lookup, redis_probe
    # replaces the Redis PING and redis_recheck_after the 60 s wait.
    attr_writer :async, :enabled, :transport, :phones, :redis_probe, :redis_recheck_after

    def install!
      ExceptionNotifier.singleton_class.prepend(NotifyHook) unless ExceptionNotifier.singleton_class < NotifyHook
      enforce_grouping_cache!
    end

    # Re-asserted before every notification rather than set once: each
    # ExceptionNotification::Rack.new (exception_notification 5.0.1, rack.rb:18) resets
    # error_grouping_cache to Rails.cache unless given one, and the gem's Engine adds that
    # middleware with no options. Relying on boot order (after_initialize runs after the
    # stack is built) held only until something rebuilt the middleware — then every
    # occurrence counted as the first and the email flood was back.
    def enforce_grouping_cache!
      ExceptionNotifier.error_grouping_cache = GROUPING_CACHE unless ExceptionNotifier.error_grouping_cache.equal?(GROUPING_CACHE)
    end

    # exception_notification's grouping trigger. Only critical errors are grouped (emailed
    # on their 1st, 2nd, 4th, 8th... occurrence); everything else emails every time, as it
    # did before grouping was enabled. The gem keys groups by class + first backtrace line,
    # so grouping ordinary errors would merge different SQL bugs (all raised from one
    # adapter line) and every never-raised health-check exception (no backtrace at all).
    def notification_trigger
      lambda do |exception, count|
        next true unless critical_exception(exception)

        factor = Math.log2(count)
        factor.to_i == factor
      end
    end

    # Pages for +exception+ if it is critical and not muted. Never raises: this runs inside
    # notify_exception, and inside Sidekiq's error_handlers chain a raise aborts the chain
    # and drops the email as well.
    def call(exception, options = {})
      return false unless enabled?

      critical = critical_exception(exception)
      return false unless critical

      key = fingerprint(critical)
      return false unless claim_slot?(key)

      begin
        run_later { deliver(format_message(critical, options), key) }
      rescue StandardError, ScriptError
        # e.g. ThreadError when the host is out of processes/memory: give the slot back
        # so the next occurrence tries again rather than staying muted for the window.
        release_slot(key)
        raise
      end
      true
    rescue StandardError, ScriptError => e
      Rails.logger.error("[CriticalErrorWhatsapp] failed, not paging: #{e.class}: #{e.message}")
      false
    end

    # Called from the Sidekiq error handler for fetch-loop Redis failures, which
    # SidekiqRedisFetchError keeps out of email. The first report schedules one recheck;
    # reports that arrive while it is pending (the other threads) are ignored.
    def note_fetch_loop_failure(exception)
      return false unless enabled?

      scheduled = synchronize do
        next false if @redis_check_pending

        @redis_check_pending = true
      end
      return false unless scheduled

      run_later { recheck_redis(exception) }
      true
    rescue StandardError, ScriptError => e
      synchronize { @redis_check_pending = false }
      Rails.logger.error("[CriticalErrorWhatsapp] fetch-loop check failed: #{e.class}: #{e.message}")
      false
    end

    # The exception itself or the first cause that is infrastructure-class. Rails wraps
    # Mysql2::Error in ActiveRecord::StatementInvalid, so the cause chain matters.
    def critical_exception(exception)
      current = exception
      CAUSE_DEPTH.times do
        break if current.nil?
        return current if critical_class?(current) || critical_message?(current)

        current = current.cause
      end
      nil
    end

    # Clears throttle and recheck state. For tests.
    def reset!
      synchronize do
        @sent_at = {}
        @window = []
        @redis_check_pending = false
      end
    end

    private

    def enabled?
      @enabled.nil? ? Rails.env.production? : @enabled
    end

    def async?
      @async != false
    end

    def critical_class?(exception)
      any_class?(exception, CRITICAL_CLASSES)
    end

    def critical_message?(exception)
      message = exception.message.to_s
      (any_class?(exception, MESSAGE_CHECKED_CLASSES) && message.match?(CRITICAL_MESSAGES)) ||
        (any_class?(exception, REDIS_COMMAND_ERROR_CLASSES) && message.match?(REDIS_CRITICAL_MESSAGES))
    end

    def any_class?(exception, names)
      names.any? do |name|
        klass = name.safe_constantize
        klass && exception.is_a?(klass)
      end
    end

    # Groups repeats of "the same" error: the MySQL temp-file name, ids and counts
    # differ per request ("/tmp/MYfd=123"), and Errno::ENOSPC names each file it failed
    # to write, so quoted strings, paths and digits are blanked.
    def fingerprint(exception)
      normalized = exception.message.to_s.lines.first.to_s
                            .gsub(/'[^']*'/, "'?'").gsub(%r{/\S+}, '/?').gsub(/\d+/, 'N').strip.first(200)
      "#{exception.class.name}:#{normalized}"
    end

    # True if this process may page for +key+ now, recording the page.
    def claim_slot?(key)
      now = Time.current
      synchronize do
        @window = window.reject { |t| t < now - THROTTLE_WINDOW }
        last = sent_at[key]
        next false if last && last > now - THROTTLE_WINDOW
        next false if window.size >= MAX_PER_WINDOW

        sent_at[key] = now
        window << now
        true
      end
    end

    # Gives a slot back after a failed send so the next occurrence retries instead of
    # staying muted for the rest of the window.
    def release_slot(key)
      synchronize do
        claimed = sent_at.delete(key)
        index = claimed && window.index(claimed)
        window.delete_at(index) if index
      end
    end

    def recheck_redis(exception)
      sleep(redis_recheck_after) if redis_recheck_after.positive?
      return if redis_reachable?

      key = "sidekiq-fetch-loop:#{exception.class.name}"
      return unless claim_slot?(key)

      message = "#{region_tag}CRITICAL on #{hostname}: Sidekiq cannot reach Redis for " \
                "#{redis_recheck_after.inspect}+ (#{exception.class}: #{exception.message.to_s.truncate(200)}). " \
                "Background jobs are not running."
      deliver(message, key)
    ensure
      synchronize { @redis_check_pending = false }
    end

    def redis_reachable?
      return @redis_probe.call if @redis_probe

      Sidekiq.redis { |conn| conn.call('PING') } == 'PONG'
    rescue StandardError
      false
    end

    def redis_recheck_after
      @redis_recheck_after || REDIS_RECHECK_AFTER
    end

    def format_message(exception, options)
      where = source(options)
      "#{region_tag}CRITICAL on #{hostname}: #{exception.class}: #{exception.message.to_s.truncate(400)}" \
        "#{" · at #{where}" if where} · repeats muted #{THROTTLE_WINDOW.inspect} per process"
    end

    # controller#action for a web request, the job class for a Sidekiq job.
    def source(options)
      controller = options.dig(:env, 'action_controller.instance')
      return "#{controller.controller_name}##{controller.action_name}" if controller

      job = options.dig(:data, :job) || options.dig(:data, 'job')
      job.is_a?(Hash) ? (job['wrapped'] || job['class']) : nil
    end

    def run_later
      return yield unless async?

      Thread.new do
        Thread.current.name = 'critical_error_whatsapp'
        yield
      end
    end

    def deliver(message, key)
      phones = @phones || OpsWhatsappAlert.configured_phones
      if phones.empty?
        Rails.logger.error("[CriticalErrorWhatsapp] no credentials[:grafana_alert_phones], cannot page: #{message.truncate(200)}")
        return
      end

      # Logged before the call: if the process is killed mid-send the page is lost, but
      # this line shows one was attempted.
      Rails.logger.warn("[CriticalErrorWhatsapp] sending page to #{OpsWhatsappAlert.mask_phones(phones)}: #{message.truncate(200)}")
      result = (@transport || method(:send_via_wati)).call(phones, message)
      if result.ok?
        Rails.logger.info("[CriticalErrorWhatsapp] paged #{phones.size} number(s) | WATI: #{result.response.inspect.truncate(300)}")
      else
        release_slot(key)
        Rails.logger.error("[CriticalErrorWhatsapp] WATI rejected the page to #{OpsWhatsappAlert.mask_phones(phones)}: " \
                           "#{result.response.inspect.truncate(500)}")
      end
    rescue StandardError => e
      release_slot(key)
      Rails.logger.error("[CriticalErrorWhatsapp] WATI send failed: #{e.class}: #{e.message} — #{message.truncate(200)}")
    end

    def send_via_wati(phones, message)
      OpsWhatsappAlert.deliver(message, title: 'CapHive Production', link: grafana_link,
                                        broadcast_name: 'Critical Errors', phones: phones)
    end

    # IN and US are independent environments; each process pages with its own credentials,
    # and this only picks the message tag and the Grafana link. AWS_REGION is set in every
    # production process (.env.production -> .env.production.<in|us>; DbRestoreService
    # fetches it at load, so a process without it does not boot). An unrecognised value is
    # shown as-is rather than guessed, so a page can never claim the wrong region.
    def region
      case ENV['AWS_REGION'].to_s
      when /\Aap-/ then 'in'
      when /\Aus-/ then 'us'
      end
    end

    def region_tag
      "[#{(region || ENV['AWS_REGION'].presence || 'region unknown').upcase}] "
    end

    # Path appended to the template's button URL. Without a known region, the app's root.
    def grafana_link
      region ? "grafana/#{region}" : ''
    end

    def hostname
      Socket.gethostname
    end

    def synchronize(&)
      MUTEX.synchronize(&)
    end

    def sent_at
      @sent_at ||= {}
    end

    def window
      @window ||= []
    end
  end
end
