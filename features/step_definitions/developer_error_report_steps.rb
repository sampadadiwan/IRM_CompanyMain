# Steps for: features/core/developer_error_report.feature

# Stands in for a controller: ErrorReportContext.for_request reads only the class name, the action,
# the request (method, path, id), the session and current_user - and current_user through #send,
# because in a real controller it is a helper method.
class ErrorReportFakeController
  FakeRequest = Struct.new(:request_method, :fullpath, :request_id)

  attr_reader :request, :session, :action_name

  def initialize(user:, path:, support_user_id: nil)
    @user = user
    @request = FakeRequest.new("GET", path, "req-err-rpt-1")
    @session = { support_user_id: }
    @action_name = "show"
  end

  private

  def current_user
    @user
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Building reports
# ─────────────────────────────────────────────────────────────────────────────

When('an error report is built for a request to {string} by {string} impersonated by {string}') do |path, email, support_email|
  user = User.find_by!(email:)
  support = User.find_by!(email: support_email)
  @report = ErrorReportContext.for_request(ErrorReportFakeController.new(user:, path:, support_user_id: support.id))
end

When('a request error report is attached but nothing has printed it') do
  @lookups = 0
  @lazy = ErrorReportContext::Lazy.new do
    @lookups += 1
    { "Source" => "built" }
  end
  # This is what WithAuthentication#prepare_exception_notifier puts in the Rack env on every request.
  @exception_data = { report: @lazy }
end

When('the error email prints its data') do
  # ExceptionNotifier's email renders the data hash with PP (views/exception_notifier/_data.text.erb).
  2.times { PP.pp(@exception_data, +"") }
end

When('an error report is built for a failed Sidekiq NotifyKycJob enqueued by {string}') do |email|
  user = User.find_by!(email:)
  # The shape Sidekiq hands an error handler for a failed ActiveJob job.
  ctx = {
    context: "Job raised exception",
    job: {
      "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => "NotifyKycJob", "queue" => "default",
      "jid" => "jid-err-rpt", "retry_count" => 2,
      "args" => [{
        "job_class" => "NotifyKycJob", "job_id" => "aj-err-rpt",
        "arguments" => [1845, { "email_method" => "notify_kyc_updated", "_aj_ruby2_keywords" => ["email_method"] }],
        "acting_user_id" => user.id,
        "enqueued_from" => "app/packs/core/investor_kycs/models/investor_kyc.rb:292"
      }]
    }
  }
  @report = ErrorReportContext.for_sidekiq(ctx)
end

When('an error report is built from a malformed Sidekiq context') do
  @report = ErrorReportContext.for_sidekiq(nil)
end

When('a WeeklyTaskDigestJob reports an error through ErrorReport for entity {string}') do |entity_name|
  allow(ExceptionNotifier).to receive(:notify_exception)
  job = WeeklyTaskDigestJob.new
  ErrorReport.notify(StandardError.new("digest failed"), job:, entity_id: Entity.find_by!(name: entity_name).id)
  expect(ExceptionNotifier).to have_received(:notify_exception) { |_error, options| @report = options[:data][:report] }
end

When('code reports an error through ErrorReport without naming a source') do
  allow(ExceptionNotifier).to receive(:notify_exception)
  ErrorReport.notify(StandardError.new("no source"))
  expect(ExceptionNotifier).to have_received(:notify_exception) { |_error, options| @report = options[:data][:report] }
end

# ─────────────────────────────────────────────────────────────────────────────
# Assertions
# ─────────────────────────────────────────────────────────────────────────────

Then(/^the (?:reported )?error report shows "([^"]*)" as "([^"]*)"$/) do |label, value|
  expect(@report[label].to_s).to include(value)
end

Then('the error report does not mention {string}') do |text|
  expect(@report.values.join(" ")).not_to include(text)
end

Then('nothing has been looked up for the report yet') do
  expect(@lookups).to eq(0)
end

Then('the report has been built exactly once') do
  expect(@lookups).to eq(1)
  expect(@lazy.value).to eq("Source" => "built")
end
