require 'exception_notification/rails'
# Required at boot, not autoloaded, for the same reason as sidekiq_redis_fetch_error
# below: the notifier runs at the worst possible moment and must not depend on a file
# read from the release directory then.
require Rails.root.join('lib/critical_error_whatsapp')

if ENV['VULN_SCAN'].blank?
  ExceptionNotification.configure do |config|
    # Adds a condition to decide when an exception must be ignored or not.
    # The ignore_if method can be invoked multiple times to add extra conditions.
    # config.ignore_if do |exception, options|
    #   not Rails.env.production?
    # end

    # Error grouping ============================================================
    # One outage used to mean one email per failing request (~1000 on 2026-09-27, the
    # DB host's disk full). Only critical errors (CriticalErrorWhatsapp.critical_exception:
    # DB/Redis/disk) are grouped — emailed on their 1st, 2nd, 4th, 8th... occurrence while
    # they keep recurring. Every other error emails on every occurrence, as before; see
    # CriticalErrorWhatsapp.notification_trigger for why ordinary errors must not be grouped.
    config.error_grouping = true
    config.error_grouping_period = 1.hour
    config.notification_trigger = CriticalErrorWhatsapp.notification_trigger

    # Notifiers =================================================================

    # Moved here from config/application.rb, where a second ExceptionNotification::Rack
    # carried them; these are the settings production emails have always used.
    config.add_notifier :email, {
      email_prefix: "[Error] #{Rails.env}:(#{ENV.fetch('BASE_DOMAIN', nil)})",
      sender_address: ENV.fetch('SUPPORT_EMAIL_FROM', nil),
      exception_recipients: ENV.fetch('ERROR_EMAIL', '').split(',')
    }
  end

  # WhatsApp page for DB/Redis/disk failures, throttled per process. Hooked in front of
  # notify_exception rather than registered as a notifier, so grouping cannot hold it back;
  # goes straight to WATI, so it works when Grafana's webhook path does not.
  CriticalErrorWhatsapp.install!

  # Grouping counters live in per-process memory (CriticalErrorWhatsapp::GROUPING_CACHE),
  # not Rails.cache (MySQL). The middleware resets the store when it is built, after this
  # file runs, so it is set again once boot finishes — and re-asserted before every
  # notification by CriticalErrorWhatsapp::NotifyHook.
  Rails.application.config.after_initialize { CriticalErrorWhatsapp.enforce_grouping_cache! }

  # ExceptionMailer (or the newer exception_notification gem) is designed for Rack requests, so Sidekiq errors bypass it unless you attach a handler:
  Sidekiq.configure_server do |config|
    # Load the classifier here, at boot, instead of letting Zeitwerk autoload it the
    # first time the handler below runs. The handler runs at the worst possible moment
    # and the autoload was a file read against the deployed release directory: when that
    # directory went away underneath a long-running Sidekiq process, resolving the
    # constant raised LoadError *inside* the handler, Sidekiq logged "ERROR HANDLER
    # THREW AN ERROR" and the exception that triggered it was never emailed at all.
    # Requiring up front means a missing file fails the boot loudly rather than silently
    # disabling production alerting. (lib/ is Zeitwerk-managed, so this file stops being
    # reloadable in the Sidekiq process — harmless, it has no reloadable dependencies.)
    require Rails.root.join('lib/sidekiq_redis_fetch_error')

    config.error_handlers << proc do |ex, ctx|
      # Not everything Sidekiq reports here is a failed job. Its own BRPOP poll loop
      # reports Redis blips through this same chain with an empty ctx, then sleeps a
      # second and retries — emailing those woke the on-call for an event that had
      # already healed, with nothing in the mail to act on (incident 2d7eca43).
      # They are counted for Grafana instead; everything else notifies as before.
      #
      # suppress? is written to fail open, but rescue here too: classification is an
      # optimisation, notification is the point, and an error handler that raises makes
      # Sidekiq drop the report entirely. ScriptError is listed alongside StandardError
      # because LoadError is a ScriptError and would otherwise slip past.
      begin
        if SidekiqRedisFetchError.suppress?(ex, ctx)
          # Not emailed, but if Redis still does not answer a minute later it is an
          # outage, not a blip — page for that, since the Grafana rule that counts these
          # pages through the same webhook path that failed on 2026-09-27.
          CriticalErrorWhatsapp.note_fetch_loop_failure(ex)
          next
        end
      rescue StandardError, ScriptError => e
        Sidekiq.logger.error("[exception_notification] suppression check failed, notifying anyway: #{e.class}: #{e.message}")
      end

      ExceptionNotifier.notify_exception(
        ex,
        data: ctx # job_class, args, jid, queue, etc.
      )
    end
  end
end
