# Steps for the KPI report journey features (features/startup/kpi_report_journey*.feature and
# kpi_mapping_deletion.feature). Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples

# ── Managed by (H6, X1) ─────────────────────────────────────────────────────────

# Editing a stakeholder needs the investors module and admin rights (InvestorPolicy#update?)
Given('the fund admin can manage stakeholders') do
  @user.permissions.set(:enable_investors)
  @user.save!
  @user.add_role(:company_admin)
end

When('I set Managed by on {string} to {string}') do |portco_name, user_name|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(edit_investor_path(portco))
  select(user_name, from: 'investor_managed_by_user_id')
  click_on('Save')
  sleep(1)
end

Then('{string} shows Managed by {string}') do |portco_name, user_name|
  portco = Investor.find_by!(investor_name: portco_name)
  expect(portco.reload.managed_by&.full_name).to eq(user_name)
  visit(investor_path(portco))
  # The details table sits in a tab that may not be the open one
  expect(page).to have_css('#investor_managed_by', text: user_name, visible: :all)
end

Given('there is a user {string} in another entity') do |first_name|
  other = FactoryBot.create(:entity, entity_type: 'Investment Fund')
  FactoryBot.create(:user, entity: other, first_name:, last_name: 'Elsewhere')
end

When('Managed by on {string} is set to the user {string}') do |portco_name, first_name|
  @portco = Investor.find_by!(investor_name: portco_name)
  @portco.managed_by_user_id = User.find_by!(first_name:).id
  @saved = @portco.save
end

Then('the portfolio company is not saved with {string}') do |message|
  expect(@saved).to be(false)
  expect(@portco.errors.full_messages).to include(message)
end

# ── Setup (H1, E1, E4) ──────────────────────────────────────────────────────────

When('the KPI report journey rollout runs for the entity') do
  JourneySetup.rollout("kpi_report", execute: true, entity_id: @entity.id, io: StringIO.new)
end

Given('KPI report journeys are set up for the entity') do
  KpiReportJourneySetup.call(entity: @entity)
end

def kpi_journey_template
  WorkflowTemplate.find_by!(entity: @entity, system_key: KpiReportJourneySetup::FULL_KEY)
end

Then('the entity has the {string} template with the tasks:') do |name, table|
  template = kpi_journey_template
  expect(template.name).to eq(name)
  expect(template.workflow_steps.order(:position).pluck(:name)).to eq(table.raw.flatten)
end

Then('the entity has {int} KPI report auto-assignment rule(s) with no conditions') do |count|
  rules = WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "KpiReport")
  expect(rules.count).to eq(count)
  expect(rules.map(&:conditions).uniq).to eq([[]])
end

Then('the entity has workflow templates enabled') do
  expect(@entity.reload.permissions.enable_workflow_templates?).to be(true)
end

Given('the admin renames the KPI journey task {string} to {string}') do |from, to|
  kpi_journey_template.workflow_steps.find_by!(name: from).update!(name: to)
end

Given('the admin adds a {string} task to the KPI journey') do |name|
  check = WorkflowChecks::Registry.keys_for("KpiReport").find { |key| WorkflowChecks::Registry.label_for(key) == name }
  kpi_journey_template.workflow_steps.create!(name:, kind: "system", check_key: check)
end

Then('the {string} template has {int} tasks and no {string} task') do |_name, count, missing|
  steps = kpi_journey_template.workflow_steps
  expect(steps.count).to eq(count)
  expect(steps.exists?(name: missing)).to be(false)
end

Then('the {string} template has a task {string}') do |_name, task|
  expect(kpi_journey_template.workflow_steps.exists?(name: task)).to be(true)
end

Then('no emails are sent') do
  expect(ActionMailer::Base.deliveries).to be_empty
end

# ── Requests, uploads and the reports they create (H3, H4, H14, H15, E2, E3, E5, E14, E18) ──

def kpi_report_for(portco_name, as_of)
  portco = Investor.find_by!(investor_name: portco_name)
  KpiReport.find_by!(entity: @entity, portfolio_company: portco, as_of: Date.parse(as_of))
end

# The grid's "send upload request": find or create the period's report and run SendPortcoNotification
Given('the fund requests KPIs from {string} for {string} period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  @portfolio_company = portco
  @kpi_report = KpiReport.find_or_create_by!(entity: @entity, portfolio_company: portco, as_of: Date.parse(as_of),
                                             period:, tag_list: "Actual") do |report|
    report.user = @user
    report.enable_portco_upload = true
  end
  SendPortcoNotification.call(model: @kpi_report, entity_id: @entity.id)
  @kpi_report.reload
end

# What KpiReportsController#update does on a portco's final submit, then the real import job
When('the portco submits the workbook for the KPI report') do
  @kpi_report.update_columns(status: "submitted", submitted_at: Time.current, import_status: "pending")
  steps %(When the workbook is imported for the KPI report)
  @kpi_report.reload
end

# KpiReportsController#create: save, then start the journey
When('the fund creates a KPI report for {string} as of {string} period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report = KpiReport.create!(entity: @entity, portfolio_company: portco, user: @user,
                                  as_of: Date.parse(as_of), period:, tag_list: "Actual")
  @kpi_report.start_journey!(@user)
end

When('the fund creates its own KPI report as of {string}') do |as_of|
  @kpi_report = KpiReport.create!(entity: @entity, user: @user, as_of: Date.parse(as_of), period: "Month")
  @kpi_report.start_journey!(@user)
end

Given('a KPI report exists for {string} as of {string} period {string} without a journey') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  KpiReport.create!(entity: @entity, portfolio_company: portco, user: @user, as_of: Date.parse(as_of), period:, tag_list: "Actual")
end

When('the notes of the KPI report for {string} as of {string} are edited') do |portco_name, as_of|
  kpi_report_for(portco_name, as_of).update!(notes: "Checked against the board pack")
end

When('every KPI on the KPI report is rejected') do
  # KpisController#reject destroys the staged KPI
  @kpi_report.kpis.find_each(&:destroy)
  @kpi_report.journey_progress!
end

Given('{string} has an Investor workflow template assigned') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  template = WorkflowTemplate.create!(entity: @entity, name: "Portfolio Company KPI Report Review", workflowable_type: "Investor")
  template.workflow_steps.create!(name: "Data Accuracy Check", states: "Accurate,Rejected", actor_user_ids: [@user.id])
  portco.create_workflow_assignment!(workflow_template: template)
end

Then('{string} has no workflow instance') do |portco_name|
  expect(Investor.find_by!(investor_name: portco_name).workflow_instances).not_to exist
end

# ── Journey assertions ──────────────────────────────────────────────────────────

Then('the KPI report for {string} as of {string} has the {string} journey') do |portco_name, as_of, template_name|
  instance = kpi_report_for(portco_name, as_of).workflow_instances.where(evaluated: true).last
  expect(instance&.template_name).to eq(template_name)
end

Then('the KPI report for {string} as of {string} has no journey') do |portco_name, as_of|
  expect(kpi_report_for(portco_name, as_of).workflow_instances).not_to exist
end

Then('that KPI report has no journey') do
  expect(@kpi_report.reload.workflow_instances).not_to exist
end

def kpi_journey_instance
  record = KpiReport.find(@kpi_report.id)
  WorkflowEvaluator.for(record, cause: :progress)
  journey_instance(record)
end

# Table columns: task | status | message (a blank message is not checked)
Then("the KPI report's journey should show:") do |table|
  instance = kpi_journey_instance
  table.hashes.each do |row|
    result = instance.step_result(journey_position(instance, row["task"].strip)) || {}
    expect(result["status"]).to eq(row["status"].strip), "#{row['task']}: #{result.inspect}"
    expect(result["message"]).to eq(row["message"].strip) if row["message"].present?
  end
end

Then("the KPI report's journey current task should be {string}") do |task|
  instance = kpi_journey_instance
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("the KPI report's journey action for {string} links to the pending KPIs of {string}") do |task, portco_name|
  instance = kpi_journey_instance
  result = instance.step_result(journey_position(instance, task))
  portco = Investor.find_by!(investor_name: portco_name)
  expect(result["action_path"]).to include("portfolio_company_id=#{portco.id}")
  expect(result["action_path"]).to include("view_unapproved=true")
end

# ── Report page (H5, H8, H9, E6, E10, E11) ──────────────────────────────────────

When('I open the KPI report') do
  visit(kpi_report_path(@kpi_report))
end

# The real buttons by id — the journey panel shows the same labels
When('I click Close report and confirm') do
  find("#kpi_report_close_btn").click
  within("#confirmModal") { click_on("Proceed") }
  expect(page).to have_text("Report closed")
end

When('I click Send completion email and confirm') do
  find("#kpi_report_send_completion_btn").click
  within("#confirmModal") { click_on("Proceed") }
  expect(page).to have_text("Completion email sent")
end

# A fund-created report the portfolio company is to fill in (enable_portco_upload), not yet requested
Given('the fund creates a KPI report for {string} as of {string} period {string} for the portco to upload') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report = KpiReport.create!(entity: @entity, portfolio_company: portco, user: @user, as_of: Date.parse(as_of),
                                  period:, tag_list: "Actual", enable_portco_upload: true)
  @kpi_report.start_journey!(@user)
end

# H18 — the journey panel's button clicks the report page's own Send upload request (its popup runs)
When('I click the panel action Send upload request and confirm') do
  find("#journey_action", text: "Send upload request").click
  within("#confirmModal") do
    expect(page).to have_text("no new report is created")
    click_on("Proceed")
  end
  expect(page).to have_text("Notification is being sent")
end

Then('{string} is emailed the upload link') do |first_name|
  email = User.find_by!(first_name:).email
  expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include(email)
end

# A second click on the report page's button, queued before the first job ran: the job sees the link was
# already sent and emails nobody (review fix — H18)
When("the report page's upload request is sent again for the KPI report") do
  SendPortcoNotificationJob.perform_now(@kpi_report.portfolio_company_id, user_id: @user.id, kpi_report_id: @kpi_report.id)
end

Then('{string} is emailed the upload link once') do |first_name|
  email = User.find_by!(first_name:).email
  expect(ActionMailer::Base.deliveries.count { |m| m.to.include?(email) }).to eq(1)
end

Then("the KPI report's upload link is recorded as sent") do
  expect(@kpi_report.reload.link_sent_at).to be_present
end

Then('{string} has {int} KPI reports') do |portco_name, count|
  expect(KpiReport.where(portfolio_company: Investor.find_by!(investor_name: portco_name)).count).to eq(count)
end

# E19 — no approved portal user: the button is there (the panel still finds it) but disabled with the reason
Then('the Send upload request button is disabled saying {string}') do |message|
  button = find("#kpi_report_send_request_btn")
  expect(button).to be_disabled
  expect(button[:title]).to include(message)
end

Then('I should not see the Close report button') do
  expect(page).to have_text(@kpi_report.portfolio_company.investor_name)
  expect(page).not_to have_css("#kpi_report_close_btn")
end

Then('I should not see the Send completion email button') do
  expect(page).not_to have_css("#kpi_report_send_completion_btn")
end

Then('all KPIs of {string} are approved') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  expect(Kpi.where(portfolio_company: portco).unapproved).not_to exist
  expect(Kpi.where(portfolio_company: portco).approved).to exist
end

Then('the KPI report is reviewed') do
  expect(@kpi_report.reload.status).to eq("reviewed")
end

Given('{string} is managed by {string}') do |portco_name, first_name|
  Investor.find_by!(investor_name: portco_name).update!(managed_by_user_id: User.find_by!(first_name:).id)
end

# An admin adds the optional step from the step editor (actors picked there)
Given('the KPI journey has a {string} task with actor {string}') do |name, first_name|
  template = kpi_journey_template
  template.workflow_steps.create!(name:, kind: "system", check_key: KpiReportCompletionEmail::CHECK_KEY,
                                  actor_user_ids: [User.find_by!(first_name:).id])
  # Journeys snapshot their template at launch: relaunch so an existing report's journey has the new
  # step (a report requested later picks it up by itself)
  if @kpi_report
    @kpi_report.workflow_instances.destroy_all
    @kpi_report.workflow_assignment&.destroy
    @kpi_report.reload.start_journey!(@user)
  end
end

Given('the KPI report is closed') do
  KpiReportClose.call(kpi_report: @kpi_report, user: @user)
  @kpi_report.reload
end

When('the completion email is sent twice') do
  2.times { KpiReportCompletionEmail.call(kpi_report: KpiReport.find(@kpi_report.id), user: @user) }
end

def completion_emails_to(first_name)
  email = User.find_by!(first_name:).email
  ActionMailer::Base.deliveries.select { |m| m.to.include?(email) && m.subject.to_s.include?("are complete") }
end

Then('{string} receives the email {string}') do |first_name, subject|
  expect(completion_emails_to(first_name).map(&:subject)).to include(subject)
end

Then('{string} receives no completion email') do |first_name|
  expect(completion_emails_to(first_name)).to be_empty
end

Then('{string} receives {int} completion email(s)') do |first_name, count|
  expect(completion_emails_to(first_name).size).to eq(count)
end

Then("the KPI report's journey should be complete") do
  instance = kpi_journey_instance
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
end

# The controller's portco submit without the import having run yet: the workbook is attached and
# import_status is pending, so "Import workbook" is current ("Import running")
Given('the portco has submitted the workbook but the import has not run') do
  path = build_kpi_test_workbook
  @kpi_report.documents.where(name: "KPIs").destroy_all
  @kpi_report.documents.build(entity_id: @entity.id, name: "KPIs", user_id: @user.id, file: File.open(path), owner: @kpi_report).save!
  @kpi_report.update_columns(status: "submitted", submitted_at: Time.current, import_status: "pending")
  @kpi_report.journey_progress!
end

When('the import job runs while the page is open') do
  @page_marker = SecureRandom.hex(4)
  # A marker on the current DOM proves later assertions ran without a page reload
  page.execute_script("document.body.dataset.journeyMarker = '#{@page_marker}'")
  ImportKpiWorkbookJob.perform_now(@kpi_report.id, @user.id)
end

# ── Who is reminded (H7, E7, E8, E9, X3) ────────────────────────────────────────

Given('the KPI journey task {string} is owned by {string}') do |task, first_name|
  kpi_journey_template.workflow_steps.find_by!(name: task).update!(owner_user: User.find_by!(first_name:))
end

Given('the user {string} is deactivated') do |first_name|
  User.find_by!(first_name:).update_column(:active, false)
end

# A requested, submitted and imported report whose journey has sat on the task for days
Given("Acme's requested KPI report is stalled on {string} for {int} days") do |task, days|
  steps %(
    Given the target KPIs are "Revenue, EBITDA"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | EBITDA  | 10       | 12       |
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    And the portco submits the workbook for the KPI report
  )
  instance = kpi_journey_instance
  expect(instance.current_step_position).to eq(journey_position(instance, task))
  instance.update_columns(current_step_since: days.days.ago)
end

When('the journey reminder job runs') do
  WorkflowAutoReminderJob.perform_now
end

def kpi_reminded(task)
  instance = journey_instance(KpiReport.find(@kpi_report.id))
  instance.workflow_state_changes.where(step_position: journey_position(instance, task), to_state: "owner_reminded")
end

Then('only {string} is reminded about {string}') do |first_name, task|
  expect(kpi_reminded(task).map { |c| c.actor.first_name }).to eq([first_name])
end

Then('{string} and {string} are each reminded once about {string}') do |first, second, task|
  expect(kpi_reminded(task).map { |c| c.actor.first_name }.sort).to eq([first, second].sort)
end

Then('nobody is reminded about {string}') do |task|
  expect(kpi_reminded(task)).not_to exist
end

Then('the journey panel shows {string}') do |text|
  expect(page).to have_css("#journey_panel", text:)
end

# ── Undo (E12, E13, X4) ─────────────────────────────────────────────────────────

Then("the KPI report's completion email can be sent again") do
  expect(@kpi_report.reload.completion_notified_at).to be_nil
end

Then("the KPI report's journey history records a move back to {string}") do |task|
  instance = kpi_journey_instance
  expect(instance.workflow_state_changes.where(step_position: journey_position(instance, task), to_state: "regressed")).to exist
end

# KpisController#unapprove through the KPI's own page
When('I unapprove the KPI {string} of the KPI report') do |name|
  kpi = @kpi_report.kpis.approved.find_by!(name:)
  visit(kpi_path(kpi))
  find("form[action='#{unapprove_kpi_path(kpi)}'] button").click
  within("#confirmModal") { click_on("Proceed") }
  expect(page).to have_text("successfully unapproved")
end

# The import job's own failure path (a post-gate failure): the report is reopened for the portco
When('the import fails') do
  job = ImportKpiWorkbookJob.new
  job.define_singleton_method(:run_import) { |*_args| raise StandardError, "Workbook could not be read" }
  expect { job.perform(@kpi_report.id, @user.id) }.to raise_error(StandardError)
  @kpi_report.reload
end

# ── Approve all (H10) ───────────────────────────────────────────────────────────

# A fund-side report on a period the upload filled (its KPIs are already there)
Given('the fund starts a journey on the KPI report for {string} as of {string}') do |portco_name, as_of|
  kpi_report_for(portco_name, as_of).start_journey!(@user)
end

# The grid's Actions → Approve all form, submitted directly (the menu's confirm is the shared popup)
When('I approve all pending KPIs of {string} on the KPI grid') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(kpi_reports_path(portfolio_company_id: portco.id, view_unapproved: true, grid_view: true))
  form = "form[action*='approve_all'][action*='portfolio_company_id=#{portco.id}']:not([action*='reject=true'])"
  expect(page).to have_css(form, visible: :all)
  # A native submit (no submit event), as the real button does with data-turbo=false
  page.execute_script("document.querySelector(\"#{form}\").submit()")
  expect(page).to have_text("All pending KPIs were successfully approved")
end

Then('the journeys of {string} as of {string} and {string} are on {string}') do |portco_name, first, second, task|
  [first, second].each do |as_of|
    instance = journey_instance(kpi_report_for(portco_name, as_of))
    expect(instance.current_step_position).to eq(journey_position(instance, task)), "#{as_of}: #{instance.step_results.inspect}"
  end
end

# ── KPI mapping delete (H11, H12, H13, E15, E16, X2, X5) ────────────────────────

def kpi_mapping(name, portco_name)
  Investor.find_by!(investor_name: portco_name).investor_kpi_mappings.find_by!(reported_kpi_name: name)
end

Given('the computed KPI mapping {string} has the formula {string}') do |name, formula|
  @portfolio_company.investor_kpi_mappings.create!(entity_id: @portfolio_company.entity_id, reported_kpi_name: name,
                                                   standard_kpi_name: name, autofill: "compute", compute_formula: formula)
end

Given('{string} only has the KPI mapping {string}') do |portco_name, name|
  portco = Investor.find_by!(investor_name: portco_name)
  doomed = portco.investor_kpi_mappings.where.not(reported_kpi_name: name)
  Kpi.where(investor_kpi_mapping_id: doomed.select(:id)).delete_all
  doomed.find_each(&:destroy!)
end

Given('the KPI mapping {string} of {string} is a child of {string}') do |child, portco_name, parent|
  kpi_mapping(child, portco_name).update!(parent: kpi_mapping(parent, portco_name))
end

# The transaction's final step fails, so the batched KPI deletes before it must roll back
Given('deleting KPI mappings fails with a database error') do
  InvestorKpiMapping.class_eval do
    alias_method :__orig_destroy!, :destroy!
    def destroy! = raise(ActiveRecord::StatementInvalid, "simulated failure")
  end
  @restore_mapping_destroy = true
end

After do
  next unless @restore_mapping_destroy

  InvestorKpiMapping.class_eval do
    alias_method :destroy!, :__orig_destroy!
    remove_method :__orig_destroy!
  end
end

When('I open the KPI mapping {string} of {string}') do |name, portco_name|
  @kpi_mapping = kpi_mapping(name, portco_name)
  visit(investor_kpi_mapping_path(@kpi_mapping))
end

When("I click the mapping's Delete button") do
  find("#investor_kpi_mapping_delete_btn").click
  expect(page).to have_css("#confirmModal", visible: true)
end

When("I click the mapping's Delete button and confirm") do
  step "I click the mapping's Delete button"
  within("#confirmModal") { click_on("Proceed") }
end

When('I cancel the confirmation') do
  within("#confirmModal") { click_on("Cancel") }
end

Then('the confirmation says {string}') do |text|
  expect(page).to have_css("#confirmModal", text:)
end

# The controller's operation, as the Delete button calls it (for cases the page can't reach)
When('the KPI mapping {string} of {string} is deleted by the fund admin') do |name, portco_name|
  @delete_result = InvestorKpiMappingDelete.call(mapping: kpi_mapping(name, portco_name), user: @user)
end

Then('the delete is refused with {string}') do |message|
  expect(@delete_result.success?).to be(false)
  expect(@delete_result[:error]).to eq(message)
end

Then("the mapping's Delete button is disabled saying {string}") do |message|
  expect(page).to have_css("#investor_kpi_mapping_delete_blocked[data-bs-title='#{message}'] button[disabled]")
  expect(page).not_to have_css("#investor_kpi_mapping_delete_btn")
end

Then('the KPI mapping {string} of {string} is deleted') do |name, portco_name|
  expect(Investor.find_by!(investor_name: portco_name).investor_kpi_mappings.exists?(reported_kpi_name: name)).to be(false)
end

Then('the KPI mapping {string} of {string} still exists with {int} KPIs') do |name, portco_name, count|
  expect(Kpi.where(investor_kpi_mapping_id: kpi_mapping(name, portco_name).id).count).to eq(count)
end

Then('{string} has no KPIs named {string}') do |portco_name, name|
  expect(Kpi.where(portfolio_company: Investor.find_by!(investor_name: portco_name), name:)).not_to exist
end

# ── End to end (H16, H17) ───────────────────────────────────────────────────────

# The New KPI Mapping form, once per KPI (the journey's "Open KPI mappings" link leads here)
When('I add the KPI mappings {string} for {string} on the mapping form') do |names, portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  names.split(",").map(&:strip).each do |name|
    visit(new_investor_kpi_mapping_path(investor_kpi_mapping: { investor_id: portco.id }))
    fill_in("investor_kpi_mapping_reported_kpi_name", with: name)
    fill_in("investor_kpi_mapping_standard_kpi_name", with: name)
    select("Numeric", from: "investor_kpi_mapping_data_type")
    click_on("Save")
    expect(page).to have_text("Investor kpi mapping was successfully created")
  end
  expect(portco.investor_kpi_mappings.count).to eq(names.split(",").size)
end

# Back from the portco's magic-link session to the logged-in fund admin
When("I switch back to the fund admin's browser") do
  Capybara.session_name = :default
end

Then('the other periods the upload created have no journey') do
  others = KpiReport.where(portfolio_company_id: @kpi_report.portfolio_company_id).where.not(id: @kpi_report.id)
  expect(others).to exist
  expect(WorkflowInstance.where(workflowable_type: "KpiReport", workflowable_id: others.select(:id))).not_to exist
end

# The fund's New KPI Report wizard: report details, the workbook through the real file picker, Save
When('I create a KPI report for {string} as of {string} period {string} with the workbook {string} on the New KPI Report screen') do |portco_name, as_of, period, file|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(new_kpi_report_path(kpi_report: { portfolio_company_id: portco.id }))
  advance_kpi_wizard_to(:report_details)
  fill_in("kpi_report_as_of", with: as_of)
  select(period, from: "kpi_report_period")
  advance_kpi_wizard_to(:upload)
  attach_file("files[]", SAMPLE_KPI_UPLOADS_DIR.join(file).to_s, make_visible: true)
  within("#kpi_validation_panel") { expect(page).to have_content("No blocking errors", wait: 20) }
  check("kpi_warnings_ack_all") if page.has_field?("kpi_warnings_ack_all", wait: 2)
  advance_kpi_wizard_to(:additional_details)
  click_on("Save")
  expect(page).to have_text("Kpi report was successfully created")
  @kpi_report = KpiReport.where(portfolio_company: portco).order(:created_at).first
  expect(@kpi_report.as_of).to eq(Date.parse(as_of))
end

# The grid's Send Reminder / the Send Portco Notification modal both run SendPortcoNotificationJob
When('the fund sends a KPI request to {string} for {string} period {string} from the grid') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  SendPortcoNotificationJob.perform_now([portco.id], user_id: @user.id, as_of:, period:)
  @kpi_report = KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
end

# ── H19: approvals in a new tab with a banner back to the report ──────────────

# The panel's button opens the staged grid in a new tab; the report (and its live step bar) stays here.
# A DOM marker on this tab proves later that it was never reloaded.
When('I click Review pending KPIs in the journey panel') do
  page.execute_script("document.body.dataset.journeyMarker = 'h19'")
  @page_marker = "h19"
  link = find("#journey_action", text: "Review pending KPIs")
  expect(link[:target]).to eq("_blank")
  @review_window = window_opened_by { link.click }
end

Then('a new tab shows the review banner {string}') do |text|
  within_window(@review_window) do
    expect(page).to have_current_path(/view_unapproved=true/)
    expect(page).to have_css("#kpi_journey_return_banner", text:)
  end
end

When('I approve all staged KPIs in the new tab') do
  within_window(@review_window) do
    form = "form[action*='approve_all'][action*='portfolio_company_id=#{@kpi_report.portfolio_company_id}']:not([action*='reject=true'])"
    expect(page).to have_css(form, visible: :all)
    # A native submit (no submit event), as the real button does with data-turbo=false
    page.execute_script("document.querySelector(\"#{form}\").submit()")
    expect(page).to have_text("All pending KPIs were successfully approved")
  end
end

Then("the new tab's banner says {string} and links back to the KPI report") do |text|
  within_window(@review_window) do
    expect(page).to have_css("#kpi_journey_return_banner", text:)
    expect(URI(find("#kpi_journey_return_link")[:href]).path).to eq(kpi_report_path(@kpi_report))
  end
end

Then('in the original tab, without reloading, the step bar should show:') do |table|
  @review_window.close
  step "without reloading, the step bar should show:", table
end
