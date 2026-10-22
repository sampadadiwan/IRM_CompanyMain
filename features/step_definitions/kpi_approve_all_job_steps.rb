# Steps for features/startup/kpi_approve_all_job.feature (KpiApproveAllJob).
# The job is run with perform_now under the :test adapter so the KpiCumulateJob it queues is only
# recorded, not run inline (inline cumulation recurses - see kpi_autofill_on_approval_steps.rb).

def pending_kpi_ids_for(portco_name)
  portco = Investor.find_by!(investor_name: portco_name)
  Kpi.unapproved.joins(:kpi_report).where(kpi_reports: { portfolio_company_id: portco.id }).order(:id).pluck(:id)
end

def run_approve_all_job(kpi_ids, portco_name)
  portco = Investor.find_by!(investor_name: portco_name)
  ActiveJob::Base.queue_adapter = :test
  # Keep the alert each run sends (UserAlert is broadcast, not stored), latest last
  @approve_all_alerts ||= []
  allow_any_instance_of(KpiApproveAllJob).to receive(:send_notification).and_wrap_original do |original, message, *rest|
    @approve_all_alerts << message
    original.call(message, *rest)
  end
  KpiApproveAllJob.perform_now(kpi_ids, @user.id, @user.entity_id, portco.id)
end

When('the approve-all job runs for the pending KPIs of {string}') do |portco_name|
  @approve_all_portco = portco_name
  @listed_kpi_ids = pending_kpi_ids_for(portco_name)
  run_approve_all_job(@listed_kpi_ids, portco_name)
end

# E1: same ids again - all already approved by the first run
When('the approve-all job runs again for the same KPIs') do
  expect { run_approve_all_job(@listed_kpi_ids, @approve_all_portco) }.not_to raise_error
end

Given('the pending KPIs of {string} are listed for approval') do |portco_name|
  @approve_all_portco = portco_name
  @listed_kpi_ids = pending_kpi_ids_for(portco_name)
end

# E2: deleted between the click (ids listed) and the job running
Given('the pending {string} KPI for {string} of {string} is deleted') do |kpi_name, as_of, portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  Kpi.unapproved.joins(:kpi_report)
     .find_by!(name: kpi_name, kpi_reports: { as_of: Date.parse(as_of), portfolio_company_id: portco.id })
     .destroy!
end

When('the approve-all job runs for the listed KPIs') do
  run_approve_all_job(@listed_kpi_ids, @approve_all_portco)
end

Then('{string} should have no pending KPIs') do |portco_name|
  expect(pending_kpi_ids_for(portco_name)).to be_empty
end

Then('{string} should have {int} approved {string} KPI(s)') do |portco_name, count, kpi_name|
  portco = Investor.find_by!(investor_name: portco_name)
  # Only the source quarter reports - cumulation is queued, not run, so no YTD/Year KPIs exist yet
  approved = Kpi.approved.joins(:kpi_report).where(name: kpi_name, kpi_reports: { portfolio_company_id: portco.id, period: "Quarter" })
  expect(approved.count).to eq(count)
end

Then('the approve-all alert should read {string}') do |message|
  expect(@approve_all_alerts.last).to eq(message)
end

# E6: the real PATCH the grid's "Approve all" button sends, through a signed-in session
When('the user asks to approve all KPIs of {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  @user.add_role(:company_admin) unless @user.has_role?(:company_admin)
  ActiveJob::Base.queue_adapter = :test
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
  # Land on the page after sign-in, so its "Signed in successfully." flash is used up
  session.follow_redirect!
  session.patch "/kpis/approve_all", params: { portfolio_company_id: portco.id }
  expect(session.response).to be_redirect
  @approve_all_notice = session.flash[:notice]
  @approve_all_alert = session.flash[:alert]
end

Then('the approve-all notice should read {string}') do |message|
  expect(@approve_all_alert).to be_nil
  expect(@approve_all_notice).to eq(message)
end

Then('no approve-all job should be queued') do
  expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job["job_class"] }).not_to include("KpiApproveAllJob")
end
