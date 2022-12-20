source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.2"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "interactor", "~> 3.0"
gem "rails", "~> 7.0.3.1"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use mysql as the database for Active Record
gem "audited", "~> 5.0"
gem "mysql2", "~> 0.5"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.0"

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

gem 'activerecord-import'
gem 'dotenv-rails'
gem 'exception_notification'
gem 'sassc-rails'
gem 'sidekiq', '~> 6.4'
gem 'sidekiq-limit_fetch'

gem "aws-sdk-s3", require: false
gem 'chewy'

gem 'kaminari'
gem 'paper_trail'

# Charting gems
gem "chartkick"
gem 'groupdate'
gem 'hightop'

gem 'eu_central_bank'
gem 'money-rails', '~>1.12'
gem 'rupees', git: "https://github.com/satishkaushik/rupees.git"
gem 'to_words'
# gem 'razorpay'

gem 'xirr', git: "https://github.com/thimmaiah/xirr"
# gem 'prometheus_exporter'

# For verifying digital signatures in PDFs
# gem 'chilkat'

gem 'odf-report'
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary-edge'

gem "administrate"
gem 'administrate-field-active_storage'
gem 'administrate-field-boolean_emoji', '~> 0.3.0'
gem 'administrate-field-shrine'
# gem 'ajax-datatables-rails', git: "git@github.com:jbox-web/ajax-datatables-rails.git"

# For custom buckets in S3 per client
gem 'fastimage'
gem 'marcel'
gem 'shrine', '~> 3.3'
gem 'uppy-s3_multipart', '~> 1.1'

gem 'cocoon'
gem "paranoia", "~> 2.2"
gem 'public_activity', github: 'chaps-io/public_activity', branch: 'master'
gem 'sanitize_email'
gem 'whenever', require: false
# gem 'ajax-datatables-rails'

gem 'active_flag'
gem 'active_storage_validations'
gem "acts_as_list"
gem 'acts-as-taggable-on', '~> 9.0'
gem 'ancestry'
gem 'caxlsx'
gem 'caxlsx_rails'
gem 'counter_culture', '~> 2.0'
gem 'impressionist'
gem 'roo'
gem 'spreadsheet' # To write exiting XLs with formulas

gem 'ransack'
gem "view_component"

gem 'client_side_validations'
gem 'rack-attack'

# for making external API calls
gem 'httparty'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"
# gem 'rmagick'
gem "combine_pdf"

gem "blazer"

# gem "strong_migrations"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'brakeman', "5.2.2"
  gem "bundle-audit", "~> 0.1.0"
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem 'erubis'
  gem 'net-ssh', '7.0.0.beta1'
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
  gem "capistrano", "3.16", require: false
  gem "capistrano3-puma"
  gem "capistrano-rails", "~> 1.6", require: false
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
  gem "selenium-webdriver"
  gem 'simplecov', require: false, group: :test
  gem "webdrivers"
end

gem "marginalia", "~> 1.11"
gem 'newrelic_rpm'
