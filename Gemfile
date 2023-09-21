source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.2"

gem "interactor", "~> 3.0"
# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.0"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use mysql as the database for Active Record
gem "audited", "~> 5.0"
gem "mysql2", "~> 0.5"

gem "json2table"
gem 'mail-logger'
gem "noticed"

# To convert Doc into PDF
gem 'libreconv'
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.0"
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

# Use Redis adapter to run Action Cable in production
gem "redis", "~> 4.0"

gem 'devise'
gem "pundit", git: "https://github.com/varvet/pundit.git"
gem "rolify"

gem 'activerecord-import', "1.5.0"
# Store env variables
gem 'dotenv-rails'
# Send error emails to support
gem 'exception_notification'
gem 'sassc-rails'
# Background Jobs
gem 'sidekiq', '~> 6.4'
gem 'sidekiq-limit_fetch'

gem 'action_mailbox_amazon_ingress', '~> 0.1.3'
gem "aws-sdk-s3", require: false
# Elastic search client
gem 'chewy'

gem 'kaminari'
gem 'paper_trail'

# Charting gems
gem "chartkick"
gem 'groupdate'
gem 'hightop'

gem 'eu_central_bank'
gem 'money-rails', '~>1.12'
gem 'rupees', git: "https://github.com/thimmaiah/rupees.git"
gem 'to_words'

# Admin screens
gem "administrate"
gem 'administrate-field-active_storage'
gem 'administrate-field-belongs_to_search'
gem 'administrate-field-boolean_emoji', '~> 0.3.0'
gem 'administrate-field-shrine'

# This generates rails based datatables
gem 'ajax-datatables-rails'
gem 'draper'
gem 'xirr', git: "https://github.com/thimmaiah/xirr"

# This is the S3 upload gem
gem 'shrine', '~> 3.3'
gem 'uppy-s3_multipart', '~> 1.1'

# Nested for fields
gem 'cocoon'
# Allows for soft delete
gem "paranoia"
# Audit trail
gem 'public_activity', github: 'chaps-io/public_activity', branch: 'master'
gem 'sanitize_email'
# Cron
gem 'whenever', require: false

# Uses bitwise flags
gem 'active_flag'
gem 'active_storage_validations'
gem "acts_as_list"

# Tree relationship of folders/documents
gem 'ancestry'
# Generating XL
gem 'caxlsx'
gem 'caxlsx_rails'
# Maintain counter caches
gem "after_commit_action"
gem 'counter_culture', '~> 3.3'

gem 'impressionist'
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
gem "bootsnap", "1.15.0", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"
# gem 'rmagick'
gem "combine_pdf"

gem "blazer"

# gem "strong_migrations"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'brakeman'
  gem "bundle-audit"
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem 'erubis'
  gem 'net-ssh', '7.0.0.beta1'
  # gem 'parallel_tests'
  gem 'pry-byebug'
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
end

gem 'awesome_print'
group :development, :staging, :test do
  gem 'factory_bot_rails'
  gem "faker"
end

group :development do
  gem 'packwerk'
  gem 'stimpack'
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'annotate'
  gem 'bullet'
  gem "letter_opener", group: :development
  gem 'overcommit', '~> 0.58.0'
  gem "web-console"

  gem "better_errors"
  gem "binding_of_caller"

  # gem 'rails-erd'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # For memory profiling
  # gem 'memory_profiler'
  # For call-stack profiling flamegraphs
  # gem 'stackprof'

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
  gem 'capistrano', '~> 3.5'
  gem 'capistrano-bundler', '~> 2.0'

  gem "capistrano3-puma"
  gem "capistrano-rails", require: false
  gem 'capistrano-rvm'
  gem 'capistrano-sidekiq', github: 'seuros/capistrano-sidekiq', ref: "784b04c973e5c074dc78c30746077c9e6fd2bb9a"
  gem 'foreman'
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem 'capybara-email'
  gem 'cucumber-rails', require: false
  gem 'database_cleaner-active_record'
  gem 'rspec-rails'
  gem "selenium-webdriver", "4.8.6"
  gem 'simplecov', require: false, group: :test
  gem "webdrivers"
end

gem "marginalia", "~> 1.11"
# gem 'newrelic_rpm'
