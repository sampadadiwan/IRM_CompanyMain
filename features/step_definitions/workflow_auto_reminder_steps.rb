# Step definitions for workflow_auto_reminders.feature
# The shared template+step creator lives in workflow_instance_steps.rb (handles reminder_interval_days too).
require 'csv'

# ── Setup ─────────────────────────────────────────────────────────────────────

# Back-dates the instance's updated_at so the reminder job thinks it has been idle
Given("the instance has been idle for {int} days") do |days|
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  @instance.update_columns(updated_at: days.days.ago)
end

Given("the actor {string} has already responded {string} to the current step") do |email, state|
  actor     = User.find_by!(email: email, entity: @entity)
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  WorkflowActorResponse.create!(
    workflow_instance: @instance,
    actor:             actor,
    step_position:     @instance.current_step_position,
    state:             state,
    channel:           :ui,
    responded_at:      Time.current
  )
  # Run the full resolver+advancer chain so WorkflowStateChange records are written.
  # If the quorum is satisfied the instance advances (or completes), which is correct — the
  # reminder job won't pick up a non-active instance, and the audit trail has real rows.
  result = WorkflowStepResolver.resolve(@instance.reload)
  WorkflowAdvancer.advance(@instance, resolved_state: result[:resolved], actor: actor, channel: :ui) if result[:resolved]
end

# ── When ──────────────────────────────────────────────────────────────────────

# The test env uses the :inline ActiveJob adapter, so deliver_later runs synchronously
# and emails land in ActionMailer::Base.deliveries (not enqueued_jobs).
When("the auto-reminder job runs") do
  ActionMailer::Base.deliveries.clear
  WorkflowAutoReminderJob.new.perform
end

When("I send a manual reminder for the active instance") do
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  @folder   ||= @instance.folder
  ActionMailer::Base.deliveries.clear

  # Simulate the same logic as WorkflowInstancesController#send_reminder
  step_data    = @instance.current_step_data
  responded    = @instance.workflow_actor_responses.active.for_step(@instance.current_step_position).pluck(:actor_id)
  pending_ids  = Array(step_data[:actor_ids]).map(&:to_i) - responded

  pending_ids.each do |actor_id|
    actor = User.find_by(id: actor_id)
    next unless actor

    WorkflowMailer.with(
      user_id:       actor.id,
      entity_id:     @folder.entity_id,
      instance_id:   @instance.id,
      step_position: @instance.current_step_position
    ).reminder.deliver_later

    WorkflowStateChange.create!(
      workflow_instance: @instance,
      step_position:     @instance.current_step_position,
      actor:             actor,
      from_state:        nil,
      to_state:          "reminder_sent",
      note:              "Manual reminder sent",
      channel:           :auto_reminder
    )
  end
end

When("I export the audit trail for the active instance") do
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  changes = @instance.workflow_state_changes.chronological.includes(:actor)

  @exported_csv = CSV.generate(headers: true) do |csv|
    csv << %w[Timestamp Step Actor From\ State To\ State Channel Note]
    changes.each do |sc|
      csv << [
        sc.created_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
        sc.step_position,
        sc.actor&.full_name || "System",
        sc.from_state.presence || "—",
        sc.to_state,
        sc.channel.humanize,
        sc.note.presence || ""
      ]
    end
  end
end

# ── Then ──────────────────────────────────────────────────────────────────────

# Checks ActionMailer::Base.deliveries (inline adapter delivers synchronously).
Then("a reminder email should be enqueued for {string}") do |email|
  actor     = User.find_by!(email: email, entity: @entity)
  delivered = ActionMailer::Base.deliveries.any? { |mail| mail.to.include?(actor.email) }
  delivered.should == true
end

Then("no reminder email should be enqueued for {string}") do |email|
  actor     = User.find_by!(email: email, entity: @entity)
  delivered = ActionMailer::Base.deliveries.any? { |mail| mail.to.include?(actor.email) }
  delivered.should == false
end

Then("a reminder state change should be logged for the instance") do
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  logged = @instance.workflow_state_changes
                    .where(channel: :auto_reminder, to_state: "reminder_sent")
                    .exists?
  logged.should == true
end

Then("the CSV should include a row with to_state {string}") do |state|
  table = CSV.parse(@exported_csv, headers: true)
  row   = table.find { |r| r["To State"] == state }
  row.should_not be_nil
end

Then("the CSV should have the correct headers") do
  table   = CSV.parse(@exported_csv, headers: true)
  headers = table.headers
  headers.should include("Timestamp", "Step", "Actor", "To State", "Channel")
end
