# frozen_string_literal: true

# Steps for features/misc/dr_serving_checks.feature. Pure: facts in, verdicts out.

When("{int} document files are looked up and {int} are missing") do |checked, missing|
  @dr_grade = Dr::ServingChecks.grade_documents(checked: checked, missing_ids: (1..missing).to_a)
end

When("the queued job ran after {string} seconds") do |seconds|
  @dr_grade = Dr::ServingChecks.grade_job(seconds: seconds == "never" ? nil : seconds.to_f, queue: "default")
end

When("the sign-in page answers HTTP {string} with {string}") do |code, body|
  @dr_grade = Dr::ServingChecks.grade_sign_in(code: code, body: body)
end

When("the signed-in read answers HTTP {string} with {string}") do |code, body|
  @dr_grade = Dr::ServingChecks.grade_api_read(code: code, body: body, path: "/funds.json")
end

When("the PDF conversion produced {string} with error {string}") do |head, error|
  @dr_grade = Dr::ServingChecks.grade_pdf(head: head == "none" ? nil : head, seconds: 2.5, error: error.presence)
end

When("curl to the app host through the load balancer exits {int}") do |code|
  @dr_grade = Dr::ServingChecks.grade_certificate(curl_exit: code, host: "dev.altconnects.com")
end

When("{int} of {int} load balancer targets are healthy") do |healthy, total|
  @dr_grade = Dr::ServingChecks.grade_targets(healthy: healthy, total: total)
end

Then("the serving check is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

When("older document ids are picked below {int}") do |max_id|
  @dr_ids = Dr::ServingChecks.spread_ids(max_id)
end

Then("the ids are 10, 20, 30, 40, 50, 60, 70, 80, 90 and 100") do
  expect(@dr_ids).to eq([10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
end

When("the ping job runs with token {string}") do |token|
  # The test env's cache is a null store; give the job a real one for this scenario
  @dr_saved_cache = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
  DrVerifyPingJob.perform_now(token)
end

Then("the cache holds the ping for {string}") do |token|
  expect(Rails.cache.read(DrVerifyPingJob.cache_key(token))).to be_present
ensure
  Rails.cache = @dr_saved_cache if @dr_saved_cache
end
