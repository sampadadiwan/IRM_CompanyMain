# frozen_string_literal: true

# Steps for features/misc/dr_drill_contacts_users.feature. DrillStack's pieces are exercised
# directly - activating them process-wide would silence the rest of the test run.

Given("an in-memory cache for the drill suppression count") do
  # Tests run with :null_store; the count needs a cache that keeps what is written
  @dr_saved_cache ||= Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
end

When("the drill mail interceptor sees an email to {string} titled {string}") do |to, subject|
  @dr_mail = Mail.new(to: to, from: "support@caphive.com", subject: subject, body: "x")
  DrillStack::MailInterceptor.delivering_email(@dr_mail)
end

Then("that email is not delivered") do
  expect(@dr_mail.perform_deliveries).to be(false)
end

Then("{int} outgoing message(s) has/have been suppressed") do |count|
  expect(DrillStack.suppressed_count).to eq(count)
end

# A stand-in for Net::HTTP: records whether the real request ran
class DrProbeHttp
  attr_reader :address, :reached

  def initialize(address)
    @address = address
  end

  def request(_req, _body = nil)
    @reached = true
    :real_response
  end
  prepend DrillStack::OutboundGuard
end

When("a guarded request is sent to {string}") do |host|
  @dr_http = DrProbeHttp.new(host)
  @dr_response = @dr_http.request(Net::HTTP::Post.new("/api/v1/sendTemplateMessage"))
end

Then("it is answered locally with a 200 and no connection is made") do
  expect(@dr_http.reached).to be_nil
  expect(@dr_response.code).to eq("200")
  expect(@dr_response.body).to include("suppressed")
end

Then("it is passed through to the real connection") do
  expect(@dr_http.reached).to be(true)
  expect(@dr_response).to eq(:real_response)
end

When("timed-job registration is decided with DR_DRILL_STACK {string}") do |region|
  @dr_register = DrillStack.register_timed_jobs?(region.empty? ? {} : { "DR_DRILL_STACK" => region })
end

Then("timed jobs are not registered") do
  expect(@dr_register).to be(false)
end

Then("timed jobs are registered") do
  expect(@dr_register).to be(true)
end

When("the drill safeguards are activated without DR_DRILL_STACK") do
  @dr_activated = DrillStack.activate!({})
end

Then("nothing is switched on") do
  expect(@dr_activated).to be(false)
  expect(Net::HTTP.ancestors).not_to include(DrillStack::OutboundGuard)
end

When("drill silence is graded with mail interception {string}, the request guard {string}, {int} timed jobs and no crontab") do |mail, guard, jobs|
  @dr_grade = DrillStack.grade_silence(mail_intercepted: mail == "on", requests_guarded: guard == "on",
                                       timed_jobs: jobs, crontab_installed: false, suppressed: 0)
end

Then("the drill silence grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

When("every committed .env file is read") do
  files = `git -C #{Rails.root} ls-files '.env*'`.split("\n")
  @dr_env_files = files.index_with { |f| Rails.root.join(f).read }
end

Then("none of them sets DR_DRILL_STACK") do
  expect(@dr_env_files).not_to be_empty
  offenders = @dr_env_files.select { |_, text| text.match?(/^\s*DR_DRILL_STACK\s*=/) }.keys
  expect(offenders).to be_empty, "DR_DRILL_STACK found in #{offenders.join(', ')} — a drill branch's .env was merged; the real app would go silent"
end

When("the drill boot message is built for region {string}") do |region|
  @dr_message = DrillStack.boot_message({ "DR_DRILL_STACK" => region })
end

Then("the drill boot message says {string}") do |text|
  expect(@dr_message).to include(text)
end

After do
  Rails.cache = @dr_saved_cache if @dr_saved_cache
end

When("a guarded block-form request is sent to {string}") do |host|
  @dr_http = DrProbeHttp.new(host)
  @dr_http.request(Net::HTTP::Post.new("/api/v1/sendTemplateMessage")) { |response| @dr_block_response = response }
end

Then("the block received the local 200") do
  expect(@dr_http.reached).to be_nil
  expect(@dr_block_response&.code).to eq("200")
end

# X3: the real registry lookup used by dr:verify (no stubbing)
Given("the drill mail interceptor is not registered") do
  ActionMailer::Base.unregister_interceptor(DrillStack::MailInterceptor)
end

When("the drill mail interceptor is registered with ActionMailer") do
  ActionMailer::Base.register_interceptor(DrillStack::MailInterceptor)
  # Never leak a mail-swallowing interceptor into later scenarios in this process
  @dr_unregister_interceptor = true
end

Then("verification reports mail as not intercepted") do
  expect(DrillStack.mail_intercepted?).to be(false)
end

Then("verification reports mail as intercepted") do
  expect(DrillStack.mail_intercepted?).to be(true)
end

After do
  ActionMailer::Base.unregister_interceptor(DrillStack::MailInterceptor) if @dr_unregister_interceptor
end
