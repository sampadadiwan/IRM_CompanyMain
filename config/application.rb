require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
Dotenv::Rails.load

module CapHive
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    config.i18n.default_locale = :en

    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1

    config.autoload_paths += Rails.root.glob('app/packs/**/')
    config.autoload_paths << Rails.root.join('lib')

    core_view_paths = %w[access_rights documents entities folders notes permissions reminders tasks users investors investor_accesses valuations nudges base investor_kycs fees signature_workflows kyc_datas notifications core support_client_mappings]

    core_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/core/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/core/#{view_path}/helpers")
    end

    misc_view_paths = %w[approvals form_types form_custom_fields payments investor_notices import_uploads esigns kanbans key_biz_metrics grid_view_preferences events ticker_feeds]

    misc_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/misc/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/misc/#{view_path}/helpers")
    end

    config.paths['app/views'].unshift("#{Rails.root}/app/packs/misc/views")

    funds_view_paths = %w[funds capital_calls capital_commitments capital_distributions portfolios capital_distribution_payments capital_remittances investment_opportunities fund_reports]

    funds_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/funds/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/funds/#{view_path}/helpers")
    end

    secondaries_view_paths = %w[secondary_sales offers interests]

    secondaries_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/secondaries/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/secondaries/#{view_path}/helpers")
    end

    startup_view_paths = %w[investments aggregate_investments option_pools excercises deals funding_rounds kpis kpi_reports]

    startup_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/startups/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/startups/#{view_path}/helpers")
    end

    ai_view_paths = %w[ai_rules ow]

    ai_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/ai/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/ai/#{view_path}/helpers")
    end

    config.to_prepare do
      Devise::Mailer.layout "mailer" # simple.haml or simple.erb
    end

    config.cache_store = :solid_cache_store

    config.time_zone = 'New Delhi'
    config.active_record.default_timezone = :local

    config.secret_key_base = Rails.application.credentials[:SECRET_KEY_BASE]

    config.active_job.queue_adapter = :sidekiq

    Rails.application.routes.default_url_options[:host] = ENV.fetch('HOST', nil)

    config.active_record.yaml_column_permitted_classes = [BigDecimal, Date, ActiveSupport::HashWithIndifferentAccess, Time, Symbol, Roo::Link, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Money, Money::Currency, Money::Bank::VariableExchange, Money::RatesStore::Memory, Monitor]

    config.action_mailer.smtp_settings = {
      address: "email-smtp.ap-south-1.amazonaws.com",
      domain: ENV.fetch("DOMAIN", nil),
      port: 587,
      user_name: Rails.application.credentials[:SES_SMTP_USERNAME],
      password: Rails.application.credentials[:SES_SMTP_PASSWORD],
      authentication: :login,
      enable_starttls_auto: true
    }

    config.to_prepare do
      Devise::SessionsController.layout "devise"
      Devise::RegistrationsController.layout "devise"
      Devise::ConfirmationsController.layout "devise"
      Devise::UnlocksController.layout "devise"
      Devise::PasswordsController.layout "devise"
    end

    if ENV['VULN_SCAN'].blank?
      Rails.application.config.middleware.use ExceptionNotification::Rack,
                                              email: {
                                                email_prefix: "[Error] #{Rails.env}: ",
                                                sender_address: ENV.fetch("SUPPORT_EMAIL", nil),
                                                exception_recipients: ENV.fetch('ERROR_EMAIL')
                                              }

    end

    # We make sure that the ES index gets updated in the background.
    # This helps in reducing the impact to app if ES is down
    Chewy.request_strategy = :sidekiq

    # config.active_storage.replace_on_assign_to_many = false
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
