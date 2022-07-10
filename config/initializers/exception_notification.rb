require 'exception_notification/sidekiq'
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
    email_prefix: "[ERROR] ",
    sender_address: %("Support" <#{ENV['SUPPORT_EMAIL']}>),
    exception_recipients: %(<#{ENV['ERROR_EMAIL']}>)
  }
end
