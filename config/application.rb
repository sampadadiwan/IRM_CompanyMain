require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
Dotenv::Railtie.load

module InvestorRelationshipManagement
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    config.i18n.default_locale = :en
    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1

    config.autoload_paths += Dir[Rails.root.join('app/jobs/**/'), Rails.root.join('app/models/**/'), Rails.root.join('app/dashboards/**/'), Rails.root.join('app/datatables/**/'), Rails.root.join('app/controllers/**/')]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("indices")

    config.to_prepare do
      Devise::Mailer.layout "mailer" # simple.haml or simple.erb
    end

    config.time_zone = 'New Delhi'
    config.active_record.default_timezone = :local

    config.secret_key_base = ENV['SECRET_KEY_BASE']

    config.active_job.queue_adapter = :sidekiq

    Rails.application.routes.default_url_options[:host] = ENV['HOST']

    config.action_mailer.smtp_settings = {
      address: "email-smtp.ap-south-1.amazonaws.com",
      domain: "altconnects.com",
      port: 587,
      user_name: ENV["SES_SMTP_USERNAME"],
      password: ENV["SES_SMTP_PASSWORD"],
      authentication: :login,
      enable_starttls_auto: true
    }

    unless Rails.env.development?
      Rails.application.config.middleware.use ExceptionNotification::Rack,
                                              email: {
                                                email_prefix: '[Error:] ',
                                                sender_address: %("Support" <#{ENV['SUPPORT_EMAIL']}>),
                                                exception_recipients: %("ERROR" <#{ENV['ERROR_EMAIL']}>)
                                              }

    end

    # Configs for upload to S3
    config.paperclip_defaults = {
      storage: :s3,
      s3_permissions: :private,
      url: '/system/:class/:document_directory/:id/:basename.:extension',
      s3_region: ENV["AWS_S3_REGION"],
      s3_credentials: {
        s3_region: ENV["AWS_S3_REGION"],
        s3_host_name: ENV["AWS_S3_HOST_NAME"],
        access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
      }
    }

    config.active_storage.replace_on_assign_to_many = false
    config.active_storage.analyzers = []
    config.active_storage.previewers = []

    # supports :s3, :s3_multipart, or :app
    config.upload_server = if ENV["UPLOAD_SERVER"].present?
                             ENV["UPLOAD_SERVER"].to_sym
                           elsif Rails.env.production?
                             :s3
                           else
                             :app
                           end
  end
end
