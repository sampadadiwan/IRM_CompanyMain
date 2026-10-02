# Step definitions for workflow_templates.feature

# ── Setup helpers ─────────────────────────────────────────────────────────────

def parse_params(str)
  # "key=val;key2=val2" → { "key" => "val", "key2" => "val2" }
  str.split(";").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    h[k.strip] = v&.strip
  end
end

# ── Given ─────────────────────────────────────────────────────────────────────

Given("the entity has employees") do
  @employees = [
    FactoryBot.create(:user, first_name: "Alice", email: "alice@example.com", entity: @entity),
    FactoryBot.create(:user, first_name: "Bob",   email: "bob@example.com",   entity: @entity)
  ]
end

# Disables the step-activation email for a single step (default is enabled).
Given("step {int} of the workflow template is set to not notify actors") do |position|
  step = @workflow_template.workflow_steps.find_by!(position: position)
  step.update!(notify_on_activation: false)
end

Given("there is a workflow template {string}") do |params_str|
  attrs = parse_params(params_str)
  @workflow_template = WorkflowTemplate.create!(
    name: attrs["name"],
    description: attrs["description"],
    reminder_interval_days: attrs["reminder_interval_days"]&.to_i,
    workflowable_type: attrs["workflowable_type"],
    entity: @entity
  )
end

# NOTE: Generic "the {word} {string} has workflow template {string}" step is in
# workflow_instance_steps.rb and covers all workflowable types including Folder.

# ── When ──────────────────────────────────────────────────────────────────────

When("I create a workflow template {string}") do |params_str|
  attrs = parse_params(params_str)
  @workflow_template = WorkflowTemplate.create!(
    name: attrs["name"],
    description: attrs["description"],
    reminder_interval_days: attrs["reminder_interval_days"]&.to_i,
    entity: @entity
  )
end

When("I try to create a workflow template {string}") do |params_str|
  attrs = parse_params(params_str)
  # Execute immediately and capture denial as a boolean (rescue-based; expect/raise_error is RSpec)
  @denied = begin
    Pundit.authorize(@user, WorkflowTemplate.new(entity: @entity), :create?)
    WorkflowTemplate.create!(name: attrs["name"], entity: @entity)
    false
  rescue Pundit::NotAuthorizedError
    true
  end
end

When("I add a step {string} to the template") do |params_str|
  attrs = parse_params(params_str)
  position = (@workflow_template.workflow_steps.maximum(:position) || 0) + 1

  actor_user_ids = if attrs["actors"]
    names = attrs["actors"].split(",").map(&:strip)
    User.where(first_name: names, entity: @entity).pluck(:id)
  end

  @workflow_template.workflow_steps.create!(
    name: attrs["name"],
    states: attrs["states"] || "Approved,Rejected,Needs Info",
    quorum_rule: attrs["quorum_rule"] || "any_one",
    on_reject_rule: attrs["on_reject_rule"] || "stop",
    position: position,
    actor_user_ids: actor_user_ids
  )
end

When("I update the workflow template name to {string}") do |new_name|
  @workflow_template.update!(name: new_name)
end

When("I delete the workflow template {string}") do |name|
  WorkflowTemplate.find_by!(name: name, entity: @entity).destroy!
end

When("I assign the workflow template {string} to the folder {string}") do |template_name, folder_name|
  template = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  folder   = Folder.find_by!(name: folder_name, entity: @entity)
  folder.workflow_assignment&.destroy
  folder.create_workflow_assignment!(workflow_template: template, created_by: @user)
end

When("I remove the workflow template from the folder {string}") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  folder.workflow_assignment&.destroy
end

# ── Then ──────────────────────────────────────────────────────────────────────

Then("the workflow template {string} should exist") do |name|
  WorkflowTemplate.find_by!(name: name, entity: @entity).should_not be_nil
end

Then("the workflow template {string} should not exist") do |name|
  WorkflowTemplate.find_by(name: name, entity: @entity).should be_nil
end

Then("the template should have {int} step(s)") do |count|
  @workflow_template.reload.workflow_steps.count.should == count
end

Then("step {int} should be named {string}") do |position, name|
  step = @workflow_template.workflow_steps.find_by!(position: position)
  step.name.should == name
end

Then("step {int} should have actor {string}") do |position, first_name|
  step = @workflow_template.workflow_steps.find_by!(position: position)
  user = User.find_by!(first_name: first_name, entity: @entity)
  step.workflow_step_actors.pluck(:user_id).should include(user.id)
end

Then("step {int} should have {int} actor(s)") do |position, count|
  step = @workflow_template.workflow_steps.find_by!(position: position)
  step.workflow_step_actors.count.should == count
end

Then("I should be denied access") do
  @denied.should == true
end

Then("the folder {string} should have workflow template {string}") do |folder_name, template_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  folder.reload.workflow_assignment&.workflow_template&.name.should == template_name
end

Then("the folder {string} should have no workflow template") do |folder_name|
  folder = Folder.find_by!(name: folder_name, entity: @entity)
  folder.reload.workflow_assignment.should be_nil
end

# ── Add / Remove step rows (Stimulus nested-form controller, requires @javascript) ──

When("I visit the edit page for the workflow template {string}") do |name|
  template = WorkflowTemplate.find_by!(name: name, entity: @entity)
  visit edit_workflow_template_path(template)
end

When("I fill in the Locked buttons field with {string}") do |value|
  fill_in "workflow_template_gated_button_labels", with: value
end

Then("the workflow template {string} should have gated_button_labels {string}") do |name, expected|
  template = WorkflowTemplate.find_by!(name: name, entity: @entity)
  template.reload.gated_button_labels.should == expected
end

Then("the workflow template show page should list {string} as locked buttons") do |labels|
  expect(page).to have_css(".wf-meta-label", text: /locked buttons/i)
  expect(page).to have_css(".wf-meta-value", text: labels)
end

When("I click {string} on the workflow template edit page") do |link_text|
  @step_rows_before = page.all(".step-row", visible: :all).count
  click_link(link_text)
end

Then("a new step row should appear on the page") do
  expect(page).to have_css(".step-row", count: @step_rows_before + 1, visible: :all)
end

When("I remove the last step row via its remove button") do
  within(all(".step-row", visible: :all).last) { find("a.btn-outline-danger").click }
end

# Persisted rows are hidden + flagged for destruction (not deleted from the DOM outright),
# so accepts_nested_attributes_for still receives the id + _destroy=1 on submit.
Then("the last step row should be hidden and marked for destruction") do
  last_row = all(".step-row", visible: :all).last
  expect(last_row[:class]).to include("d-none")
  expect(last_row.find(".step-destroy-flag", visible: false).value).to eq("1")
end

When("I save the workflow template edit form") do
  click_button("Save")
  # Wait for Turbo to complete navigation before subsequent DB assertions run
  expect(page).to have_text("successfully updated")
end
