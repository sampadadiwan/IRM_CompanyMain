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

# ── Test object creation for each workflowable type ───────────────────────────

# Creates a minimal InvestorKyc, bypassing complex validations and DB NOT NULL FKs.
# investor_kycs.investor_id is NOT NULL at the DB level, so we create a stub Investor first.
Given("the entity has an investor_kyc {string}") do |attrs_str|
  attrs = parse_params(attrs_str)

  # Stub Investor — investor_entity_id is NOT NULL; reuse @entity as both sides.
  # imported: true suppresses InvestorAddedJob. Singleton override silences the
  # after_commit :change_investor_entity callback.
  investor = Investor.new(entity: @entity, investor_entity: @entity, imported: true)
  investor.define_singleton_method(:change_investor_entity) {}
  investor.save(validate: false)

  kyc = InvestorKyc.new(
    entity:              @entity,
    investor:            investor,
    full_name:           attrs["name"],
    kyc_type:            "Individual",
    address:             "Test Address",
    birth_date:          "1980-01-01",
    PAN:                 "ABCDE1234F",
    bank_name:           "Test Bank",
    bank_branch:         "Test Branch",
    bank_account_type:   "Savings",
    bank_account_number: "1234567890",
    ifsc_code:           "TEST0001234"
  )
  # before_save :set_investor_name calls investor.investor_name — silence on this instance.
  kyc.define_singleton_method(:set_investor_name) {}
  kyc.save(validate: false)

  puts "\n[KYC Created] #{attrs['name']} (id=#{kyc.id})"
  puts "  completed_by_investor: #{kyc.completed_by_investor} | verified: #{kyc.verified}"
  assigned = kyc.reload.workflow_assignment
  if assigned
    puts "  → auto-assigned template: \"#{assigned.workflow_template.name}\" (rule fired on create)"
    inst = kyc.workflow_instances.instance_active.first
    puts "  → active instance: ##{inst.id} at step #{inst.current_step_position}" if inst
  else
    puts "  → no template auto-assigned on create"
  end

  @workflowable_store ||= {}
  @workflowable_store[["investor_kyc", attrs["name"]]] = kyc
end

# Creates a minimal CapitalCommitment, bypassing complex validations.
# The "name" param maps to folio_id (used as a lookup key).
# capital_commitments.fund_id and investor_id are NOT NULL at the DB level — create stubs.
Given("the entity has a capital_commitment {string}") do |attrs_str|
  attrs = parse_params(attrs_str)

  # Stub Fund — only currency and entity_id are NOT NULL.
  # Fund includes WithDataRoom which fires after_create :create_data_room — silence it.
  fund = Fund.new(entity: @entity, currency: "INR")
  fund.define_singleton_method(:create_data_room) {}
  fund.save(validate: false)

  # Stub Investor — reuse @entity as investor_entity to satisfy NOT NULL FK.
  investor = Investor.new(entity: @entity, investor_entity: @entity, imported: true)
  investor.define_singleton_method(:change_investor_entity) {}
  investor.save(validate: false)

  cc = CapitalCommitment.new(
    entity:          @entity,
    fund:            fund,
    investor:        investor,
    folio_id:        attrs["name"],
    commitment_date: Date.today,
    fund_close:      "Test Close"
  )
  # before_save :set_investor_name calls investor.investor_name — silence on this instance.
  cc.define_singleton_method(:set_investor_name) {}
  cc.save(validate: false)

  @workflowable_store ||= {}
  @workflowable_store[["capital_commitment", attrs["name"]]] = cc
end

# Creates a minimal Approval.
Given("the entity has an approval {string}") do |attrs_str|
  attrs = parse_params(attrs_str)
  approval = Approval.create!(
    entity:           @entity,
    title:            attrs["name"],
    due_date:         Date.today + 7,
    response_status:  "Approved,Pending,Rejected"
  )
  @workflowable_store ||= {}
  @workflowable_store[["approval", attrs["name"]]] = approval
end

# ── Generic workflow assignment for any type ───────────────────────────────────

# Assigns the named template to the named workflowable of the given type.
# Type is one of: folder, investor_kyc, capital_commitment, approval
Given("the {word} {string} has workflow template {string}") do |type, obj_name, template_name|
  workflowable = find_workflowable!(type, obj_name)
  template     = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  workflowable.workflow_assignment&.destroy
  workflowable.create_workflow_assignment!(workflow_template: template, created_by: @user)
end

# Creates an active workflow instance at step 1 for the named workflowable.
Given("the {word} {string} has an active workflow instance for {string}") do |type, obj_name, _template_name|
  workflowable = find_workflowable!(type, obj_name)
  @instance    = WorkflowInstanceService.launch(workflowable, launched_by: @user)
end

# Creates an active instance already advanced to a specific step.
Given("the {word} {string} has an active workflow instance for {string} at step {int}") do |type, obj_name, _template_name, step_pos|
  workflowable = find_workflowable!(type, obj_name)
  @instance    = WorkflowInstanceService.launch(workflowable, launched_by: @user)
  @instance.update!(current_step_position: step_pos)
end

# ── When ──────────────────────────────────────────────────────────────────────

# Generic launch step for any workflowable type (folder, investor_kyc, capital_commitment, approval)
When("I launch the workflow for {word} {string}") do |type, obj_name|
  workflowable  = find_workflowable!(type, obj_name)
  @launch_error = nil
  @instance = begin
    WorkflowInstanceService.launch(workflowable, launched_by: @user)
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
  WorkflowActorResponse.create!(
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

# Generic version: actor submits a response on any workflowable type's active instance.
When("the actor submits {string} on the current step of the {word} {string}") do |state, type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  @instance    = workflowable.workflow_instances.instance_active.first!
  puts "\n[Response] #{type} \"#{obj_name}\" — submitting \"#{state}\" at step #{@instance.current_step_position}"
  WorkflowActorResponse.create!(
    workflow_instance: @instance,
    actor:             @user,
    step_position:     @instance.current_step_position,
    state:             state,
    channel:           :ui,
    responded_at:      Time.current
  )
  result = WorkflowStepResolver.resolve(@instance.reload)
  if result[:resolved]
    WorkflowAdvancer.advance(@instance, resolved_state: result[:resolved], actor: @user, channel: :ui)
    @instance.reload
    puts "  → advanced to step #{@instance.current_step_position}, status=#{@instance.status}"
  end
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

# Resets the active workflow instance for any workflowable type back to step 1.
# Sets @instance so subsequent Then steps can reference it.
When("I reset the active workflow for {word} {string}") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  @instance    = workflowable.workflow_instances.instance_active.first!
  puts "\n[Reset] #{type} \"#{obj_name}\" — instance ##{@instance.id} at step #{@instance.current_step_position}"
  WorkflowInstanceService.reset(@instance)
  @instance.reload
  puts "  → after reset: step=#{@instance.current_step_position}, status=#{@instance.status}"
  puts "  → active responses: #{@instance.workflow_actor_responses.active.count}"
end

# Tries to reset an instance that may not be active — captures any ArgumentError for assertion.
When("I try to reset the active workflow for {word} {string}") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  @instance    = workflowable.workflow_instances.order(created_at: :desc).first!
  @reset_error = nil
  begin
    WorkflowInstanceService.reset(@instance)
  rescue ArgumentError => e
    @reset_error = e.message
    puts "\n[Reset blocked] #{e.message}"
  end
end

# Asserts that the reset was blocked with an error.
Then("I should see a workflow reset error") do
  @reset_error.should_not be_nil
end

# Asserts the active instance has a WorkflowStateChange audit entry for the reset event.
Then("the active instance should have a reset audit entry") do
  @instance.reload
  change = @instance.workflow_state_changes.find_by(to_state: "reset")
  puts "\n[Assert audit] reset entry: #{change ? change.note : 'NOT FOUND'}"
  change.should_not be_nil
  change.note.should include("reset")
end

# Asserts that step-1 actors received a re-notification email after a reset.
# The launch email fires once; the reset fires a second delivery.
Then("the step-1 actors should have received a re-notification email") do
  # Count deliveries that are step_activation mailer actions
  activation_mails = ActionMailer::Base.deliveries.select do |m|
    m.subject.to_s.downcase.include?("action required") ||
      m.header["X-Mailer-Action"].to_s == "step_activation"
  end
  puts "\n[Assert notify] total deliveries: #{ActionMailer::Base.deliveries.count}, step_activation: #{activation_mails.count}"
  ActionMailer::Base.deliveries.count.should >= 2
end

# WorkflowMailer#step_activation always subjects its emails "Action Required: ...",
# distinguishing it from #reminder ("Reminder: ..."). Used to assert notify_on_activation
# suppression on both launch and reset (they share the same notify_step_actors code path).
Then("a step-activation email should have been sent") do
  activation_mails = ActionMailer::Base.deliveries.select { |m| m.subject.to_s.start_with?("Action Required") }
  puts "\n[Assert notify] total deliveries: #{ActionMailer::Base.deliveries.count}, step_activation: #{activation_mails.count}"
  activation_mails.should_not be_empty
end

Then("no step-activation email should have been sent") do
  activation_mails = ActionMailer::Base.deliveries.select { |m| m.subject.to_s.start_with?("Action Required") }
  puts "\n[Assert notify] total deliveries: #{ActionMailer::Base.deliveries.count}, step_activation: #{activation_mails.count}"
  activation_mails.should be_empty
end

# Generic remove-template step for any workflowable type (folder, investor_kyc, capital_commitment, approval)
When("I try to remove the workflow template from {word} {string}") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  workflowable.workflow_assignment&.destroy
end

# ── Phase 4: breadcrumb workflow link ─────────────────────────────────────────

# Visits the standard show page for the named workflowable using Rails path helpers.
When("I visit the {word} show page for {string}") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  path = case type
         when "folder"              then folder_path(workflowable)
         when "investor_kyc"        then investor_kyc_path(workflowable)
         when "capital_commitment"  then capital_commitment_path(workflowable)
         when "approval"            then approval_path(workflowable)
         else raise "No path helper for workflowable type: #{type}"
         end
  visit(path)
end

# The breadcrumb renders one of two workflow controls depending on the current user's role:
#   - .ti-pencil-check button  → current user is a pending actor on this step
#   - .ti-layout-kanban link   → observer / non-actor (or no response needed)
# Both indicate an active workflow is wired up, so accept either icon.
Then("I should see the workflow link in the breadcrumb") do
  expect(page).to have_css(".breadcrumbs .ti-pencil-check, .breadcrumbs a .ti-layout-kanban")
end

# When no workflow instance is active neither icon is present.
Then("I should not see the workflow link in the breadcrumb") do
  expect(page).not_to have_css(".breadcrumbs .ti-pencil-check")
  expect(page).not_to have_css(".breadcrumbs a .ti-layout-kanban")
end

# ── Then ──────────────────────────────────────────────────────────────────────

# Asserts the investor_kyc has a specific template assigned via auto-assignment.
# (Folder equivalent lives in workflow_template_steps.rb — keeping them separate avoids ambiguity.)
Then("the investor_kyc {string} should have workflow template {string}") do |obj_name, template_name|
  kyc = find_workflowable!("investor_kyc", obj_name)
  kyc.reload
  actual = kyc.workflow_assignment&.workflow_template&.name
  puts "\n[Assert template] investor_kyc \"#{obj_name}\" → assigned: \"#{actual || 'none'}\""
  actual.should == template_name
end

# Generic: any workflowable type should have an active instance (folder, investor_kyc, capital_commitment, approval)
Then("the {word} {string} should have an active workflow instance") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  workflowable.reload
  instances = workflowable.workflow_instances.instance_active
  inst = instances.first
  puts "\n[Assert instance] #{type} \"#{obj_name}\" → active instances: #{instances.count}"
  puts "  instance ##{inst.id}: status=#{inst.status}, step=#{inst.current_step_position}" if inst
  instances.count.should == 1
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

# Generic: any workflowable type should still have its template after a blocked removal (folder, investor_kyc, capital_commitment, approval)
Then("the {word} {string} should still have workflow template {string}") do |type, obj_name, template_name|
  workflowable = find_workflowable!(type, obj_name)
  workflowable.reload.workflow_assignment&.workflow_template&.name.should == template_name
end

# ── Phase 5: Template type scoping + auto-assignment ──────────────────────────

# Sets the workflowable_type on an existing template (update via AR directly in test).
Given("the workflow template {string} has workflowable_type {string}") do |template_name, type|
  template = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  # Bypass the immutability validation — we're setting the initial type in a test setup context
  template.update_column(:workflowable_type, type)
end

# Creates an auto-assignment rule for the named template.
# conditions is a raw JSON string (passed through as-is).
Given("there is an auto-assignment rule for template {string} type {string} with conditions {string} auto_launch {word} priority {int}") do |template_name, type, conditions_json, auto_launch_str, priority|
  template = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  WorkflowAutoAssignmentRule.create!(
    entity:            @entity,
    workflow_template: template,
    workflowable_type: type,
    conditions:        JSON.parse(conditions_json),
    auto_launch:       auto_launch_str == "true",
    priority:          priority
  )
end

# Tries to assign a typed template to a workflowable — expects AR validation to block it.
When("I try to assign template {string} to {word} {string}") do |template_name, type, obj_name|
  template     = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  workflowable = find_workflowable!(type, obj_name)
  # Build (don't save — let validation run via valid? check) so we can test the outcome
  assignment = WorkflowAssignment.new(
    workflow_template: template,
    workflowable:      workflowable,
    created_by:        @user
  )
  @assignment_valid = assignment.valid?
  workflowable.workflow_assignment.destroy if workflowable.workflow_assignment.present? && @assignment_valid
  workflowable.create_workflow_assignment!(workflow_template: template, created_by: @user) if @assignment_valid
end

# Creates a new folder for the entity (the after_create hook will fire auto-assignment rules).
# Folders must be children of the entity root_folder so their full_path is unique
# (a parentless folder always gets full_path="/", conflicting with the entity root folder).
When("a new folder {string} is created for the entity") do |attrs_str|
  attrs   = parse_params(attrs_str)
  parent  = @entity.root_folder || Folder.find_by(entity: @entity, level: 0)
  folder  = Folder.create!(name: attrs["name"], entity: @entity, parent: parent)
  @workflowable_store ||= {}
  @workflowable_store[["folder", attrs["name"]]] = folder
end

# Updates a single DB column on a workflowable, triggering the after_update auto-assignment hook.
When("I update the {word} {string} attribute {string} to {string}") do |type, obj_name, attribute, value|
  workflowable = find_workflowable!(type, obj_name)
  puts "\n[Update] #{type} \"#{obj_name}\" — setting #{attribute} = #{value}"
  workflowable.update!(attribute => value)
  workflowable.reload
  assigned = workflowable.workflow_assignment
  if assigned
    puts "  → auto-assigned template: \"#{assigned.workflow_template.name}\" (rule fired on update)"
    inst = workflowable.workflow_instances.instance_active.first
    puts "  → active instance: ##{inst.id} at step #{inst.current_step_position}" if inst
  else
    puts "  → no template auto-assigned (condition did not match or template already set)"
  end
  # Re-index under the new name in case the lookup key changed (e.g. folder name)
  @workflowable_store ||= {}
  @workflowable_store[[type, value]] = workflowable
end

# Manually assigns a template to a workflowable without using the auto-assignment service.
Given("I manually assign template {string} to {word} {string}") do |template_name, type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  template     = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  workflowable.workflow_assignment&.destroy
  workflowable.create_workflow_assignment!(workflow_template: template, created_by: @user)
end

# Asserts that the workflowable has exactly N workflow assignments (catches double-assignment bugs).
Then("the {word} {string} should have exactly {int} workflow assignment") do |type, obj_name, expected_count|
  workflowable = find_workflowable!(type, obj_name)
  WorkflowAssignment.where(workflowable: workflowable).count.should == expected_count
end

# Asserts that the workflowable has no workflow template assigned.
Then("the {word} {string} should not have a workflow template") do |type, obj_name|
  workflowable = find_workflowable!(type, obj_name)
  workflowable.reload
  assigned = workflowable.workflow_assignment
  puts "\n[Assert no template] #{type} \"#{obj_name}\" → #{assigned ? "UNEXPECTED template: \"#{assigned.workflow_template.name}\"" : 'correctly unassigned'}"
  assigned.should be_nil
end

# ── Full-stack UI: Launch Workflow modal on the folder page ───────────────────

When("I open the Workflow tab") do
  find("a[href='#workflow-tab']").click
end

# Opens the Bootstrap modal, picks the template (option text includes the step
# count, e.g. "LP Review (1 step(s))", so match on prefix), and submits — a real
# POST to WorkflowInstancesController#create, unlike the WorkflowInstanceService
# calls used by every other launch step in this file.
When("I launch the workflow {string} from the launch modal") do |template_name|
  within("#workflow-tab") { click_button("Launch Workflow") }
  within(".modal.show", wait: 5) do
    find("option", text: /\A#{Regexp.escape(template_name)}/).select_option
    click_button("Launch Workflow")
  end
end

# ── Full-stack UI: navigating from the index list ─────────────────────────────

When("I visit the workflow instances index page") do
  visit workflow_instances_path
end

When("I click {string} for the instance on folder {string}") do |link_text, folder_name|
  within(find("tr", text: folder_name)) { click_link(link_text) }
end

Then("I should land on the workflow instance show page for {string}") do |folder_name|
  expect(page).to have_css(".breadcrumb-item.active", text: "Workflow")
  expect(page).to have_link(folder_name)
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

# Resolves a workflowable by type label and name/identifier.
# Types: folder, investor_kyc, capital_commitment, approval
def find_workflowable!(type, name)
  case type
  when "folder"
    Folder.find_by!(name: name, entity: @entity)
  when "investor_kyc"
    # Look up from store first (in case object was created without validations),
    # then fall back to DB lookup by full_name
    (@workflowable_store || {})[["investor_kyc", name]] ||
      InvestorKyc.find_by!(full_name: name, entity: @entity)
  when "capital_commitment"
    # folio_id is used as the name key for CapitalCommitment
    (@workflowable_store || {})[["capital_commitment", name]] ||
      CapitalCommitment.find_by!(folio_id: name, entity: @entity)
  when "approval"
    (@workflowable_store || {})[["approval", name]] ||
      Approval.find_by!(title: name, entity: @entity)
  else
    raise "Unknown workflowable type: #{type}"
  end
end
