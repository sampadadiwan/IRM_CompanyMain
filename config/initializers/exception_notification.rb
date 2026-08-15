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
    config.error_handlers << proc do |ex, ctx|
      # Not everything Sidekiq reports here is a failed job. Its own BRPOP poll loop
      # reports Redis blips through this same chain with an empty ctx, then sleeps a
      # second and retries — emailing those woke the on-call for an event that had
      # already healed, with nothing in the mail to act on (incident 2d7eca43).
      # They are counted for Grafana instead; everything else notifies as before.
      next if SidekiqRedisFetchError.suppress?(ex, ctx)

      ExceptionNotifier.notify_exception(
        ex,
        data: ctx # job_class, args, jid, queue, etc.
      )
    end
  end
end
