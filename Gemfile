source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem 'docusign_esign', '~> 4.0.0.rc1'
gem 'faraday'
gem 'faraday-typhoeus'

# Gem for segmenting paragraphs into sentences
gem 'pragmatic_segmenter'

# Ruby 4.0 removed cgi from the standard library (require "cgi" now only pulls in
# cgi/escape); several models/views need CGI.parse/CGI.unescapeHTML, which only the
# standalone gem still provides.
gem 'cgi'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'dentaku'
gem 'pdf-reader'
gem 'rails', '~> 8.1.2'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use mysql as the database for Active Record
gem "audited"
gem 'enumerize'
gem "json2table"
gem 'mail-logger'
gem "mysql2"
gem "noticed"
gem 'sqlite3'
gem 'trailblazer'
gem 'yajl-ruby', require: 'yajl'
# To convert Doc into PDF
gem 'libreconv'
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 6.0"
# gem "secure_headers"
# Used to produce mail merge documents from word templates and DB data
gem 'docx'
gem 'sablon'

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
gem 'rswag-api'
gem 'rswag-ui'

# Use Redis adapter to run Action Cable in production
# Pinned < 6: Action Cable's redis subscription adapter (actioncable/lib/action_cable/subscription_adapter/redis.rb)
# hardcodes `gem "redis", ">= 4", "< 6"` and raises Gem::LoadError against redis 6.x.
gem "redis", "< 6"
# Background Jobs
gem 'memoized'
gem "sidekiq"
gem "sidekiq-cron"

gem 'devise'
gem 'devise-api', github: 'nejdetkadir/devise-api', branch: 'main'
gem 'devise-two-factor', '~> 6.4'
gem 'rqrcode', '~> 2.0'
gem 'hashie'
gem 'has_scope'
gem "pundit"
gem "rolify"
gem "solid_cache"

gem 'activerecord-import'
# Store env variables
gem 'dotenv-rails'
# Send error emails to support
gem 'exception_notification'
gem 'sassc-rails'

gem "aws-sdk-ec2", require: false
gem 'aws-sdk-iam'
gem "aws-sdk-s3", require: false
gem "aws-sdk-sns"
# Cost-audit rake task (lib/tasks/aws_cost_audit.rake) — all share aws-sdk-core
gem "aws-sdk-costexplorer", require: false
gem "aws-sdk-cloudwatch", require: false
gem "aws-sdk-cloudwatchlogs", require: false
gem "aws-sdk-elasticloadbalancingv2", require: false
# Elastic search client
gem 'chewy'

# gem 'kaminari'
gem "pagy", "~> 9.4"
# gem 'paper_trail'

# Charting gems
gem "chartkick"
gem 'groupdate'
gem 'hightop'

gem 'eu_central_bank'
gem 'money-rails', '~>1.12'
gem 'rupees', git: "https://github.com/thimmaiah/rupees.git"
gem 'to_words'
# gem 'xirr', git: "https://github.com/ausangshukla/xirr.git"

# Admin screens
gem "administrate"
gem 'administrate-field-active_storage'
gem 'administrate-field-boolean_emoji'
gem 'administrate-field-shrine'

# This generates rails based datatables
gem 'draper'

# This is the S3 upload gem
gem 'shrine'
gem 'uppy-s3_multipart'

# Nested for fields
gem 'cocoon'
# Allows for soft delete
gem "paranoia"
gem 'sanitize_email', "2.0.7"
# Cron
gem 'whenever', require: false

# Uses bitwise flags
gem 'active_flag'
# gem 'active_storage_validations'
gem "acts_as_list"

# Tree relationship of folders/documents
gem 'ancestry'
gem 'spreadsheet'
# Generating XL
gem 'caxlsx'
gem 'caxlsx_rails'
# Maintain counter caches
gem "after_commit_action"
gem 'counter_culture'

gem 'roo'

gem 'ransack'
gem "view_component"

# Validates using javascript
gem 'client_side_validations'
gem 'rack-attack'

# for making external API calls
gem 'httparty'
gem 'rubyzip', "2.4.1"

# SMS delivery for two-factor one-time codes. See docs/modules/two_factor_auth/twilio_sms_otp_design.md.
gem 'twilio-ruby'
# Phone number parsing/validation (wraps Google's libphonenumber metadata). Twilio requires
# E.164 and users.phone/call_code carry no format validation, so numbers must be normalised
# before they can be dialled. Per-country trunk-prefix and length rules are not regex-able.
gem 'phonelib'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing"
# gem 'rmagick'
gem "combine_pdf"
gem "hexapdf"

gem "blazer"
gem "net-pop", github: "ruby/net-pop"
gem 'net-scp'
gem 'net-smtp'
gem 'net-ssh'
gem 'public_activity'
gem 'rubyXL', "3.4.33"

# gem "strong_migrations"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'brakeman'
  gem "bundler-audit"
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem 'erubis'

  gem 'bullet'
  gem 'htmlbeautifier'
  gem 'parallel_tests'
  # Deliberately NOT adding cuke_modeler. It only exists to unlock
  # `parallel_cucumber --group-by scenarios`, and that mode silently runs fewer scenarios than
  # it should: measured on `--tags @notification`, a single cucumber process and
  # `--group-by steps` across 6 workers both report 215 scenarios / 2398 steps, while
  # `--group-by scenarios` reports 212 / 2336. Three scenarios vanish inside parallel_tests'
  # own scenario enumeration (these features use Scenario Outlines heavily, so example-row
  # expansion is the likely culprit - not root-caused). A green run that quietly skipped three
  # scenarios is worse than a slower one, so group by steps and accept the lumpier split.
  gem 'pry-byebug'
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false

  # Not a test tier of its own — there are no specs. Cucumber is built on it:
  # features/support/env.rb requires 'rspec/rails' and 'cucumber/rspec/doubles', and step
  # definitions use RSpec::Expectations and RSpec::Mocks. Removing this breaks every feature.
  gem 'rspec-rails'
end

gem 'awesome_print'
group :development, :staging, :test do
  gem 'factory_bot_rails'
  gem "faker"
end

group :development do
  gem 'packs-rails'
  # gem 'stimpack'
  # SES suppression list + configuration-set inspection for the ses:bounce_stats
  # rake task (lib/tasks/ses_bounce_stats.rake). Diagnostic only — the app sends
  # via the SES SMTP interface and never calls the SES API, so this is not needed
  # in production. (That task's time series comes from aws-sdk-cloudwatch, above.)
  gem "aws-sdk-sesv2", require: false
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'annotate'
  gem "letter_opener", group: :development
  gem 'overcommit', require: false
  gem "web-console"

  gem "better_errors"
  gem "binding_of_caller"

  # gem 'rails-erd'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  gem "rack-mini-profiler"
  gem "ruby-prof"

  # For memory profiling
  # gem 'memory_profiler'
  # For call-stack profiling flamegraphs
  # gem 'stackprof'

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
  gem 'capistrano'
  gem 'capistrano-bundler'

  gem 'capistrano3-puma'

  gem "capistrano-rails", require: false
  gem 'capistrano-rvm'
  gem 'foreman'

  # gem 'capistrano-solid_queue', require: false
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem 'capybara-email'
  gem 'cucumber', '10.2.0'
  gem 'cucumber-rails', require: false
  gem 'database_cleaner-active_record'

  gem 'simplecov', require: false, group: :test
  gem "webdrivers"
  # gem "selenium-webdriver"
  gem 'capybara-playwright-driver'
  gem 'playwright-ruby-client', '1.61.0'
  gem "webmock"
  gem 'terminal-table'
end

gem "marginalia"
# gem 'newrelic_rpm'
gem 'aws-sdk-wafv2', require: false
gem 'eqn'
gem 'friendly_id'
gem 'humanize'
gem 'langchainrb'
gem 'mini_magick'
gem 'parser'
gem 'polars-df'
gem 'prometheus_exporter'
gem 'redcarpet'
gem "ruby-openai", git: "https://github.com/alexrudall/ruby-openai.git"
gem 'sendgrid-ruby'
gem 'wikipedia-client'

gem "ferrum_pdf", "~> 0.3.0"
gem 'ostruct'

# The only change in this gem is that models.json has the new gemini 2.5 flash model
gem 'doorkeeper'
gem 'doorkeeper-openid_connect'
gem 'google_search_results'
gem 'htmltoword'
gem 'i18n-tasks', group: :development
gem 'ice_cube'
gem 'json_schemer'
# MCP (Model Context Protocol) server SDK — exposes fund data as tools for external AI clients.
# Pinned to ~> 1.3 to prevent surprise upgrades; 1.3.0 introduced dns_rebinding_protection
# which requires allowed_hosts configuration for non-localhost deployments.
gem 'mcp', '~> 1.3'
gem 'ruby_linear_regression'
gem 'ruby_llm'
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'
gem 'email_reply_parser'