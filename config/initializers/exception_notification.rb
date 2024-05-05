require 'exception_notification/rails'

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
    sender_address: %("Support" <#{ENV.fetch('SUPPORT_EMAIL', nil)}>),
    exception_recipients: ENV.fetch('ERROR_EMAIL', nil)
  }
end
