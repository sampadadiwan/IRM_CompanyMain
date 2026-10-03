# Steps for the investor KYC journey and the KYC fixes that ship with it (investor_kyc_journey*.feature,
# investor_kyc_fixes.feature). Generic panel / rollout / Set up journeys steps are reused from the
# capital call and distribution journey step files.
# Worked examples in openspec/changes/investor-kyc-journey/design.md#worked-examples

KYC_SAMPLE_FILE = "public/sample_uploads/sample_kyc1.pdf".freeze

# ── Entity configuration ──────────────────────────────────────────────────────

Given("the entity's investor KYC journeys are removed") do
  WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "InvestorKyc").destroy_all
  WorkflowTemplate.where(entity: @entity, workflowable_type: "InvestorKyc")
                  .find_each { |t| t.workflow_assignments.destroy_all && t.destroy }
end

Given("the entity's investor KYC journeys are seeded") do
  InvestorKycJourneySetup.call(entity: @entity)
end

Given("the entity requires the individual KYC documents {string}") do |names|
  @entity.entity_setting.update!(individual_kyc_doc_list: names)
end

Given("the entity requires no KYC documents") do
  @entity.entity_setting.update!(individual_kyc_doc_list: nil, non_individual_kyc_doc_list: nil)
end

Given("AML is enabled for the entity") do
  @entity.entity_setting.update!(aml_enabled: true)
end

Given("AML is not enabled for the entity") do
  @entity.entity_setting.update!(aml_enabled: false)
end

# Yes-no Document Checks on one document (openspec/changes/document-checks)
Given("the entity has {int} document checks on {string}") do |count, document_name|
  count.times do |i|
    DocCheck.create!(entity: @entity, record_type: "InvestorKyc", document_name:, action: "question",
                     look_for: "Question #{i + 1}?", position: i)
  end
end

# The seeded Compliance sign-off has no approver; pick me, before the KYC launches its journey
Given("I am the approver on the Compliance sign-off") do
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  template.workflow_steps.find_by!(name: "Compliance sign-off").workflow_step_actors.create!(user: @user)
end

# ── The company's KYC emails (the "Set up KYC email" / "Preview the email" tasks) ─────────────────
# KYC emails are owned by the ENTITY with for_type "InvestorKyc" (unlike a call's, owned by its fund),
# which is why one edit reaches every KYC of the company that has not emailed its investor yet.
# Worked examples H1, E4–E7, E14 — openspec/changes/investor-kyc-email-review-steps/design.md#worked-examples

Given("the entity has a KYC email {string}") do |subject|
  @kyc_email = CustomNotification.create!(entity: @entity, owner: @entity, for_type: "InvestorKyc", subject:,
                                          body: "Please complete your KYC", email_method: "notify_kyc_required")
end

Given("the entity's KYC email is disabled") do
  @kyc_email.update!(enabled: false)
end

Given("the entity has a KYC reminder email {string}") do |subject|
  @kyc_reminder_email = CustomNotification.create!(entity: @entity, owner: @entity, for_type: "InvestorKyc", subject:,
                                                   body: "A gentle reminder", email_method: "kyc_required_reminder")
end

# Through the controller, so the after_action that runs JourneyEmailEdit fires as it does in the app.
# travel 1.second so the invalidation is newer than the confirmation it withdraws.
When("I edit the entity's KYC email") do
  travel 1.second
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.custom_notification_path(@kyc_email),
                  custom_notification: { subject: "Complete your KYC — revised" })
end

When("I edit the entity's KYC reminder email") do
  travel 1.second
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.custom_notification_path(@kyc_reminder_email),
                  custom_notification: { subject: "A reminder — revised" })
end

When("I delete the entity's KYC email") do
  travel 1.second
  as_user_request(@user, :delete, Rails.application.routes.url_helpers.custom_notification_path(@kyc_email), {})
end

# One company email edit reaches many KYCs, so these scenarios juggle more than one (X2)
Given("I remember this KYC as {string}") do |label|
  @remembered_kycs ||= {}
  @remembered_kycs[label] = @investor_kyc
end

Then("the journey of KYC {string} should be at {string}") do |label, task|
  instance = journey_instance(InvestorKyc.find(@remembered_kycs.fetch(label).id))
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("the entity's KYC email subject should be {string}") do |subject|
  expect(@kyc_email.reload.subject).to eq(subject)
end

Then("the journey of KYC {string} should not have moved back") do |label|
  instance = journey_instance(InvestorKyc.find(@remembered_kycs.fetch(label).id))
  expect(instance.workflow_state_changes.where(to_state: %w[regressed invalidated])).not_to exist
end

# X1 — the undo failing must never take the notification save down with it
Given("resetting the email reviews raises an error") do
  WorkflowStepInvalidate.singleton_class.class_eval do
    alias_method :__original_call, :call
    define_method(:call) { |**_args| raise "Journey undo exploded" }
  end
end

After do
  klass = WorkflowStepInvalidate.singleton_class
  if klass.method_defined?(:__original_call)
    klass.class_eval do
      alias_method :call, :__original_call
      remove_method :__original_call
    end
  end
end

When("I create the entity's KYC email {string}") do |subject|
  travel 1.second
  as_user_request(@user, :post, Rails.application.routes.url_helpers.custom_notifications_path,
                  custom_notification: { subject:, body: "Please complete your KYC", for_type: "InvestorKyc",
                                         email_method: "notify_kyc_required", entity_id: @entity.id,
                                         owner_id: @entity.id, owner_type: "Entity" })
end

# ── KYCs ──────────────────────────────────────────────────────────────────────

# Built as the subclass, the way InvestorKycsController#new builds it (so the STI type-name fix is exercised)
def create_journey_kyc(args = "")
  attrs = FactoryBot.attributes_for(:investor_kyc, verified: false, completed_by_investor: false).except(:submission_status, :verified, :completed_by_investor)
  kyc = IndividualKyc.new(attrs.merge(entity: @entity, investor: @investor, kyc_type: "individual", submission_status: "not_sent"))
  key_values(kyc, args)
  kyc.save!(validate: false)
  kyc.reload
end

Given("there is an individual KYC for the investor {string}") do |args|
  @investor_kyc = create_journey_kyc(args)
end

Given("there is an individual KYC for the investor") do
  @investor_kyc = create_journey_kyc
end

Given("the KYC has the documents {string}") do |names|
  names.split(",").map(&:strip).each do |name|
    Document.create!(entity_id: @investor_kyc.entity_id, name:, owner: @investor_kyc, user: @user,
                     file: File.new(KYC_SAMPLE_FILE, "r"))
  end
end

# A document as the KYC form's file field saves it: named after the field label, with the field's
# meta_data as owner_tag (e.g. "Upload Tax ID" tagged "PAN")
Given("the KYC has the document {string} tagged {string}") do |name, owner_tag|
  Document.create!(entity_id: @investor_kyc.entity_id, name:, owner_tag:, owner: @investor_kyc, user: @user,
                   file: File.new(KYC_SAMPLE_FILE, "r"))
end

# InvestorKycConcern#docs_completed? must agree with the journey's "Upload required documents"
Then("the KYC's required documents should be complete") do
  expect(@investor_kyc.reload.docs_completed?).to be(true)
end

Then("the KYC's required documents should not be complete") do
  expect(@investor_kyc.reload.docs_completed?).to be(false)
end

# A finished Document Checks run as DocChecks::RunJob stores it: one result per check of the entity, the
# first <failing> answered "No" (needing attention), on the KYC's own documents as they are now.
# Worked examples H7, E22 — openspec/changes/document-checks/design.md#worked-examples
Given("the KYC's documents were checked with {int} of {int} items needing attention") do |failing, total|
  @investor_kyc.reload
  checks = DocCheck.for_record(@investor_kyc).to_a
  expect(checks.size).to eq(total), "the entity has #{checks.size} document checks for this KYC, not #{total}"
  DocCheckRun.for_record(@investor_kyc).update_all(current: false)
  run = DocCheckRun.create!(entity: @investor_kyc.entity, record: @investor_kyc, user: @user, status: "done", current: true,
                            started_at: Time.current, finished_at: Time.current,
                            counts: { "ok" => total - failing, "attention" => failing })
  checks.each_with_index do |check, index|
    document = DocChecks::Kyc.find_document(@investor_kyc, check.document_name)
    run.doc_check_results.create!(entity: @investor_kyc.entity, doc_check: check, document_name: check.document_name,
                                  look_for: check.look_for, action: check.action, document_id: document&.id,
                                  document_file_id: document&.file&.id, outcome: index < failing ? "unexpected_answer" : "ok",
                                  note: index < failing ? nil : "yes", doc_value: index < failing ? "No" : "Yes")
  end
  DocChecks::Kyc.on_assessed(@investor_kyc, DocChecks::Assessment.new(@investor_kyc).settled?)
end

Given("the KYC's AML result is {string}") do |status|
  @investor_kyc.reload.update_columns(aml_status: nil)
  @investor_kyc.aml_status = status
  @investor_kyc.save!(validate: false)
end

Given("I override the KYC's AML status to {string} with reason {string}") do |status, reason|
  Audited.audit_class.as_user(@user) { @investor_kyc.reload.override_aml_status!(status:, reason:) }
end

Given("the KYC is submitted") do
  @investor_kyc.reload.update!(submission_status: "completed", submitted_at: Time.current)
end

Given("the KYC is verified directly") do
  Audited.audit_class.as_user(@user) { @investor_kyc.reload.update!(submission_status: "verified", verified_by_id: @user.id) }
end

Given("the KYC's form link was sent") do
  @investor_kyc.reload.update!(submission_status: "link_sent", link_sent_at: Time.current)
end

# ── Journey ───────────────────────────────────────────────────────────────────

When("the KYC's journey is evaluated") do
  @journey_record = InvestorKyc.find(@investor_kyc.id)
  WorkflowEvaluator.for(@journey_record, cause: :progress)
end

Then("the KYC has the {string} journey") do |template_name|
  instance = InvestorKyc.find(@investor_kyc.id).workflow_instances.where(evaluated: true).last
  expect(instance&.template_name).to eq(template_name)
end

Then("the KYC has no journey") do
  expect(InvestorKyc.find(@investor_kyc.id).workflow_instances).not_to exist
end

# Table columns: task | status | message (a blank message is not checked)
Then("the KYC's journey should show:") do |table|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  table.hashes.each do |row|
    result = instance.step_result(journey_position(instance, row["task"].strip)) || {}
    expect(result["status"]).to eq(row["status"]), "#{row['task']}: #{result.inspect}"
    expect(result["message"]).to eq(row["message"].strip) if row["message"].present?
  end
end

Then("the KYC's journey current task should be {string}") do |task|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("the KYC's journey should be complete") do
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
end

When("I mark {string} reviewed on the KYC") do |task|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  result = WorkflowAcknowledge.call(instance:, step_position: journey_position(instance, task), user: @user)
  expect(result.success?).to be(true), result[:errors].to_s
end

When("I sign off the KYC's Compliance sign-off") do
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  WorkflowActorResponse.create!(workflow_instance: instance, actor: @user, step_position: instance.current_step_position,
                                state: "Approved", channel: :ui, responded_at: Time.current)
  resolution = WorkflowStepResolver.call(instance: instance.reload)[:resolution]
  WorkflowAdvancer.call(instance:, resolved_state: resolution[:resolved], actor: @user, channel: :ui)
end

Then("the KYC's journey owner for reminders should be nobody") do
  expect(InvestorKyc.find(@investor_kyc.id).workflow_default_owner).to be_nil
end

Given("the investor created the KYC themselves") do
  Audited.audit_class.as_user(@investor_user) { @investor_kyc = create_journey_kyc }
end

# X6 — one check raising: the step shows the engine's error message and the error is reported
Given("the Validate documents check raises an error") do
  WorkflowChecks::InvestorKyc::ValidateDocuments.class_eval do
    alias_method :__original_call, :call
    define_method(:call) { |_kyc| raise "Bad AI answers" }
  end
end

After do
  klass = WorkflowChecks::InvestorKyc::ValidateDocuments
  if klass.method_defined?(:__original_call)
    klass.class_eval do
      alias_method :call, :__original_call
      remove_method :__original_call
    end
  end
end

When("I delete the KYC") do
  @deleted_kyc_id = @investor_kyc.id
  InvestorKyc.find(@investor_kyc.id).destroy!
end

Then("the KYC should be deleted") do
  expect(InvestorKyc.where(id: @deleted_kyc_id)).not_to exist
end

# ── Rollout (investor_kyc_journey_rollout.feature) ────────────────────────────

When("I run the KYC journey rollout for the entity") do
  run_journey_rollout(execute: false, task_name: "investor_kyc_journeys:rollout")
end

When("I run the KYC journey rollout for the entity with EXECUTE") do
  run_journey_rollout(execute: true, task_name: "investor_kyc_journeys:rollout")
end

Then("the entity should have no investor KYC journey") do
  expect(WorkflowTemplate.where(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)).not_to exist
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "InvestorKyc")).not_to exist
end

def expect_kyc_journey(entity, tasks)
  template = WorkflowTemplate.find_by!(entity:, system_key: InvestorKycJourneySetup::FULL_KEY)
  expect(template.name).to eq("Investor KYC")
  expect(template.workflow_steps.count).to eq(tasks)
end

Then("the entity should have the investor KYC journey with {int} tasks") do |tasks|
  expect_kyc_journey(@entity, tasks)
end

Then("the new company should have the investor KYC journey with {int} tasks") do |tasks|
  expect_kyc_journey(@new_entity, tasks)
end

Then("every new KYC should go to the investor KYC journey") do
  rules = WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "InvestorKyc").to_a
  expect(rules.size).to eq(1)
  expect(rules.first.workflow_template.system_key).to eq(InvestorKycJourneySetup::FULL_KEY)
  expect(rules.first.conditions).to eq([])
  expect(rules.first.auto_launch).to be(true)
end

Then("the entity should have exactly {int} investor KYC journey and {int} KYC auto-assignment rule(s)") do |templates, rules|
  expect(WorkflowTemplate.where(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY).count).to eq(templates)
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "InvestorKyc").count).to eq(rules)
end

# A company set up before the two email tasks existed: the seeded template without them, renumbered
# from 1 as it was then. What the backfill has to repair (H7, E9, E11).
Given("the investor KYC journey template predates the email tasks") do
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  template.workflow_steps.where(name: ["Set up KYC email", "Preview the email"]).destroy_all
  # Ascending: positions 1 and 2 are free now, so no collision with the unique position index
  template.workflow_steps.order(:position).each_with_index { |step, idx| step.update!(position: idx + 1) }
end

# Single-column table (header "task"): the template's tasks, in position order
Then("the investor KYC journey tasks should be:") do |table|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  expect(template.workflow_steps.order(:position).pluck(:name)).to eq(table.hashes.map { |row| row["task"].strip })
end

Then("the {string} task should be an acknowledge task checking {string} skipped by {string}") do |name, check, skip|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  step = template.workflow_steps.find_by!(name:)
  expect([step.kind, step.check_key, step.skip_key]).to eq(["acknowledge", check, skip])
  expect(step.states).to eq(WorkflowStep::ACKNOWLEDGE_STATES)
end

Given("the investor KYC journey's {string} task is removed") do |name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  template.workflow_steps.find_by!(name:).destroy!
end

Then("the investor KYC journey should have no {string} task") do |name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  expect(template.workflow_steps.where(name:)).not_to exist
end

Then("the Compliance sign-off should still have me as approver") do
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  expect(template.workflow_steps.find_by!(name: "Compliance sign-off").actor_users).to include(@user)
end

Given("the entity has its own human approval workflow for KYCs") do
  template = WorkflowTemplate.create!(entity: @entity, name: "KYC Approval", workflowable_type: "InvestorKyc")
  template.workflow_steps.create!(position: 1, name: "Approve", kind: "human", states: "Approved,Rejected",
                                  quorum_rule: "any_one", on_reject_rule: "stop")
  WorkflowAutoAssignmentRule.create!(entity: @entity, workflow_template: template, workflowable_type: "InvestorKyc",
                                     priority: 0, auto_launch: false, conditions: [])
end

When("a new angel fund company is created") do
  @new_entity = FactoryBot.create(:entity, entity_type: "Angel Fund")
end

Then("the Set up journeys menu should offer only {string}") do |label|
  find("#setup_journeys_menu_btn").click
  within("#setup_journeys_menu") do
    items = all(".dropdown-item").map { |i| i.text.strip }
    expect(items.size).to eq(1), items.inspect
    expect(items.first).to include(label)
  end
end

Then("the rollout output should not mention {string}") do |text|
  expect(@rollout_output).not_to include(text)
end

Then("the KYC's journey message for {string} should include {string}") do |task, text|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  expect(instance.step_result(journey_position(instance, task))&.dig("message").to_s).to include(text)
end

# ── KYC page (investor_kyc_journey_ui.feature) ────────────────────────────────

When("I open the KYC page") do
  visit investor_kyc_path(@investor_kyc)
  expect(page).to have_css(".breadcrumbs", text: @investor_kyc.reload.full_name.to_s)
end

Then("the KYC journey panel should be shown") do
  expect(page).to have_css("#investor_kyc_journey_card")
end

Then("the KYC journey panel should not be shown") do
  expect(page).to have_css("#investor_kyc_toggle_verified_btn, .breadcrumbs", match: :first)
  expect(page).to have_no_css("#investor_kyc_journey_card")
end

When("I click the KYC panel action and proceed") do
  find("#journey_action").click
  within("#confirmModal") { click_on("Proceed") }
end

When("I click the KYC panel action") do
  find("#journey_action").click
end

Then("the panel review action {string} should click {string}") do |label, control|
  link = find("#journey_review_action", text: label)
  expect(link["data-controller"]).to eq("journey-action")
  expect(link["data-journey-action-control-value"]).to eq(control)
end

When("I click the panel review action") do
  find("#journey_review_action").click
end

# The email tasks' second buttons go to other screens, so they navigate (no action_target to click)
Then("the panel review action {string} should link to the entity's KYC emails") do |label|
  link = find("#journey_review_action", text: label)
  expect(link["data-controller"]).to be_blank
  expect(link["href"]).to include("/custom_notifications").and include("InvestorKyc")
end

Then("the panel review action {string} should link to the new KYC email form") do |label|
  link = find("#journey_review_action", text: label)
  expect(link["href"]).to include("/custom_notifications/new").and include("InvestorKyc")
end

# Back to the fund user after the investor acted: the magic-link steps switch Capybara to their own
# session (:kyc_magic_link), and the fund user's cookies are still on the default one
When("I switch back to the fund user's session") do
  Capybara.session_name = :default
end

# Both email tasks already confirmed, for the scenarios that are about a later task
Given("the KYC's email tasks are confirmed") do
  kyc = InvestorKyc.find(@investor_kyc.id)
  WorkflowEvaluator.for(kyc, cause: :progress)
  instance = journey_instance(kyc)
  ["Set up KYC email", "Preview the email"].each do |task|
    WorkflowAcknowledge.call(instance: instance.reload, step_position: journey_position(instance, task), user: @user)
  end
end

Then("the KYC's tab {string} should be open") do |tab_id|
  expect(page).to have_css("#{tab_id}.active")
end

When("the investor submits the KYC while the page is open") do
  mark_page_for_reload_check
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.assign_attributes(submission_status: "completed", submitted_at: Time.current)
  InvestorKycUpdate.call(investor_kyc: kyc, investor_user: true, validate: false)
end

# What AmlReportAsyncDownloadJob does once the screening is back: store the result, tell the journey
When("the KYC's AML result arrives as {string} while the page is open") do |status|
  mark_page_for_reload_check
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.aml_status = status
  kyc.save!(validate: false)
  kyc.journey_progress!
end

# What DocChecks::RunJob does at the end: store the results, then tell the journey
When("the KYC's documents finish checking with {int} of {int} items needing attention while the page is open") do |failing, total|
  mark_page_for_reload_check
  step %(the KYC's documents were checked with #{failing} of #{total} items needing attention)
  InvestorKyc.find(@investor_kyc.id).journey_progress!
end

When("a colleague bulk-verifies the KYC while the page is open") do
  mark_page_for_reload_check
  InvestorKycsBulkActionJob.perform_now([@investor_kyc.id], @user.id, "verify")
end

When("I open the KYC page as the investor") do
  step "I log out"
  step "I login as the investor user"
  visit investor_kyc_path(@investor_kyc)
end

When("a user of another entity requests the KYC's journey panel") do
  outsider = FactoryBot.create(:user, entity: FactoryBot.create(:entity, entity_type: "Investment Fund"))
  outsider.add_role(:company_admin)
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(outsider, scope: :user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.get "/investor_kycs/#{@investor_kyc.id}/journey"
  @outsider_status = session.response.status
  @outsider_body = session.response.body.to_s
ensure
  Warden.test_reset!
end

Then("the journey panel request should be refused") do
  expect(@outsider_status == 403 || @outsider_status == 302 || @outsider_body.include?("Access Denied")).to be(true),
                                                                                                            "status #{@outsider_status}"
  expect(@outsider_body).not_to include("investor_kyc_journey_card")
end

# X2 — a user who may not verify: the Verify control is not on the page, so the panel's button is a
# plain link to the KYC (journey_action_controller.js finds no control to click)
module KycVerifyDenied
  mattr_accessor :active, default: false

  def toggle_verified?
    KycVerifyDenied.active ? false : super
  end
end
InvestorKycPolicy.prepend(KycVerifyDenied) unless InvestorKycPolicy <= KycVerifyDenied

Given("I may not verify KYCs") do
  KycVerifyDenied.active = true
end

After { KycVerifyDenied.active = false }

Then("the Verify control should not be on the page") do
  expect(page).to have_no_css("#investor_kyc_toggle_verified_btn")
end

Then("the panel action should be a plain link to the KYC") do
  link = find("#journey_action", text: "Verify")
  expect(URI(link["href"]).path).to eq(investor_kyc_path(@investor_kyc))
end

Then("the KYC should be verified") do
  expect(page).to have_text("successfully verified") # the toggle's redirect notice: the request has finished
  expect(InvestorKyc.find(@investor_kyc.id).submission_status).to eq("verified")
end

Given("the KYC's bank verification failed") do
  @investor_kyc.reload.update_columns(bank_verified: false, bank_verification_status: "Name does not match")
end

# ── Undo and fixes (investor_kyc_journey.feature, investor_kyc_fixes.feature) ─

# A fund user's save of the KYC form, through the same service InvestorKycsController#update uses
def fund_user_saves_kyc(kyc)
  Audited.audit_class.as_user(@user) { InvestorKycUpdate.call(investor_kyc: kyc, investor_user: false) }
end

When("a fund user ticks complete on the KYC") do
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.completed_by_investor = true
  fund_user_saves_kyc(kyc)
end

When("a fund user unticks complete on the KYC") do
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.completed_by_investor = false
  fund_user_saves_kyc(kyc)
end

When("a fund user edits the KYC's address to {string}") do |address|
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.address = address
  fund_user_saves_kyc(kyc)
end

Then("the KYC's status should be {string}") do |status|
  expect(InvestorKyc.find(@investor_kyc.id).submission_status).to eq(status)
end

Then("the KYC should have been submitted just now") do
  expect(InvestorKyc.find(@investor_kyc.id).submitted_at).to be_within(2.minutes).of(Time.current)
end

# Through the real controller actions, as the KYC page's buttons send them
When("I request updates on the KYC") do
  as_user_request(@user, :post, "/investor_kycs/#{@investor_kyc.id}/request_updates", { message: "Please fix the bank account" })
end

When("I verify the KYC from its page") do
  as_user_request(@user, :put, "/investor_kycs/#{@investor_kyc.id}/toggle_verified", {})
end

When("I unverify the KYC from its page") do
  as_user_request(@user, :put, "/investor_kycs/#{@investor_kyc.id}/toggle_verified", {})
end

When("I bulk {string} the KYCs") do |action|
  InvestorKycsBulkActionJob.perform_now(@kycs.map(&:id), @user.id, action)
end

Given("there are {int} verified individual KYCs with journeys") do |count|
  @kycs = Array.new(count) { create_journey_kyc("submission_status=verified") }
  @kycs.each { |kyc| WorkflowEvaluator.for(kyc, cause: :progress) }
  @investor_kyc = @kycs.first
end

Then("each of the KYCs should be {string} with the journey back at {string}") do |status, task|
  @kycs.each do |kyc|
    kyc = InvestorKyc.find(kyc.id)
    expect(kyc.submission_status).to eq(status)
    instance = journey_instance(kyc)
    expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
  end
end

# InvestorKycsController#edit/#update turn investors away once a KYC is completed or verified
# ("link sent", what bulk Unverify used to set, let them edit again)
Then("the investor should not be able to edit the KYC") do
  kyc = InvestorKyc.find(@investor_kyc.id)
  expect(kyc.submission_completed? || kyc.submission_verified?).to be(true)
end

When("the KYC's {string} document is replaced") do |name|
  doc = Document.where(owner_type: "InvestorKyc", owner_id: @investor_kyc.id, name:).first!
  doc.update!(file: File.new("public/sample_uploads/address_proof.pdf", "r"))
end

When("the KYC's {string} document is deleted") do |name|
  Document.where(owner_type: "InvestorKyc", owner_id: @investor_kyc.id, name:).first!.destroy!
end

Then("the KYC's journey should have moved back to {string} with {string}") do |task, note|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  position = journey_position(instance, task)
  expect(instance.current_step_position).to eq(position), instance.step_results.inspect
  result = instance.step_result(position)
  expect(result["regressed"]).to be(true), result.inspect
  history = instance.workflow_state_changes.order(:id).map { |c| [c.step_position, c.to_state, c.note] }
  expect(result["regressed_reason"].to_s).to include(note), "#{result.inspect} history=#{history.inspect}"
end

Then("the KYC's journey history should have no move back") do
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  expect(instance.workflow_state_changes.where(to_state: %w[regressed invalidated])).not_to exist
end

Then("the {string} confirmation on the KYC should have been reset") do |task|
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  expect(instance.workflow_actor_responses.active.for_step(journey_position(instance, task))).not_to exist
end

Then("the Compliance sign-off vote on the KYC should have been reset") do
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  position = journey_position(instance, "Compliance sign-off")
  expect(instance.workflow_actor_responses.active.for_step(position)).not_to exist
end

# The documents-first form: the investor uploads documents and the form is pre-filled, no submit
When("the investor uploads documents first and the form is pre-filled") do
  step %(the KYC has the documents "PAN Card, Address Proof, Photo")
  kyc = InvestorKyc.find(@investor_kyc.id)
  kyc.full_name = "Asha Ventures" # what KycDocExtractorAgent writes (save without validation)
  kyc.save!(validate: false)
end

# Everything up to and including the Compliance sign-off, with my sign-off on it
Given("the KYC is at Verify KYC with my review and sign-off") do
  step "the KYC's form link was sent"
  step "the KYC is submitted"
  step %(the KYC has the documents "PAN Card, Address Proof, Photo")
  step %(the KYC's AML result is "no_match")
  step "the KYC's journey is evaluated"
  step %(I mark "Validate documents" reviewed on the KYC)
  step %(I mark "Review KYC" reviewed on the KYC)
  # The sign-off is a vote only when an approver is set; otherwise it is n/a already
  instance = journey_instance(InvestorKyc.find(@investor_kyc.id))
  step "I sign off the KYC's Compliance sign-off" if instance.current_step_position == journey_position(instance, "Compliance sign-off")
  step %(the KYC's journey current task should be "Verify KYC")
end

# ── Per-form-type journeys (E25–E27) ──────────────────────────────────────────

Given("the entity has the KYC form types {string}") do |labels|
  # "Individual — Default, Individual — Fund IV, Non Individual — Default"
  @kyc_form_types = labels.split(",").map(&:strip).to_h do |label|
    kind, tag = label.split("—").map(&:strip)
    name = kind == "Individual" ? "IndividualKyc" : "NonIndividualKyc"
    [label, FormType.find_or_create_by!(entity: @entity, name:, tag:)]
  end
end

def create_kyc_with_form_type(label)
  form_type = @kyc_form_types.fetch(label)
  klass = form_type.name.constantize
  attrs = FactoryBot.attributes_for(:investor_kyc, verified: false, completed_by_investor: false)
                    .except(:submission_status, :verified, :completed_by_investor)
  kyc_type = form_type.name == "IndividualKyc" ? "individual" : "non_individual"
  kyc = klass.new(attrs.merge(entity: @entity, investor: @investor, kyc_type:, form_type:, submission_status: "not_sent"))
  kyc.save!(validate: false)
  kyc
end

When("a KYC is created with each form type") do
  @kycs_by_form_type = @kyc_form_types.keys.index_with { |label| create_kyc_with_form_type(label) }
end

Then("the KYCs should have the journeys:") do |table|
  table.hashes.each do |row|
    kyc = InvestorKyc.find(@kycs_by_form_type.fetch(row["form type"]).id)
    instance = kyc.workflow_instances.where(evaluated: true).last
    expect(instance&.template_name).to eq(row["journey"]), "#{row['form type']}: #{instance&.template_name.inspect}"
  end
end

When("I open the {string} workflow template and click Duplicate") do |name|
  visit workflow_template_path(WorkflowTemplate.find_by!(entity: @entity, name:))
  find("#workflow_template_duplicate_btn").click
  expect(page).to have_text("Template duplicated")
end

Then("the template {string} should have the same {int} tasks as {string}") do |copy_name, count, original_name|
  copy = WorkflowTemplate.find_by!(entity: @entity, name: copy_name)
  original = WorkflowTemplate.find_by!(entity: @entity, name: original_name)
  expect(copy.system_key).to be_nil
  expect(copy.workflow_steps.count).to eq(count)
  attrs = ->(t) { t.workflow_steps.map { |s| s.attributes.slice("position", "name", "kind", "check_key", "skip_key", "states") } }
  expect(attrs.call(copy)).to eq(attrs.call(original))
end

Given("the template {string} is renamed {string}") do |from, to|
  WorkflowTemplate.find_by!(entity: @entity, name: from).update!(name: to)
end

When("I add an auto-assignment rule to {string} for the KYC form type {string} with priority {int}") do |template_name, label, priority|
  # Built with the condition builder: Form type is <label> (workflow-rule-condition-builder)
  step %(I open a new rule for "#{template_name}")
  step %(I add the condition "Form type" "is" "#{label}")
  fill_in "workflow_auto_assignment_rule_priority", with: priority
  check "workflow_auto_assignment_rule_auto_launch"
  click_on "Save"
  expect(page).to have_text("Auto-assignment rule created")
end

Then("the rule for {string} should match only the form type {string}") do |template_name, label|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  rule = WorkflowAutoAssignmentRule.find_by!(entity: @entity, workflow_template: template)
  expect(rule.conditions).to eq([{ "attribute" => "form_type_id", "operator" => "eq", "value" => @kyc_form_types.fetch(label).id.to_s }])
end

Then("the KYC form type list on a new rule for {string} should be exactly {string}") do |template_name, labels|
  step %(I open a new rule for "#{template_name}")
  step %(the KYC form type list on the rule form should be exactly "#{labels}")
end

Given("another entity has its own KYC form type {string}") do |tag|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund")
  FormType.find_or_create_by!(entity: other, name: "IndividualKyc", tag:)
end

# Review fix, carried over to the builder — conditions typed through View as JSON save as typed
When("I add an auto-assignment rule to {string} with the conditions JSON:") do |template_name, json|
  step %(I open a new rule for "#{template_name}")
  fill_in "workflow_auto_assignment_rule_priority", with: 50
  find("#toggle_rule_conditions_json").click
  fill_in "workflow_auto_assignment_rule_conditions_json", with: json.gsub("<form type id>", @kyc_form_types.values.last.id.to_s)
  click_on "Save"
  expect(page).to have_text("Auto-assignment rule created")
end

Then("the rule for {string} should have the conditions:") do |template_name, json|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  # The newest rule: the seeded template also has its catch-all rule
  rule = WorkflowAutoAssignmentRule.where(entity: @entity, workflow_template: template).order(:id).last
  expected = JSON.parse(json.gsub("<form type id>", @kyc_form_types.values.last.id.to_s))
  expect(rule.conditions).to eq(expected)
end

Given("there is an individual KYC for the investor that was never submitted") do
  @kycs = [create_journey_kyc]
  @investor_kyc = @kycs.first
end

# ── KYC form Save guard (investor_kyc_fixes.feature) ──────────────────────────

KYC_FORM_SAVE_BTN = '[data-action="click->interim-save#submit"]'.freeze

# interim-save submits with form.submit(); replace it with a counter so the page stays put and the
# scenario can count how many submits the clicks produced
When("I open the KYC edit form with submits counted") do
  visit edit_investor_kyc_path(@investor_kyc)
  expect(page).to have_css("form.wizard_form", visible: :all)
  page.execute_script(<<~JS)
    window.kycFormSubmits = 0
    document.querySelector("form.wizard_form").submit = () => { window.kycFormSubmits += 1 }
  JS
end

# Both clicks in one script, the way a fast double-click lands before the page navigates away.
# The Save buttons sit on the wizard's last step (hidden until reached); a DOM click still runs the action.
When("I click the KYC form's Save button twice") do
  page.execute_script("const b = document.querySelector('#{KYC_FORM_SAVE_BTN}'); b.click(); b.click()")
end

Then("the KYC form should have been submitted {int} time(s)") do |count|
  expect(page.evaluate_script("window.kycFormSubmits")).to eq(count)
end

Then("the KYC form's Save button should be disabled and show {string}") do |text|
  # The same (first) Save button the click step used
  button = page.first(KYC_FORM_SAVE_BTN, visible: :all)
  expect(button.disabled?).to be(true)
  expect(button.text(:all).strip).to eq(text)
end

# ── The journey run page's flow diagram (workflow_templates/_flow_diagram) ──

# Owner on the template's step: the run page resolves owners from the live template, so this
# works after the KYC's journey has launched
Given("I own the {string} step of the KYC journey") do |step_name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: InvestorKycJourneySetup::FULL_KEY)
  template.workflow_steps.find_by!(name: step_name).update!(owner_user: @user)
end

When("I open the KYC's journey run page") do
  instance = @investor_kyc.reload.workflow_instances.where(evaluated: true).order(:created_at).last!
  visit workflow_instance_path(instance)
  expect(page).to have_css(".wffd")
end

# Case-insensitive: some labels (e.g. "If rejected") are uppercased by CSS, and Capybara matches
# the rendered text
Then("the run diagram step {string} should show {string}") do |step_name, text|
  expect(run_diagram_step(step_name)).to have_text(/#{Regexp.escape(text)}/i)
end

Then("the run diagram step {string} should not show {string}") do |step_name, text|
  expect(run_diagram_step(step_name)).to have_no_text(/#{Regexp.escape(text)}/i)
end

Then("the run diagram step {string} should show my name as owner") do |step_name|
  within(run_diagram_step(step_name)) { expect(page).to have_css(".wf-actor-chip", text: @user.full_name) }
end

When("I switch the run diagram to {string}") do |label|
  click_button(label)
end

Then("the run diagram should be laid out as a graph") do
  expect(page).to have_css(".wffd.wffd-graph")
end

Then("the run diagram should be laid out as a list") do
  expect(page).to have_css(".wffd")
  expect(page).to have_no_css(".wffd.wffd-graph")
end

# One step of the diagram: its whole node (card, sidebar and reject rule), found by the card title
def run_diagram_step(step_name)
  find(:xpath, "//div[contains(@class,'wffd-step-wrap')][.//div[contains(@class,'wffd-card-title')][normalize-space()='#{step_name}']]")
end
