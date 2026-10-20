# frozen_string_literal: true

# features/support_console/provisioning.feature — the provisioning tasks' pure decisions, with no AWS call.

def load_support_console_tasks
  return if defined?(SupportConsoleDbAccess)

  require "rake"
  load Rails.root.join("lib/tasks/support_console/db_access.rake").to_s
end

When('the provisioning region is worked out for {string} with REGION {string}') do |env_name, region|
  load_support_console_tasks
  previous = ENV.fetch("REGION", nil)
  ENV["REGION"] = region.presence
  @region_error = nil
  @region = SupportConsoleDbAccess.region(SupportConsoleDbAccess::ENVIRONMENTS.fetch(env_name))
rescue SystemExit => e
  # abort raises SystemExit carrying the message.
  @region_error = e.message
ensure
  ENV["REGION"] = previous
end

Then('it is refused with {string}') do |text|
  expect(@region_error).to include(text)
end

Then('the region is {string}') do |region|
  expect(@region_error).to be_nil
  expect(@region).to eq(region)
end
