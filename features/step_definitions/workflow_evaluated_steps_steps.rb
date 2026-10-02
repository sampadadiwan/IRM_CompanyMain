# Step definitions for evaluated workflows (journeys): workflow_evaluated_steps.feature and the
# capital call journey features. Records are found with find_workflowable! (workflow_instance_steps.rb).

# ── Setup ─────────────────────────────────────────────────────────────────────

# Table columns: name | kind | check | skip | actors | keep_on_regress | unlocks
Given("there is a journey template {string} with steps:") do |name, table|
  @workflow_template = WorkflowTemplate.create!(name:, entity: @entity)
  table.hashes.each_with_index do |row, idx|
    kind = row["kind"].presence || "human"
    step = @workflow_template.workflow_steps.create!(
      position: idx + 1, name: row["name"].strip, kind:,
      check_key: row["check"].presence, skip_key: row["skip"].presence,
      states: kind == "human" ? "Approved,Rejected" : nil,
      quorum_rule: "any_one", on_reject_rule: "stop",
      keep_on_regress: row["keep_on_regress"].to_s == "true",
      unlocks: row["unlocks"].presence,
      owner_user_id: row["owner"].present? ? resolve_actor_list(row["owner"]).first&.id : nil,
      reminder_interval_days: row["reminder_days"].presence&.to_i
    )
    resolve_actor_list(row["actors"]).each { |u| step.workflow_step_actors.create!(user: u) } if row["actors"].present?
  end
end

Given("the {word} {string} has flag {string} set") do |type, obj_name, flag|
  set_journey_flags(find_workflowable!(type, obj_name), [flag], "yes")
end

Given("the {word} {string} has flags {string} set") do |type, obj_name, flags|
  set_journey_flags(find_workflowable!(type, obj_name), flags.split(",").map(&:strip), "yes")
end

When("the {word} {string} has flag {string} cleared") do |type, obj_name, flag|
  set_journey_flags(find_workflowable!(type, obj_name), [flag], "no")
end

# ── Evaluation ────────────────────────────────────────────────────────────────

When("the journey for {word} {string} is evaluated") do |type, obj_name|
  @journey_record = find_workflowable!(type, obj_name)
  WorkflowEvaluator.for(@journey_record, cause: :progress)
end

When("an undoing action clears flag {string} on the {word} {string} with note {string}") do |flag, type, obj_name, note|
  @journey_record = find_workflowable!(type, obj_name)
  @journey_record.journey_undo(note:, actor: @user) do
    set_journey_flags(@journey_record, [flag], "no")
  end
end

# The undo starts, a page view evaluates while it is still running (recording the move back
# passively), then the undo finishes and evaluates with cause :undo
When("a long undoing action clears flag {string} on the {word} {string} and the journey is viewed before it finishes") do |flag, type, obj_name|
  @journey_record = find_workflowable!(type, obj_name)
  @journey_record.journey_undo(note: "Recompute", actor: @user) do
    set_journey_flags(@journey_record, [flag], "no")
    WorkflowEvaluator.for(@journey_record, cause: :progress)
  end
end

When("I mark step {string} reviewed on the {word} {string}") do |step_name, type, obj_name|
  @journey_record = find_workflowable!(type, obj_name)
  instance = journey_instance(@journey_record)
  result = WorkflowAcknowledge.call(instance:, step_position: journey_position(instance, step_name), user: @user)
  expect(result.success?).to be(true), result[:errors].to_s
end

When("the actor rejects the current step of the {word} {string} with note {string}") do |type, obj_name, note|
  @journey_record = find_workflowable!(type, obj_name)
  instance = journey_instance(@journey_record)
  WorkflowActorResponse.create!(workflow_instance: instance, actor: @user, step_position: instance.current_step_position,
                                state: "Rejected", note:, channel: :ui, responded_at: Time.current)
  resolution = WorkflowStepResolver.call(instance: instance.reload)[:resolution]
  WorkflowAdvancer.call(instance:, resolved_state: resolution[:resolved], actor: @user, channel: :ui)
end

When("a view-only employee {string} posts Mark reviewed for step {string} on the {word} {string}") do |email, step_name, type, obj_name|
  @journey_record = find_workflowable!(type, obj_name)
  instance = journey_instance(@journey_record)
  viewer = FactoryBot.create(:user, email:, first_name: "Vik", entity: @entity)
  # The shared investor_kyc fixture uses this entity as the investor's own entity, which would let
  # any employee update the KYC "as the investor"; point it elsewhere so the viewer has no rights
  @journey_record.investor.update_columns(investor_entity_id: FactoryBot.create(:entity).id)
  # Post to the real endpoint as the viewer (Warden test login on a Rails integration session), so
  # the controller's policy checks run exactly as in production
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(viewer, scope: :user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post Rails.application.routes.url_helpers.acknowledge_workflow_instance_path(instance),
               params: { step_position: journey_position(instance, step_name) }
  @viewer_response_status = session.response.status
ensure
  Warden.test_reset!
end

# ── Assertions ────────────────────────────────────────────────────────────────

Then("the journey should show:") do |table|
  instance = journey_instance(@journey_record)
  table.hashes.each do |row|
    position = journey_position(instance, row["step"].strip)
    expect(instance.step_result(position)&.dig("status")).to eq(row["status"]), "step #{row['step']}: #{instance.step_results.inspect}"
  end
end

Then("the journey current step should be {string}") do |step_name|
  instance = journey_instance(@journey_record)
  expect(instance.current_step_position).to eq(journey_position(instance, step_name))
end

Then("the journey message for {string} should include {string}") do |step_name, text|
  instance = journey_instance(@journey_record)
  expect(instance.step_result(journey_position(instance, step_name))&.dig("message").to_s).to include(text)
end

Then("the journey instance should be active") do
  expect(journey_instance(@journey_record).instance_active?).to be(true)
end

Then("the journey should be complete") do
  instance = journey_instance(@journey_record)
  expect(instance.instance_complete?).to be(true)
  expect(instance.completed_at).to be_present
end

Then("the history should show {string} for step {string}") do |to_state, step_name|
  instance = journey_instance(@journey_record)
  expect(instance.workflow_state_changes.where(to_state:, step_position: journey_position(instance, step_name))).to exist
end

Then("the history should show {string} for step {string} with note {string}") do |to_state, step_name, note|
  instance = journey_instance(@journey_record)
  changes = instance.workflow_state_changes.where(to_state:, step_position: journey_position(instance, step_name))
  expect(changes.pluck(:note)).to include(note)
end

Then("the CFO vote on step {string} should be {word}") do |step_name, state|
  instance = journey_instance(@journey_record)
  votes = instance.workflow_actor_responses.for_step(journey_position(instance, step_name))
  if state == "archived"
    expect(votes.active).not_to exist
    expect(votes.archived).to exist
  else
    expect(votes.active).to exist
  end
end

Then("no confirmation should be recorded for step {string}") do |step_name|
  instance = journey_instance(@journey_record)
  expect(instance.workflow_actor_responses.active.for_step(journey_position(instance, step_name))).not_to exist
end

# ── Helpers ───────────────────────────────────────────────────────────────────

# Sets json_fields flags read by the test checks, without callbacks noise
def set_journey_flags(record, flags, value)
  fields = (record.json_fields || {}).merge(flags.index_with { value })
  record.update_column(:json_fields, fields)
  record.reload
end

def journey_instance(record)
  record.workflow_instances.where(evaluated: true).order(created_at: :desc).first!.reload
end

def journey_position(instance, step_name)
  step = instance.snapshot_steps.find { |s| s[:name] == step_name }
  raise "No step named #{step_name}" unless step

  step[:position].to_i
end

# ── Ticks and reminders (workflow_ticks_and_reminders.feature) ───────────────

After { travel_back }

When("{int} days pass") do |days|
  travel days.days
end

When("the 15-minute tick runs") do
  ActionMailer::Base.deliveries.clear
  WorkflowEvaluateJob.perform_now
end

When("the daily reminder job runs") do
  ActionMailer::Base.deliveries.clear
  WorkflowAutoReminderJob.perform_now
end

Given("the journey for {word} {string} was launched {int} days ago") do |type, obj_name, days|
  @journey_record = find_workflowable!(type, obj_name)
  journey_instance(@journey_record).update_columns(created_at: days.days.ago)
end

Given("the {word} {string} has flag {string} set {int} days ago") do |type, obj_name, flag, days|
  record = find_workflowable!(type, obj_name)
  set_journey_flags(record, [flag], "yes")
  record.update_columns(updated_at: days.days.ago)
end

Given("the user is deactivated") do
  @user.update_columns(active: false)
end

Then("the user should receive an owner reminder for {string}") do |step_name|
  mails = ActionMailer::Base.deliveries.select { |m| m.to.include?(@user.email) && m.subject.start_with?("Needs attention: #{step_name}") }
  expect(mails).not_to be_empty, ActionMailer::Base.deliveries.map(&:subject).inspect
end

Then("no owner reminder should have been sent") do
  expect(ActionMailer::Base.deliveries.select { |m| m.subject.to_s.start_with?("Needs attention:") }).to be_empty
end

Then("step {string} should be recorded as passed {int} days ago") do |step_name, days|
  instance = journey_instance(@journey_record)
  passed_at = Time.zone.parse(instance.step_result(journey_position(instance, step_name))["passed_at"])
  expect(passed_at.to_date).to eq(days.days.ago.to_date)
end

Then("step {string} should be current since {int} days ago") do |step_name, days|
  instance = journey_instance(@journey_record)
  expect(instance.current_step_position).to eq(journey_position(instance, step_name))
  expect(instance.current_step_since.to_date).to eq(days.days.ago.to_date)
end

Then("the human-only instance for {word} {string} should be unchanged") do |type, obj_name|
  instance = find_workflowable!(type, obj_name).workflow_instances.instance_active.first!
  expect(instance.evaluated).to be(false)
  expect(instance.step_results).to be_nil
  expect(instance.workflow_state_changes.where(channel: :system)).not_to exist
end

Then("the user should receive a sign-off reset email mentioning {string}") do |text|
  mail = ActionMailer::Base.deliveries.find { |m| m.to.include?(@user.email) && m.subject.start_with?("Your sign-off was reset") }
  expect(mail).to be_present, ActionMailer::Base.deliveries.map(&:subject).inspect
  expect(mail.html_part&.body&.decoded || mail.body.decoded).to include(text)
end

# ── The journey card on a record's page, whatever the record is ───────────────
# Every type renders the same card (workflow_instances/_journey_panel) with its own frame id, so
# these match "<something>_journey_card" rather than naming calls or distributions. A page shows at
# most one journey card.

JOURNEY_CARD = "[id$='_journey_card']".freeze

# Hidden, not gone: a journey complete for a day or more renders with d-none and is brought back by
# the breadcrumb's journey icon
Then("the journey card should be hidden") do
  expect(page).to have_css(JOURNEY_CARD, visible: :hidden)
  expect(page).to have_no_css(JOURNEY_CARD, visible: :visible)
end

Then("the journey card should be visible") do
  expect(page).to have_css(JOURNEY_CARD, visible: :visible)
end

# The green strip inside the card, which is all a complete journey has in place of "What's needed now"
Then("the journey card should say the journey is complete") do
  expect(page).to have_css("#journey_panel.cc-now--done", text: "Journey complete")
end

# The breadcrumb icon next to Favourites/User Guide (layouts/_breadcrumbs, journey_reveal_controller)
When("I click the breadcrumb's journey icon") do
  find("#show-completed-journey-button").click
end

# Hidden rather than absent: it is rendered on every page and only shown by the controller when a
# completed journey card is there to toggle
Then("the breadcrumb should not offer the journey icon") do
  expect(page).to have_no_css("#show-completed-journey-button", visible: :visible)
end
