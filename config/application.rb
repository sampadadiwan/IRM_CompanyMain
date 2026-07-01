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

    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1

    config.autoload_lib(ignore: %w[assets tasks])

    # Exclude subdirectories within controllers/, dashboards/, and policies/ from being Zeitwerk
    # roots — they are namespaces (e.g. Admin::, Audited::, Noticed::) resolved relative to
    # their parent dir. Also exclude delivery_methods/ itself (namespace dir at pack level).
    # concerns/ dirs are the exception: they define flat top-level constants, so re-added below.
    config.autoload_paths += Rails.root.glob('app/packs/**/').reject do |path|
      path_str = path.to_s
      path_str.match?(%r{/(controllers|channels|dashboards|policies)/[^/]+}) ||
        path_str.match?(%r{/(delivery_methods|account_entry_allocation)/?$})
    end
    config.autoload_paths += Rails.root.glob('app/packs/**/controllers/concerns/')
    config.autoload_paths << Rails.root.join('lib')

    core_view_paths = %w[access_rights documents entities folders notes permissions reminders tasks users investors investor_accesses valuations nudges base investor_kycs fees signature_workflows kyc_datas notifications core support_client_mappings validation_rules workflow_templates email_deliverability]

    core_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/core/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/core/#{view_path}/helpers")
    end

    misc_view_paths = %w[approvals form_types form_custom_fields payments investor_notices import_uploads esigns kanbans grid_view_preferences events blogs incoming_emails]

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

    ai_view_paths = %w[ai_rules chats agent_charts support_agents faqs ai_portfolio_reports assistants assistant_tasks report_insights customer_support_agent]

    ai_view_paths.each do |view_path|
      config.paths['app/views'].unshift("#{Rails.root}/app/packs/ai/#{view_path}/views")
      config.paths['app/helpers'].unshift("#{Rails.root}/app/packs/ai/#{view_path}/helpers")
    end

    # This is to enable docker to access the app running on localhost
    # config.hosts << "host.docker.internal"

    config.to_prepare do
      Devise::Mailer.layout "mailer" # simple.haml or simple.erb
    end

    config.action_view.default_form_builder = "LocaleDateFormBuilder"

    config.cache_store = :solid_cache_store

    config.time_zone = 'New Delhi'
    config.active_support.to_time_preserves_timezone = :zone
    config.active_record.default_timezone = :local

    config.secret_key_base = Rails.application.credentials[:SECRET_KEY_BASE]

    config.active_job.queue_adapter = :sidekiq

    Rails.application.routes.default_url_options[:host] = ENV.fetch('HOST', nil)

    config.active_record.yaml_column_permitted_classes = [BigDecimal, Date, ActiveSupport::HashWithIndifferentAccess, Time, Symbol, Roo::Link, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Money, Money::Currency, Money::Bank::VariableExchange, Money::RatesStore::Memory, Monitor, Enumerize::Value]

    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_SERVER"),
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

      if RubyLLM.config.use_new_acts_as
        require 'ruby_llm/active_record/acts_as'
        ActiveSupport.on_load(:active_record) { include RubyLLM::ActiveRecord::ActsAs } unless ::ActiveRecord::Base.include?(RubyLLM::ActiveRecord::ActsAs)
      end
    end

    if ENV['VULN_SCAN'].blank?
      Rails.application.config.middleware.use ExceptionNotification::Rack,
                                              email: {
                                                email_prefix: "[Error] #{Rails.env}:(#{ENV.fetch('BASE_DOMAIN', nil)})",
                                                sender_address: ENV.fetch("SUPPORT_EMAIL_FROM", nil),
                                                exception_recipients: ENV.fetch('ERROR_EMAIL', nil).split(',')
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

    # Active Record encryption — required by devise-two-factor for otp_secret.
    #
    # Local/test use hardcoded dev keys (safe — never used in production).
    # Staging/production read from Rails credentials. To add keys to an environment:
    #
    #   1. Generate keys (run once per environment, never reuse across envs):
    #        bundle exec rails db:encryption:init
    #
    #   2. Edit the credentials file for that environment, e.g. for staging.in:
    #        RAILS_ENV=staging EDITOR="nano" bundle exec rails credentials:edit --environment staging.in
    #      (substitute staging.us / production.in / production.us as needed)
    #
    #   3. Paste the block from step 1 under an `active_record_encryption:` key:
    #        active_record_encryption:
    #          primary_key: <value from step 1>
    #          deterministic_key: <value from step 1>
    #          key_derivation_salt: <value from step 1>
    #
    #   WARNING: Never rotate these keys after users have enrolled in 2FA — doing so
    #   permanently breaks decryption of all existing otp_secret values in the database.
    if Rails.env.local? || Rails.env.test?
      config.active_record.encryption.primary_key         = "83c289e1ed3247d95938943c48c9b5ac35dac2d6fa6fd8a942016c025e5c6714"
      config.active_record.encryption.deterministic_key   = "d7b7d8e9f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7"
      config.active_record.encryption.key_derivation_salt = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1"
    else
      enc = Rails.application.credentials.active_record_encryption
      config.active_record.encryption.primary_key         = enc.fetch(:primary_key)
      config.active_record.encryption.deterministic_key   = enc.fetch(:deterministic_key)
      config.active_record.encryption.key_derivation_salt = enc.fetch(:key_derivation_salt)
    end
  end
end
