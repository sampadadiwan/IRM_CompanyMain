# Steps for: features/core/investor_workflow_auto_assignment.feature

# Mirrors "the folder {string} should have workflow template {string}" (workflow_template_steps.rb)
# and "the investor_kyc {string} should have workflow template {string}" (workflow_instance_steps.rb) —
# each workflowable type gets its own by established convention rather than a generic {word} step.
Then('the investor {string} should have workflow template {string}') do |investor_name, template_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @entity)
  investor.reload.workflow_assignment&.workflow_template&.name.should == template_name
end

# Proves auto-assignment (auto_launch: false) only assigns the template — it does not
# also launch an instance, unlike the Investor Onboarding rule (auto_launch: true).
Then('the investor {string} should not have an active workflow instance') do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @entity)
  investor.reload.workflow_instances.instance_active.count.should == 0
end

# Counts WorkflowInstance rows across ALL statuses (active + archived), to prove a genuinely
# NEW instance was created by a later KPI import rather than the same one being reused.
Then('the investor {string} should have exactly {int} workflow instance(s) in total') do |investor_name, expected_count|
  investor = Investor.find_by!(investor_name: investor_name, entity: @entity)
  investor.reload.workflow_instances.count.should == expected_count
end
