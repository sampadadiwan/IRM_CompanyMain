# Step definitions for the fleet-wide support agent configuration health checks.
# The banner UI steps live in portfolio_scoring_agent_config_steps.rb and are shared.

# Replaces the agent's entire json_fields with the docstring JSON — scenarios
# state their exact configuration rather than layering on factory defaults.
Given("the agent json fields are:") do |doc_string|
  @support_agent.update!(json_fields: JSON.parse(doc_string))
end

# Valid full configuration for CashFlowAssistantAgent pointing at the fund
# created by "there is an existing fund" (@fund) — ids are dynamic so this
# cannot live in a feature-file docstring.
Given("the cash flow agent is configured for the existing fund") do
  @support_agent.update!(json_fields: {
    "funds"             => [{ "fund_id" => @fund.id, "name" => @fund.name }],
    "cash_tags"         => "Cash",
    "expense_tags"      => "Expense",
    "buffer_tags"       => "",
    "report_recipients" => "ops@example.com"
  })
end

# A FundUnitSetting with no ISIN — invisible to RTA reconciliation.
Given("the fund has a unit setting {string} without ISIN") do |name|
  FundUnitSetting.create!(entity_id: @entity.id, fund: @fund, name: name)
end

Then("the agent config issues should include {string}") do |fragment|
  issues = @support_agent.agent.config_issues(@support_agent)
  expect(issues.join("\n")).to include(fragment),
    "expected config issues to include '#{fragment}', got: #{issues.inspect}"
end

Then("the agent config issues should be empty") do
  issues = @support_agent.agent.config_issues(@support_agent)
  expect(issues).to be_empty, "expected no config issues, got: #{issues.inspect}"
end
