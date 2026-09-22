# Coverage for ErrorReportContext — the who/what/where block rendered above the error list in
# EntityMailer#notify_errors and friends. See app/packs/core/base/services/error_report_context.rb.

Given('a job {string} enqueued by {string} from {string}') do |job_class, user_email, origin|
  @error_job = job_class.constantize.new(fund_id: 7)
  # Stands in for the serialize/deserialize round trip: on a Sidekiq thread the job has only the
  # id and the call site that the payload carried over from the enqueueing request.
  @error_job.instance_variable_set(:@acting_user_id, User.find_by!(email: user_email).id)
  @error_job.instance_variable_set(:@enqueued_from, origin)
end

Given('a job {string} enqueued by nobody') do |job_class|
  @error_job = job_class.constantize.new(fund_id: 7)
end

When('the job reports {string} by email') do |message|
  EntityMailer.with(
    error_msg: { missing_rates: [message] },
    context: @error_job.error_context
  ).notify_errors.deliver_now
  open_email("support@example.com")
end

# CGI.unescapeHTML: the mailer view escapes the body, so a rate line like "USD->INR" arrives as
# "USD-&gt;INR" and a call site like "...:in 'update'" as "...:in &#39;update&#39;". Comparing
# against the decoded text asserts what the recipient actually reads.
def error_email_text
  open_email("support@example.com") if current_email.nil?
  CGI.unescapeHTML(current_email.body.to_s)
end

Then('the error email context should show {string} as {string}') do |label, value|
  expect(error_email_text).to include(label)
  expect(error_email_text).to include(value)
end

Then('the error email should still list {string}') do |message|
  expect(error_email_text).to include(message)
end
