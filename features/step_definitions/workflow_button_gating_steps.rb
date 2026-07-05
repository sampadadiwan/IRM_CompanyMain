# Step definitions for workflow_button_gating.feature

Given("the workflow template {string} has gated_button_labels {string}") do |template_name, labels|
  template = WorkflowTemplate.find_by!(name: template_name, entity: @entity)
  template.update!(gated_button_labels: labels)
end

# The workflow-gate Stimulus controller sets aria-disabled="true" on a matched element
# regardless of tag (button_to-rendered <button> or link_to-rendered <a>), so this
# assertion works for both without caring which markup a given action happens to use.
Then("the button labeled {string} should be disabled") do |label|
  expect(page).to have_css(%([data-workflow-gate-label="#{label}"][aria-disabled="true"]), wait: 5)
end

Then("the button labeled {string} should not be disabled") do |label|
  expect(page).to have_css(%([data-workflow-gate-label="#{label}"]), wait: 5)
  expect(page).to have_no_css(%([data-workflow-gate-label="#{label}"][aria-disabled="true"]))
end
