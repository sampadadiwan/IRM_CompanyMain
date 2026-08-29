require 'exception_notification/rails'

if ENV['VULN_SCAN'].blank?
  ExceptionNotification.configure do |config|
    # Adds a condition to decide when an exception must be ignored or not.
    # The ignore_if method can be invoked multiple times to add extra conditions.
    # config.ignore_if do |exception, options|
    #   not Rails.env.production?
    # end

    # Notifiers =================================================================

    # Email notifier sends notifications by email.
    config.add_notifier :email, {
      email_prefix: "[ERROR] #{Rails.env}: ",
      sender_address: %("Support" <#{ENV.fetch('SUPPORT_EMAIL_FROM', nil)}>),
      exception_recipients: ENV.fetch('ERROR_EMAIL', nil)
    }
  end

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
        next if SidekiqRedisFetchError.suppress?(ex, ctx)
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
