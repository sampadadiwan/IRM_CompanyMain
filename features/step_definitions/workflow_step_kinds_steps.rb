# Step definitions for workflow_step_kinds.feature (capital-call-journey phase 1).
# Template setup steps ("there is a workflow template", "I add a step") are in workflow_template_steps.rb.

Then("step {int} should be of kind {string}") do |position, kind|
  step = @workflow_template.workflow_steps.find_by!(position:)
  expect(step.kind).to eq(kind)
end

Then("step {int} should have states {string}") do |position, states|
  step = @workflow_template.workflow_steps.find_by!(position:)
  expect(step.states).to eq(states)
end

Then("no step of the template should be evaluated from data") do
  expect(@workflow_template.workflow_steps.reload.none?(&:evaluated?)).to be(true)
end

# Builds (but only keeps if valid) a step of the given kind with the given check key
When("I try to add a {string} step {string} with check {string}") do |kind, name, check_key|
  position = (@workflow_template.workflow_steps.maximum(:position) || 0) + 1
  @step = @workflow_template.workflow_steps.build(name:, kind:, check_key: check_key.presence, position:)
  @step_saved = @step.save
end

Then("the step should not be saved with the error {string}") do |message|
  expect(@step_saved).to be(false)
  expect(@step.errors.full_messages).to include(message)
end

Then("the step should be saved with kind {string} and states {string}") do |kind, states|
  expect(@step_saved).to be(true)
  @step.reload
  expect(@step.kind).to eq(kind)
  expect(@step.states).to eq(states)
end

Then("the check options for the template should include {string}") do |key|
  expect(WorkflowChecks::Registry.keys_for(@workflow_template.workflowable_type)).to include(key)
end

Then("the check options for the template should not include {string}") do |key|
  expect(WorkflowChecks::Registry.keys_for(@workflow_template.workflowable_type)).not_to include(key)
end

# ── Step editor screen ─────────────────────────────────────────────────────────

When("I visit the new step page for the workflow template {string}") do |name|
  template = WorkflowTemplate.find_by!(name:, entity: @entity)
  visit new_workflow_template_workflow_step_path(template)
end

Then("I should see the step kinds {string}") do |labels|
  labels.split(",").map(&:strip).each do |label|
    expect(page).to have_field(label, type: "radio")
  end
end

Then("the Check list should offer {string} and not {string}") do |offered, hidden|
  expect(page).to have_select("Check", with_options: [offered], visible: :all)
  expect(page).not_to have_select("Check", with_options: [hidden], visible: :all)
end

When("I fill in the step name {string}, choose kind {string} and save without a check") do |name, kind|
  fill_in "Name", with: name
  choose kind
  click_button "Save"
end
