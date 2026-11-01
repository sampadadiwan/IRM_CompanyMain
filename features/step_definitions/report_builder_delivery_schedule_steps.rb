# frozen_string_literal: true

# Report Builder delivery — the Delivery tab's schedule, over HTTP and in the
# browser, on the Acme fixture from report_builder_trust_steps.rb.
# Worked examples H4–H8, E3–E7, X2–X5:
# openspec/changes/report-builder-delivery/business-rules.md

module ReportBuilderScheduleWorld
  def schedule_path(suffix = "schedule")
    "/report_builder/#{@report.id}/#{suffix}"
  end

  # The Delivery tab of the builder page fetched over HTTP, or of the settings
  # panel a builder change answered with
  def delivery_tab
    doc  = page_doc.at_css("turbo-stream") ? stream_target("report_builder_settings") : page_doc
    pane = doc.at_css("#rb-pane-delivery")
    expect(pane).not_to be_nil, "no Delivery tab on the page"
    pane
  end

  # Gherkin keeps "\n" as two characters; the recipients box gets a real new line
  def typed(text)
    text.gsub('\n', "\n")
  end
end

World(ReportBuilderScheduleWorld)

Given("Meera's email is {string} and Acme has the user {string}") do |meera_email, other_email|
  acme[:meera].update_columns(email: meera_email)
  acme[:meera].reload
  acme[:ravi] = FactoryBot.create(:user, entity: @entity, first_name: "Ravi", email: other_email,
                                         permissions: User.permissions.keys)
end

Given("the report has a {string} schedule in {string} to {string}") do |frequency, timezone, recipients|
  @report.create_report_schedule!(frequency: frequency, timezone: timezone, enabled: true,
                                  recipients: recipients.split(",").map(&:strip))
end

Given("the schedule was last sent at {string} and goes next at {string}") do |last, nxt|
  @report.report_schedule.update_columns(last_run_at: Time.zone.parse(last), next_run_at: Time.zone.parse(nxt))
end

When("I save the schedule {string} in {string} to {string} from the builder") do |frequency, timezone, recipients|
  builder_request(:patch, schedule_path, enabled: "true", frequency: frequency, timezone: timezone,
                                         recipients: typed(recipients), outsiders_ok: "0")
end

When("I turn the schedule off from the builder") do
  builder_request(:patch, schedule_path, enabled: "false", recipients: "")
end

When("I send a test of the schedule from the builder") do
  builder_request(:post, schedule_path("schedule_test"))
end

When("I send the schedule save {string} to {string} without confirming") do |frequency, recipients|
  rb_patch schedule_path, params: { enabled: "true", frequency: frequency, recipients: recipients }
end

When("Omar sends a test and a recipients check for the report") do
  @refusals = %w[schedule_test schedule_check].map do |suffix|
    rb_session.post schedule_path(suffix), params: { recipients: "omar@beta.test" }
    rb_session.response.status
  end
end

Then("both are refused") do
  expect(@refusals.grep(200..299)).to be_empty, "answers: #{@refusals.inspect}"
end

Then("no email went out") do
  expect(ActionMailer::Base.deliveries).to be_empty
end

Then("the refusal says {string}") do |text|
  expect(last_rb_json["errors"]).to include(text)
end

Then("the schedule emails {string} {string} in {string}") do |recipients, frequency, timezone|
  schedule = ReportSchedule.find_by(report_id: @report.id)
  expect(schedule).to be_present, "no schedule saved"
  expect(schedule.recipients).to eq(recipients.split(",").map(&:strip))
  expect(schedule.frequency).to eq(frequency)
  expect(schedule.timezone).to eq(timezone)
  expect(schedule.enabled).to be(true)
end

Then("the schedule is off and still emails {string}") do |recipients|
  schedule = ReportSchedule.find_by(report_id: @report.id)
  expect(schedule.enabled).to be(false)
  expect(schedule.recipients).to eq(recipients.split(",").map(&:strip))
end

Then("the report has no schedule") do
  expect(ReportSchedule.where(report_id: @report.id)).not_to exist
end

Then("exactly one email went out, to {string}, with the subject {string} and an Excel file") do |to, subject|
  mails = ActionMailer::Base.deliveries
  expect(mails.size).to eq(1), "emails: #{mails.map(&:to).inspect}"
  expect(mails.first.to).to eq([to])
  expect(mails.first.subject).to eq(subject)
  expect(mails.first.attachments.map(&:filename)).to include(a_string_ending_with(".xlsx"))
end

Then("the Delivery tab reads {string}") do |text|
  expect(delivery_tab.text.gsub(/[[:space:]]+/, " ")).to include(text)
end

Then("the Delivery tab's time zone is {string}") do |zone|
  expect(delivery_tab.at_css("#rb_schedule_timezone option[selected]")&.[]("value")).to eq(zone)
end

Then("the Delivery tab says {string} under the recipients") do |text|
  pane = stream_target("report_builder_settings").at_css("#rb-pane-delivery")
  expect(pane.at_css("#rb_schedule_recipients.is-invalid")).to be_present
  expect(pane.at_css("#rb_schedule_recipients_error").text).to include(text)
end

# ─────────────────────────────────────────────────────────────────────────────
# In the browser (H5, E3, X2)
# ─────────────────────────────────────────────────────────────────────────────

When("I turn the schedule on with the recipients {string}") do |recipients|
  open_builder_tab("delivery")
  # The input sits under the iOS-style slider; click the switch itself
  find("label.ios-toggle:has(#scheduleEnabledToggle)").click
  find("#rb_schedule_recipients").set(recipients)
end

When("I click Save schedule") do
  click_on "Save schedule"
end

Then("the popup reads {string} and {string}") do |title, detail|
  within("#confirmModal") do
    expect(page).to have_content(title, wait: 10)
    expect(page).to have_content(detail)
  end
end

When("I click Proceed in the popup") do
  within("#confirmModal") { click_on "Proceed" }
end

When("I click Cancel in the popup") do
  within("#confirmModal") do
    expect(page).to have_content("Immediate Actions", wait: 10)
    click_on "Cancel"
  end
  expect(page).to have_no_css("#confirmModal.show", wait: 5)
end

Then("the recipients field says {string}") do |text|
  expect(page).to have_css("#rb_schedule_recipients.is-invalid", wait: 10)
  expect(page).to have_css("#rb_schedule_recipients_error", text: text)
end

Then("the recipients field still reads {string}") do |text|
  expect(find("#rb_schedule_recipients").value).to eq(text)
end
