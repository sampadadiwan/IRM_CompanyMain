source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# ruby "3.1.2"
gem 'docusign_esign', '~> 4.0.0.rc1'
gem 'faraday'
gem 'faraday-typhoeus'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'pdf-reader'
gem 'rails', '~> 8.0.0'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use mysql as the database for Active Record
gem 'acts_as_favoritor', git: "https://github.com/ausangshukla/acts_as_favoritor.git"
gem "audited"
gem 'enumerize'
gem "json2table"
gem 'mail-logger'
gem "mysql2"
gem "noticed"
gem 'trailblazer'
gem 'yajl-ruby', require: 'yajl'
# To convert Doc into PDF
gem 'libreconv'
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 6.0"
# gem "secure_headers"
# Used to produce mail merge documents from word templates and DB data
gem 'sablon'

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# gem 'rswag-api'
# gem 'rswag-ui'

# Use Redis adapter to run Action Cable in production
gem "redis"
# Background Jobs
gem 'memoized'
gem "sidekiq"
gem "sidekiq-cron"

gem 'devise'
gem 'devise-api', github: 'nejdetkadir/devise-api', branch: 'main'
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
gem "aws-sdk-s3", require: false
# Elastic search client
gem 'chewy'

gem 'kaminari'
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
gem 'ajax-datatables-rails'
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
gem 'rubyzip'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing"
# gem 'rmagick'
gem "combine_pdf"

gem "blazer"
gem "net-pop", github: "ruby/net-pop"
gem 'net-smtp'
gem 'net-ssh'
gem 'public_activity'
gem 'rubyXL', git: "https://github.com/weshatheleopard/rubyXL.git"

# gem "strong_migrations"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'brakeman'
  gem "bundler-audit"
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem 'erubis'

  gem 'htmlbeautifier'
  gem 'parallel_tests'
  gem 'pry-byebug'
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'bullet'
  
end

gem 'awesome_print'
group :development, :staging, :test do
  gem 'factory_bot_rails'
  gem "faker"
end

group :development do
  gem 'packs-rails'
  # gem 'stimpack'
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
  gem 'capistrano-sidekiq', github: 'seuros/capistrano-sidekiq', ref: "784b04c973e5c074dc78c30746077c9e6fd2bb9a"
  gem 'foreman'

  # gem 'capistrano-solid_queue', require: false
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem 'capybara-email'
  gem 'cucumber-rails', require: false
  gem 'database_cleaner-active_record'
  gem 'rspec-rails'

  gem 'simplecov', require: false, group: :test
  gem 'sqlite3'
  gem "webdrivers"
  # gem "selenium-webdriver"
  gem "capybara-playwright-driver"
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
gem 'vega'
gem 'wikipedia-client'

gem "ferrum_pdf", "~> 0.3.0"
gem 'ostruct'
