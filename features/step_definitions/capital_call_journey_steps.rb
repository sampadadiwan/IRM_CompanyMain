# Step definitions for the capital call journey features (capital_call_journey*.feature).
# Engine-level journey steps (evaluation, history, reminders) are in workflow_evaluated_steps_steps.rb
# and read @journey_record, which these steps point at the capital call.

SAMPLE_NOTICE_PDF = "public/sample_uploads/sample_kyc1.pdf".freeze

# ── Seeding and launch ────────────────────────────────────────────────────────

Given("the entity's capital call journeys are seeded") do
  CapitalCallJourneySetup.call(entity: @entity)
end

# Retires both seeded journey templates, leaving them and their auto-assignment rules in place —
# the rules then match a new call but can hand it nothing (WorkflowAutoAssignmentService)
Given("the entity's capital call journey templates are disabled") do
  WorkflowTemplate.where(entity: @entity, system_key: [CapitalCallJourneySetup::FULL_KEY, CapitalCallJourneySetup::LIGHT_KEY])
                  .find_each { |template| template.update!(enabled: false) }
end

Then("the call should have no workflow template") do
  expect(@capital_call.reload.workflow_assignment).to be_nil
end

Given("the entity's capital call journeys are removed") do
  WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalCall").destroy_all
  WorkflowTemplate.where(entity: @entity, system_key: [CapitalCallJourneySetup::FULL_KEY, CapitalCallJourneySetup::LIGHT_KEY])
                  .find_each { |t| t.workflow_assignments.destroy_all && t.destroy }
end

# Drops the "imported → Light" rule so every call, imported or not, gets Full
Given("every capital call in the entity gets the Full journey") do
  light = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalCallJourneySetup::LIGHT_KEY)
  WorkflowAutoAssignmentRule.where(entity: @entity, workflow_template: light).destroy_all
end

When("an imported capital call {string} is created") do |args|
  @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity, manual_generation: true)
  key_values(@capital_call, args)
  CapitalCallCreate.call(capital_call: @capital_call)
  @capital_call.reload
end

Then("the call has the {string} journey") do |template_name|
  instance = @capital_call.reload.workflow_instances.where(evaluated: true).last
  expect(instance&.template_name).to eq(template_name)
end

Then("the call has no journey") do
  expect(@capital_call.reload.workflow_instances).not_to exist
end

# ── Evaluation and assertions ────────────────────────────────────────────────

When("the call's journey is evaluated") do
  @journey_record = @capital_call.reload
  WorkflowEvaluator.for(@journey_record, cause: :progress)
end

# Table columns: task | status | message (a blank message is not checked)
Then("the call's journey should show:") do |table|
  instance = journey_instance(@capital_call)
  table.hashes.each do |row|
    result = instance.step_result(journey_position(instance, row["task"].strip)) || {}
    expect(result["status"]).to eq(row["status"]), "#{row['task']}: #{result.inspect}"
    expect(result["message"]).to eq(row["message"].strip) if row["message"].present?
  end
end

Then("the call's journey current task should be {string}") do |task|
  instance = journey_instance(@capital_call)
  expect(instance.current_step_position).to eq(journey_position(instance, task)), instance.step_results.inspect
end

Then("the call's journey should be complete") do
  instance = journey_instance(@capital_call)
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
end

Then("the call's journey should have the tasks {string}") do |names|
  instance = journey_instance(@capital_call)
  expect(instance.snapshot_steps.pluck(:name)).to eq(names.split(",").map(&:strip))
end

Given("the call has no unit prices") do
  @capital_call.update_column(:unit_prices, {})
end

# ── Notices ───────────────────────────────────────────────────────────────────

Given("{int} investor on the call has unverified KYC") do |count|
  @capital_call.capital_remittances.includes(capital_commitment: :investor_kyc).first(count).each do |cr|
    cr.capital_commitment.investor_kyc.update_columns(verified: false)
  end
end

# Stands in for "Generate Documents": the doc generator skips investors whose KYC is unverified
When("the call's notices are generated for verified investors") do
  @capital_call.capital_remittances.includes(capital_commitment: :investor_kyc).find_each do |cr|
    next unless cr.capital_commitment.investor_kyc&.verified

    create_generated_notice(cr)
  end
end

When("the remaining investor's KYC is verified and their notice generated") do
  @capital_call.capital_remittances.includes(capital_commitment: :investor_kyc).find_each do |cr|
    next if Document.exists?(owner: cr, owner_tag: "Generated")

    cr.capital_commitment.investor_kyc.update_columns(verified: true)
    create_generated_notice(cr)
  end
end

Given("the call's notices are generated and approved") do
  @capital_call.capital_remittances.find_each { |cr| create_generated_notice(cr, approved: true) }
end

Given("the call's notices are marked sent") do
  @capital_call.capital_remittances.update_all(notification_sent: true)
end

Given("both review tasks are marked reviewed") do
  @journey_record = @capital_call.reload
  ["Review custom notification", "Check preview"].each do |task|
    instance = journey_instance(@capital_call)
    result = WorkflowAcknowledge.call(instance:, step_position: journey_position(instance, task), user: @user)
    expect(result.success?).to be(true), "#{task}: #{result[:errors]} #{instance.step_results.inspect}"
  end
end

When("the call's remittances are verified") do
  @capital_call.capital_remittances.where(verified: false).find_each do |cr|
    CapitalRemittanceVerify.call(capital_remittance: cr)
  end
end

# ── Uploads ───────────────────────────────────────────────────────────────────

When("remittances are uploaded for {int} investors on the call") do |count|
  @fund.capital_commitments.first(count).each do |commitment|
    cr = CapitalRemittance.new(capital_call: @capital_call, fund: @fund, entity: @fund.entity, investor: commitment.investor,
                               capital_commitment: commitment, folio_id: commitment.folio_id, created_by: "Upload",
                               call_basis: "Upload", status: "Pending", call_amount_cents: 1_000_000,
                               folio_call_amount_cents: 1_000_000)
    result = CapitalRemittanceCreate.call(capital_remittance: cr)
    expect(result.success?).to be(true), cr.errors.full_messages.inspect
  end
end

# ── Query shape (E19) ─────────────────────────────────────────────────────────

When("the call's journey is evaluated while counting queries") do
  @journey_record = @capital_call.reload
  @full_remittance_loads = []
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    sql = payload[:sql].to_s
    @full_remittance_loads << sql if sql.match?(/SELECT\s+"capital_remittances"\.\*/i)
  end
  WorkflowEvaluator.for(@journey_record, cause: :progress)
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
end

Then("no query selected every column of capital_remittances") do
  expect(@full_remittance_loads).to be_empty, @full_remittance_loads.first(3).inspect
end

# ── Helpers ───────────────────────────────────────────────────────────────────

def create_generated_notice(remittance, approved: false)
  Document.create!(entity_id: remittance.entity_id, owner: remittance, name: "Call Notice - #{remittance.id}",
                   owner_tag: "Generated", file: File.open(SAMPLE_NOTICE_PDF, "rb"), user_id: @user.id, approved:)
end

# ── Call page (capital_call_journey_ui.feature) ───────────────────────────────

Given("the call's notices are generated and {int} of them is approved") do |approved_count|
  @capital_call.capital_remittances.order(:id).each_with_index do |cr, idx|
    create_generated_notice(cr, approved: idx < approved_count)
  end
end

Given("{int} commitment on the call is set to skip doc gen") do |count|
  @capital_call.capital_remittances.first(count).each do |cr|
    commitment = cr.capital_commitment
    commitment.update_column(:json_fields, (commitment.json_fields || {}).merge("skip_doc_gen" => "Yes"))
  end
end

# Unapproves every access of the last investor on the call, so nobody there receives call emails
Given("{int} investor on the call has nobody subscribed to Capital Call emails") do |count|
  @capital_call.capital_remittances.order(:id).last(count).each do |cr|
    InvestorAccess.where(investor_id: cr.investor_id).update_all(approved: false)
  end
end

When("I open the capital call page") do
  visit capital_call_path(@capital_call)
  expect(page).to have_css("#capital_call_journey_card")
end

# The same page, without waiting for a visible card: a journey complete for a day or more renders
# its card hidden (workflow_instances/_journey_panel), and the breadcrumb's journey icon shows it
When("I open the call page") do
  visit capital_call_path(@capital_call)
  # The breadcrumb names the call (CapitalCallsController#set_capital_call), so this waits for the
  # page without touching the journey card either way
  expect(page).to have_css(".breadcrumbs", text: @capital_call.to_s)
end

# The shortest way to a finished Full journey: notices approved and sent, both reviews confirmed,
# the call approved, remittances paid and verified, and no unit prices so Allocate units is n/a
Given("the call's journey is complete") do
  step "the call has no unit prices"
  step "the call's notices are generated and approved"
  step "the call's journey is evaluated"
  step "both review tasks are marked reviewed"
  step "when the capital call is approved"
  step "the call's notices are marked sent"
  step "the call's remittances are fully paid"
  step "the call's remittances are verified"
  step "the call's journey is evaluated"
  instance = journey_instance(@capital_call)
  expect(instance.instance_complete?).to be(true), instance.step_results.inspect
end

# Backdating the instance, as an old journey on a long-settled call would be. The evaluator writes
# completed_at once and never rewrites it, so re-evaluating on page load leaves this alone.
Given("the call's journey was completed {int} days ago") do |days|
  journey_instance(@capital_call).update_columns(completed_at: days.days.ago)
end

# The step rail draws each task's state as an icon rather than a text glyph, so the feature's
# mark column is matched against the pill's data-journey-status instead of its text.
STEP_BAR_MARKS = {
  "\u2713" => ".journey-step[data-journey-status='passed']",
  "\u25cf" => ".journey-step[data-journey-status='current'], .journey-step[data-journey-status='error']",
  "\u21ba" => ".journey-step[data-journey-regressed='true']",
  "\u25cb" => ".journey-step[data-journey-status='not_yet']",
  "n/a" => ".journey-step[data-journey-status='na']"
}.freeze

Then("the step bar should show:") do |table|
  within("#journey_step_bar") do
    table.hashes.each do |row|
      selector = STEP_BAR_MARKS.fetch(row["mark"]) { raise "Unknown step bar mark #{row['mark'].inspect}" }
      expect(page).to have_css(selector, text: row["task"])
    end
  end
end

Then("the panel should say {string}") do |text|
  expect(page).to have_css("#journey_message", text:)
end

# The acknowledge step's second button, beside Mark reviewed (#journey_review_action)
Then("the panel review action {string} should go to {string} in this tab") do |label, path|
  link = find("#journey_review_action", text: label)
  expect(URI(link[:href]).path).to eq(path)
  expect(link[:target]).to be_blank
  # The record's own override form (the call's or the distribution's), not the fund's
  query = Rack::Utils.parse_nested_query(URI(link[:href]).query)["custom_notification"]
  record = instance_variable_get("@#{query['owner_type'].underscore}")
  expect(query["owner_id"]).to eq(record.id.to_s)
end

Then("the panel review action {string} should go to the custom notification in a new tab") do |label|
  link = find("#journey_review_action", text: label)
  expect(URI(link[:href]).path).to eq(custom_notification_path(@custom_notification))
  expect(link[:target]).to eq("_blank")
end

Then("I should see the Mark reviewed button in the journey panel") do
  expect(page).to have_css("#journey_mark_reviewed")
end

When("I click Mark reviewed in the journey panel") do
  find("#journey_mark_reviewed").click
end

When("I click Approve in the call's Actions menu") do
  within("#capital_call_#{@capital_call.id}_actions") { click_on("Actions") }
  find("#capital_call_approve_btn").click
  expect(page).to have_css("#ruleValidationModal", visible: true)
end

# The dialog doesn't repeat the journey (H12): no task from the step bar appears in it
Then("the confirmation should not mention journey steps") do
  within("#ruleValidationModal") do
    expect(page).to have_text("This will approve the capital call")
    ["Review custom notification", "Check preview", "CFO sign-off"].each { |task| expect(page).not_to have_text(task) }
  end
end

When("I confirm the dialog") do
  find("#ruleModalConfirm").click
end

Then("the call should be approved") do
  expect(page).to have_text("approved")
  expect(@capital_call.reload.approved).to be(true)
end

Then("the panel should warn {string}") do |text|
  expect(page).to have_css(".journey-warning", text:)
end

Then("the panel should not show any warnings") do
  expect(page).not_to have_css(".journey-warning")
end

# ── Undoing actions (capital_call_journey_undo.feature) ───────────────────────

# Inserts a human approval step (approver: the logged-in user) before the named task in the
# entity's Full journey; positions are shifted from the bottom up to respect the unique index
Given("the Full journey has a {string} approval step before {string}") do |name, before|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalCallJourneySetup::FULL_KEY)
  # The seeded Full journey already has a CFO sign-off with no approver: pick the user on it
  if (seeded = template.workflow_steps.find_by(name:))
    seeded.workflow_step_actors.create!(user: @user)
    next
  end
  target = template.workflow_steps.find_by!(name: before).position
  # reorder: the association already orders by position ascending, which would collide on the way up
  template.workflow_steps.where(position: target..).reorder(position: :desc).each { |s| s.update_column(:position, s.position + 1) }
  step = template.workflow_steps.create!(position: target, name:, kind: "human", states: "Approved,Rejected",
                                         quorum_rule: "any_one", on_reject_rule: "previous_step")
  step.workflow_step_actors.create!(user: @user)
end

# Notices generated and approved, both reviews confirmed — the journey waits at the sign-off
# (if there is one) or at Approve call
Given("the call is ready for sign-off") do
  step %(the call's notices are generated and approved)
  step %(the call's journey is evaluated)
  step %(both review tasks are marked reviewed)
end

Given("the call is ready for sign-off and the CFO has signed off") do
  step %(the call is ready for sign-off)
  cfo_sign_off
  ActionMailer::Base.deliveries.clear
end

# The CFO's approval vote on the current (CFO sign-off) step, as the instance page records it
def cfo_sign_off
  instance = journey_instance(@capital_call)
  WorkflowActorResponse.create!(workflow_instance: instance, actor: @user, step_position: instance.current_step_position,
                                state: "Approved", channel: :ui, responded_at: Time.current)
  resolution = WorkflowStepResolver.call(instance: instance.reload)[:resolution]
  WorkflowAdvancer.call(instance:, resolved_state: resolution[:resolved], actor: @user, channel: :ui)
end

# Signs off from elsewhere (another tab / the CFO's own session) while this page stays open
When("the CFO signs off on the call while the page is open") do
  @page_marker = SecureRandom.hex(4)
  page.execute_script("document.body.dataset.journeyMarker = '#{@page_marker}'")
  cfo_sign_off
end

When("I change the call's percentage called to {string}") do |value|
  @capital_call.reload.percentage_called = value.to_f
  # A moment later than the sign-off, so "given before the undo started" is unambiguous
  travel 1.second
  result = CapitalCallUpdate.call(capital_call: @capital_call, current_user: @user)
  expect(result.success?).to be(true), @capital_call.errors.full_messages.inspect
end

When("I recompute the call") do
  travel 1.second
  CapitalRemittancesRecomputeFeesJob.perform_now(@capital_call.id, @user.id)
end

When("I unapprove the call") do
  travel 1.second
  result = CapitalCallUnapprove.call(capital_call: @capital_call.reload, current_user: @user)
  expect(result.success?).to be(true)
end

When("I unapprove one of the call's notices on the Documents screen") do
  travel 1.second
  @unapproved_notice = Document.where(owner: @capital_call.capital_remittances, owner_tag: "Generated").first!
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.document_path(@unapproved_notice),
                  document: { approved: "0" })
  expect(@unapproved_notice.reload.approved).to be(false)
end

When("I approve that notice again") do
  @unapproved_notice.update!(approved: true, approved_by_id: @user.id)
end

# Exercises CapitalRemittanceDocJob's journey hook with the generator itself stubbed: replace the
# call's notices with new, unapproved ones as a regeneration would
When("the call's notices are regenerated by the doc job") do
  travel 1.second
  job = CapitalRemittanceDocJob.new
  call = @capital_call
  world = self # inside the stub, self is the job
  job.define_singleton_method(:generate) do |*_args, **_opts|
    Document.where(owner: call.capital_remittances, owner_tag: "Generated").find_each(&:destroy)
    call.capital_remittances.find_each { |cr| world.send(:create_generated_notice, cr) }
  end
  job.define_singleton_method(:valid_inputs) { true }
  job.perform(@capital_call.id, nil, @user.id)
end

Given("the fund has a capital call email") do
  @fund_email = CustomNotification.create!(entity: @entity, owner: @fund, for_type: "CapitalCall", subject: "Capital call",
                                           body: "Please pay", email_method: "notify_capital_remittance")
end

When("I edit the fund's capital call email") do
  travel 1.second
  as_user_request(@user, :patch, Rails.application.routes.url_helpers.custom_notification_path(@fund_email),
                  custom_notification: { subject: "Capital call — revised" })
end

Given("I remember this call as {string}") do |label|
  @remembered_calls ||= {}
  @remembered_calls[label] = @capital_call
end

Then("the journey of {string} should not have moved back") do |label|
  instance = journey_instance(@remembered_calls.fetch(label))
  expect(instance.workflow_state_changes.where(to_state: %w[regressed invalidated])).not_to exist
end

Then("the call's journey message for {string} should be {string}") do |task, message|
  instance = journey_instance(@capital_call)
  expect(instance.step_result(journey_position(instance, task))&.dig("message")).to eq(message)
end

Then("the call should be saved with percentage called {string}") do |value|
  expect(@capital_call.reload.percentage_called.to_f).to eq(value.to_f)
end

Given("the call's remittances are fully paid") do
  @capital_call.capital_remittances.find_each do |cr|
    cr.update_columns(collected_amount_cents: cr.call_amount_cents + cr.other_fee_cents)
  end
end

When("I unverify one of the call's remittances") do
  travel 1.second
  cr = @capital_call.capital_remittances.where(verified: true).first!
  CapitalRemittanceVerify.call(capital_remittance: cr, current_user: @user)
end

# Sends a request as `user` through the real controller (Warden test login on an integration session)
def as_user_request(user, verb, path, params)
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(user, scope: :user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.public_send(verb, path, params:)
  expect(session.response.status).to be < 400, session.response.body.to_s[0, 300]
ensure
  Warden.test_reset!
end

# ── Rollout (capital_call_journey_rollout.feature) ────────────────────────────

When("I run the journey rollout for the entity") do
  run_journey_rollout(execute: false)
end

When("I run the journey rollout for the entity with EXECUTE") do
  run_journey_rollout(execute: true)
end

Then("the rollout output should mention {string}") do |text|
  expect(@rollout_output).to include(text)
end

Then("the entity should have no capital call journeys") do
  expect(WorkflowTemplate.where(entity: @entity, system_key: [CapitalCallJourneySetup::FULL_KEY, CapitalCallJourneySetup::LIGHT_KEY])).not_to exist
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalCall")).not_to exist
end

Then("the entity should have the Full journey with {int} tasks and the Light journey with {int} tasks") do |full, light|
  expect(WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalCallJourneySetup::FULL_KEY).workflow_steps.count).to eq(full)
  expect(WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalCallJourneySetup::LIGHT_KEY).workflow_steps.count).to eq(light)
end

Then("imported calls should go to Light and other calls to Full") do
  rules = WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalCall").order(:priority).to_a
  expect(rules.map { |r| r.workflow_template.system_key }).to eq([CapitalCallJourneySetup::LIGHT_KEY, CapitalCallJourneySetup::FULL_KEY])
  expect(rules.first.conditions).to eq([{ "attribute" => "manual_generation", "operator" => "eq", "value" => "true" }])
  expect(rules.all?(&:auto_launch)).to be(true)
end

Then("the entity should have workflow templates enabled") do
  expect(@entity.reload.permissions.enable_workflow_templates?).to be(true)
end

Then("the entity should have exactly {int} Full and {int} Light journey") do |full, light|
  expect(WorkflowTemplate.where(entity: @entity, system_key: CapitalCallJourneySetup::FULL_KEY).count).to eq(full)
  expect(WorkflowTemplate.where(entity: @entity, system_key: CapitalCallJourneySetup::LIGHT_KEY).count).to eq(light)
end

Then("the Full journey should still have a {string} step") do |name|
  template = WorkflowTemplate.find_by!(entity: @entity, system_key: CapitalCallJourneySetup::FULL_KEY)
  expect(template.workflow_steps.where(name:)).to exist
end

Then("the entity should have exactly {int} capital call auto-assignment rules") do |count|
  expect(WorkflowAutoAssignmentRule.where(entity: @entity, workflowable_type: "CapitalCall").count).to eq(count)
end

# Runs the real rake task for this entity, capturing what it prints. task_name picks the journey
# kind (the distribution rollout feature passes capital_distribution_journeys:rollout).
def run_journey_rollout(execute:, task_name: "capital_call_journeys:rollout")
  Rails.application.load_tasks unless Rake::Task.task_defined?(task_name)
  task = Rake::Task[task_name]
  task.reenable
  ENV["ENTITY_ID"] = @entity.id.to_s
  ENV["EXECUTE"] = execute ? "1" : nil
  out = StringIO.new
  original = $stdout
  $stdout = out
  task.invoke
  @rollout_output = out.string
ensure
  $stdout = original if original
  ENV.delete("ENTITY_ID")
  ENV.delete("EXECUTE")
end

Then("the {string} confirmation should still be recorded") do |task|
  instance = journey_instance(@capital_call)
  expect(instance.workflow_actor_responses.active.for_step(journey_position(instance, task))).to exist
end

Then("the {string} confirmation should have been reset") do |task|
  instance = journey_instance(@capital_call)
  responses = instance.workflow_actor_responses.for_step(journey_position(instance, task))
  expect(responses.active).not_to exist
  expect(responses.archived).to exist
end

# E29 — the history row for a step names who moved it, how, and from which state
Then("the {string} history should record {string} from {string} by me via {string}") do |task, to_state, from_state, channel|
  instance = journey_instance(@capital_call)
  event = instance.workflow_state_changes.for_step(journey_position(instance, task)).where(to_state:).chronological.last
  expect(event).to be_present, "no #{to_state} event for #{task}"
  expect([event.from_state, event.actor_id, event.channel]).to eq([from_state, @user.id, channel])
end

Then("the {string} history should have no {string} event") do |task, to_state|
  instance = journey_instance(@capital_call)
  expect(instance.workflow_state_changes.for_step(journey_position(instance, task)).where(to_state:)).not_to exist
end

# ── Real time (J2.2) ──────────────────────────────────────────────────────────

# Runs CapitalRemittanceDocJob (generator stubbed to create the notices) while the browser stays on
# the call page; the job's journey evaluation broadcasts, and the page must update on its own
When("the call's notices are generated by the doc job while the page is open") do
  @page_marker = SecureRandom.hex(4)
  # A marker on the current DOM proves later assertions ran without a page reload
  page.execute_script("document.body.dataset.journeyMarker = '#{@page_marker}'")
  job = CapitalRemittanceDocJob.new
  call = @capital_call
  world = self # inside the stub, self is the job
  job.define_singleton_method(:generate) do |*_args, **_opts|
    call.capital_remittances.find_each { |cr| world.send(:create_generated_notice, cr) }
  end
  job.define_singleton_method(:valid_inputs) { true }
  job.perform(@capital_call.id, nil, @user.id)
end

# Same assertion as "the step bar should show:" (which waits for the update), plus proof that the
# page was not reloaded: the marker set before the job is still on the DOM
Then("without reloading, the step bar should show:") do |table|
  step "the step bar should show:", table
  expect(page.evaluate_script("document.body.dataset.journeyMarker")).to eq(@page_marker)
end

# ── The panel's action button (journey_action_controller.js) ──────────────────

# The action is a link whose href stays as a fallback; what it really does is click the named
# control on this same page, so the assertion is on the wiring, not on the href.
Then("the panel action {string} should click {string}") do |label, control_id|
  link = find("#journey_action", text: label)
  expect(link["data-controller"]).to eq("journey-action")
  expect(link["data-journey-action-control-value"]).to eq(control_id)
  expect(page).to have_css("##{control_id}", visible: :all)
end

# The window opens the Actions menu link's own URL (its ransack filter uses generated group keys,
# so it is compared whole rather than searched for a predicate name) with the approval hint.
When("I click the panel action, a new window should open on the notices awaiting approval") do
  href = find("#capital_call_view_notices_to_approve_btn", visible: :all)["href"]
  new_window = window_opened_by { find("#journey_action").click }
  within_window(new_window) do
    expect(page).to have_current_path(/documents/)
    expect(page.current_url).to end_with(URI(href).request_uri).and include("hint=approve_notices")
  end
  new_window.close
end

Then("the call page should still be open in the original window") do
  expect(page).to have_current_path(capital_call_path(@capital_call))
  expect(page).to have_css("#journey_step_bar")
end

When("I click the panel action") do
  find("#journey_action").click
  expect(page).to have_css("#ruleValidationModal", visible: true)
end

# ── Forward-moving hooks (J2.2) ───────────────────────────────────────────────

# Records, per call id, each journey re-check and each "tell open pages" broadcast, while still
# running the real methods (super). Prepended once; the recorders are reset per scenario step below.
module JourneyActivitySpy
  mattr_accessor :rechecked, :broadcast, default: []

  def journey_progress!(...)
    JourneyActivitySpy.rechecked += [id]
    super
  end

  def broadcast_journey_change
    JourneyActivitySpy.broadcast += [id]
    super
  end
end
CapitalCall.prepend(JourneyActivitySpy) unless CapitalCall <= JourneyActivitySpy

Given("journey activity on calls is recorded") do
  JourneyActivitySpy.rechecked = []
  JourneyActivitySpy.broadcast = []
end

When("the call's notices are generated by the doc job") do
  job = CapitalRemittanceDocJob.new
  call = @capital_call
  world = self # inside the stub, self is the job
  job.define_singleton_method(:generate) do |*_args, **_opts|
    call.capital_remittances.find_each { |cr| world.send(:create_generated_notice, cr) }
  end
  job.define_singleton_method(:valid_inputs) { true }
  job.perform(@capital_call.id, nil, @user.id)
end

# Notices as the generator leaves them: from the call template, so they are subject to approval
def create_template_notices
  @capital_call.capital_remittances.find_each do |cr|
    create_generated_notice(cr).update_columns(from_template_id: @call_template.id)
  end
end

When("the call's notices are generated and approved in bulk") do
  create_template_notices
  ids = Document.where(owner: @capital_call.capital_remittances, owner_tag: "Generated").pluck(:id)
  DocumentsBulkActionJob.perform_now(ids, @user.id, "Approve")
end

When("the call's notices are generated and approved by date range") do
  create_template_notices
  DocumentApprovalJob.perform_now(@entity.id, Date.yesterday, I18n.l(Time.zone.today),
                                  { user_id: @user.id, owner_type: "CapitalRemittance" })
end

# Through the real controller, as the payments screen does
When("I record full payment on each of the call's remittances") do
  @capital_call.capital_remittances.find_each do |cr|
    as_user_request(@user, :post, "/capital_remittance_payments",
                    { capital_remittance_payment: { fund_id: cr.fund_id, capital_remittance_id: cr.id, entity_id: cr.entity_id,
                                                    folio_amount: (cr.call_amount_cents + cr.other_fee_cents) / 100.0,
                                                    payment_date: Time.zone.today.iso8601 } })
  end
end

When("the call's remittances are generated by the call job") do
  CapitalCallJob.perform_now(@capital_call.id, "Generate", @user.id)
end

Then("the call's journey should have been re-checked") do
  expect(JourneyActivitySpy.rechecked).to include(@capital_call.id)
end

Then("open pages for the call should have been told about the change") do
  expect(JourneyActivitySpy.broadcast).to include(@capital_call.id)
end

Then("open pages for the call should not have been told about any change") do
  expect(JourneyActivitySpy.broadcast).not_to include(@capital_call.id)
end

Then("the call's notices should all be approved") do
  notices = Document.where(owner: @capital_call.capital_remittances, owner_tag: "Generated")
  expect(notices.count).to eq(@capital_call.capital_remittances.count)
  expect(notices.where(approved: false)).not_to exist
end

# ── Setup from the UI (rollout feature) ───────────────────────────────────────

When("I open the Workflow Templates page") do
  visit(workflow_templates_path)
  expect(page).to have_css("h1", text: "Workflow Templates")
end

# The setup buttons live in the Workflow Templates page's "Set up journeys" menu, one item per kind
When("I choose {string} from the Set up journeys menu and proceed") do |label|
  find("#setup_journeys_menu_btn").click
  within("#setup_journeys_menu") { click_on(label) }
  within("#confirmModal") { click_on("Proceed") }
end

Then("the Set up journeys menu should show {string} as done") do |label|
  find("#setup_journeys_menu_btn").click
  within("#setup_journeys_menu") { expect(page).to have_button(label, disabled: true) }
end

Then("the Set up journeys menu should not be shown") do
  expect(page).to have_css("h1", text: "Workflow Templates")
  expect(page).to have_no_css("#setup_journeys_menu")
end

Given("the user is no longer a company admin") do
  @user.remove_role(:company_admin)
end

When("I delete the call") do
  @deleted_call_id = @capital_call.id
  @deleted_instance_ids = WorkflowInstance.where(workflowable: @capital_call).pluck(:id)
  as_user_request(@user, :delete, "/capital_calls/#{@capital_call.id}", {})
end

Then("the call and its journey should be gone") do
  expect(CapitalCall.exists?(@deleted_call_id)).to be false
  expect(WorkflowAssignment.where(workflowable_type: "CapitalCall", workflowable_id: @deleted_call_id)).not_to exist
  expect(WorkflowInstance.where(id: @deleted_instance_ids)).not_to exist
end
