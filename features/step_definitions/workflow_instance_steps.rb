# Step definitions for workflow_instances.feature

# ── Template + step setup helpers ─────────────────────────────────────────────

# Creates a template with one step from a semicolon-separated param string.
# Supports reminder_interval_days on both the template and the step.
# Step-level "nil" (string) means explicitly disabled; an integer string sets that value.
Given("there is a workflow template {string} with 1 step {string}") do |template_params, step_params|
  tattrs = parse_params(template_params)
  sattrs = parse_params(step_params)

  @workflow_template = WorkflowTemplate.create!(
    name:                  tattrs["name"],
    entity:                @entity,
    reminder_interval_days: tattrs["reminder_interval_days"].presence&.to_i
  )

  actor_users = resolve_actor_list(sattrs["actors"])

  # "nil" (string) → 0 (disabled sentinel, distinct from inherit-nil); integer string → that value; absent key → nil (inherit)
  step_reminder = if sattrs.key?("reminder_interval_days")
                    raw = sattrs["reminder_interval_days"]
                    raw == "nil" ? 0 : raw.to_i
                  end

  step = @workflow_template.workflow_steps.create!(
    position:               1,
    name:                   sattrs["name"],
    states:                 sattrs["states"] || "Approved,Rejected",
    quorum_rule:            sattrs["quorum_rule"]    || "any_one",
    on_reject_rule:         sattrs["on_reject_rule"] || "stop",
    reminder_interval_days: step_reminder
  )
  actor_users.each { |u| step.workflow_step_actors.create!(user: u) }
end

# Creates a template with multiple steps from a table.
Given("there is a workflow template {string} with {int} steps:") do |template_params, _count, table|
  tattrs = parse_params(template_params)
  @workflow_template = WorkflowTemplate.create!(name: tattrs["name"], entity: @entity)
  table.hashes.each_with_index do |row, idx|
    actor_users = resolve_actor_list(row["actors"])
    step = @workflow_template.workflow_steps.create!(
      position:        idx + 1,
      name:            row["name"],
      states:          row["states"] || "Approved,Rejected",
      quorum_rule:     row["quorum_rule"]    || "any_one",
      on_reject_rule:  row["on_reject_rule"] || "stop"
    )
    actor_users.each { |u| step.workflow_step_actors.create!(user: u) }
  end
end

Given("there is a second actor {string} in the entity") do |username|
  @actor2 = User.create!(
    first_name: username, last_name: "Actor",
    email: "#{username}@example.com",
    password: "password123",
    entity: @entity
  )
end

# Creates an active workflow instance at step 1 for the named folder.
Given("the folder {string} has an active workflow instance for {string}") do |folder_name, _template_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  @instance = WorkflowInstanceService.launch(folder, launched_by: @user)
end

# Creates an active instance already advanced to a specific step (bypasses quorum logic).
Given("the folder {string} has an active workflow instance for {string} at step {int}") do |folder_name, _template_name, step_pos|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  @instance = WorkflowInstanceService.launch(folder, launched_by: @user)
  @instance.update!(current_step_position: step_pos)
end

# ── When ──────────────────────────────────────────────────────────────────────

When("I launch the workflow for folder {string}") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  @launch_error = nil
  @instance = begin
    WorkflowInstanceService.launch(folder, launched_by: @user)
  rescue ArgumentError => e
    @launch_error = e.message
    nil
  end
end

When("I try to launch another workflow for folder {string}") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  @launch_error = nil
  begin
    WorkflowInstanceService.launch(folder, launched_by: @user)
  rescue ArgumentError => e
    @launch_error = e.message
  end
end

When("the actor submits {string} on the current step of the active instance for {string}") do |state, folder_name|
  folder    = Folder.find_by!(name: folder_name, entity: @entity)
  @instance = folder.workflow_instances.instance_active.first!
  response  = WorkflowActorResponse.create!(
    workflow_instance: @instance,
    actor:             @user,
    step_position:     @instance.current_step_position,
    state:             state,
    channel:           :ui,
    responded_at:      Time.current
  )
  result = WorkflowStepResolver.resolve(@instance.reload)
  WorkflowAdvancer.advance(@instance, resolved_state: result[:resolved], actor: @user, channel: :ui) if result[:resolved]
end

When("the actor {string} submits {string} on the current step") do |actor_name, state|
  actor = actor_name == "admin" ? @user : @actor2
  WorkflowActorResponse.create!(
    workflow_instance: @instance,
    actor:             actor,
    step_position:     @instance.current_step_position,
    state:             state,
    channel:           :ui,
    responded_at:      Time.current
  )
  result = WorkflowStepResolver.resolve(@instance.reload)
  WorkflowAdvancer.advance(@instance, resolved_state: result[:resolved], actor: actor, channel: :ui) if result[:resolved]
end

When("I archive the active workflow for folder {string}") do |folder_name|
  folder    = Folder.find_by!(name: folder_name, entity: @entity)
  @instance = folder.workflow_instances.instance_active.first!
  WorkflowArchiver.archive(@instance)
end

When("I try to remove the workflow template from folder {string}") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  # Attempt to set workflow_template_id to nil — should be blocked by model validation
  folder.update(workflow_template_id: nil)
end

# ── Then ──────────────────────────────────────────────────────────────────────

Then("the folder {string} should have an active workflow instance") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  folder.workflow_instances.instance_active.count.should == 1
end

Then("the active instance should be at step {int}") do |step_pos|
  @instance.reload.current_step_position.should == step_pos
end

Then("I should see a workflow launch error") do
  @launch_error.should_not be_nil
end

Then("the active instance for {string} should be at step {int}") do |folder_name, step_pos|
  folder    = Folder.find_by!(name: folder_name, entity: @entity)
  # After advance, the instance might be complete — check any non-archived instance
  instance  = folder.workflow_instances.where.not(status: :archived).first!
  instance.reload.current_step_position.should == step_pos
end

Then("the active instance for {string} should have status {string}") do |folder_name, expected_status|
  folder   = Folder.find_by!(name: folder_name, entity: @entity)
  # No status filter — caller may assert any status including "archived"
  instance = folder.workflow_instances.order(created_at: :desc).first!
  instance.reload.status.should == expected_status
end

Then("all previous actor responses for the instance should be archived") do
  @instance.reload.workflow_actor_responses.active.count.should == 0
end

Then("the instance resolution for {string} should be {string}") do |folder_name, expected|
  folder    = Folder.find_by!(name: folder_name, entity: @entity)
  instance  = folder.workflow_instances.instance_active.first!
  result    = WorkflowStepResolver.resolve(instance)
  result.key?(expected.to_sym).should == true
end

Then("the folder {string} should still have workflow template {string}") do |folder_name, template_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  folder.reload.workflow_template&.name.should == template_name
end

# ── Private helpers ────────────────────────────────────────────────────────────

private

# Resolves actor labels ("admin", "actor2", or email) to User records.
def resolve_actor_list(actors_str)
  return [@user] if actors_str.blank?
  actors_str.split(",").map(&:strip).map do |label|
    case label
    when "admin"  then @user
    when "actor2" then @actor2
    else User.find_by!(email: label, entity: @entity)
    end
  end.compact
end
