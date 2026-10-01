# frozen_string_literal: true

# Steps for features/login/cross_region_housekeeping.feature.
#
# The task is invoked through Rake so the dry-run/EXECUTE=1 gate is exercised as an operator
# would hit it, rather than by calling an inner method directly. Rake tasks are once-only, so
# each invocation re-enables it.

Given("a user {string} with stored regions {string}") do |email, regions|
  @entity ||= FactoryBot.create(:entity, first_name: "Silicon Road", entity_type: "Investment Fund")
  user = FactoryBot.create(:user, email: email, entity: @entity, primary_region: "IN")
  # update_column so the deliberately malformed shapes survive any normalising callback -
  # these are exactly the values found in production.
  user.update_column(:regions, regions)
end

def run_regions_housekeeping(execute:)
  Rails.application.load_tasks unless Rake::Task.task_defined?("users:normalize_regions")
  previous = ENV["EXECUTE"]
  ENV["EXECUTE"] = execute ? "1" : nil
  @housekeeping_output = capture_stdout { Rake::Task["users:normalize_regions"].tap(&:reenable).invoke }
ensure
  previous.nil? ? ENV.delete("EXECUTE") : ENV["EXECUTE"] = previous
end

def capture_stdout
  original = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original
end

When("I run the regions housekeeping in reporting mode") do
  run_regions_housekeeping(execute: false)
end

When("I run the regions housekeeping in execute mode") do
  run_regions_housekeeping(execute: true)
end

Then("it should report {int} users would change") do |count|
  expect(@housekeeping_output).to match(/Scanned \d+ users; #{count} (updated|would change)\./)
end

Then("{string} should still have stored regions {string}") do |email, regions|
  expect(User.find_by(email: email).regions).to eq(regions)
end

Then("{string} should have stored regions {string}") do |email, regions|
  expect(User.find_by(email: email).regions).to eq(regions)
end

Then("{string} should have switchable regions {string}") do |email, csv|
  expect(User.find_by(email: email).switchable_region_codes).to eq(csv.split(",").map(&:strip))
end
