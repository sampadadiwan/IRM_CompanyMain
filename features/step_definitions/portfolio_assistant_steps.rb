# frozen_string_literal: true

# Step definitions for the Portfolio Assistant chat provider scenarios.
#
# These exercise PortfolioAssistantChatProvider directly without spinning
# up the full GenericChatAgent / LLM round-trip. Mirrors the LP Assistant
# step style: instantiate the adapter, drive routing via the `target`
# argument, assert on the wrapped assistant's class and delegations.

Given('there is a portfolio company {string} for the entity') do |attrs_string|
  attrs = attrs_string.split(';').map { |kv| kv.split('=', 2) }.to_h
  name = attrs.fetch('name')
  @portfolio_company = Investor.create!(
    entity_id: @entity.id,
    investor_name: name,
    primary_email: "#{name.parameterize}@example.com",
    category: 'Portfolio Company'
  )
end

Given('a SupportAgent of type {string} exists for the entity') do |agent_type|
  @support_agent = SupportAgent.create!(
    entity: @entity,
    name: agent_type.underscore.humanize,
    agent_type: agent_type,
    enabled: true,
    json_fields: {
      'chat_config' => { 'enabled' => true }
    }
  )
end

When('the chat provider is resolved with target nil') do
  @provider = BaseChatProvider.resolve(
    support_agent: @support_agent, target: nil, analyst: @user
  )
end

When('the chat provider is resolved with target the portfolio company {string}') do |_name|
  @provider = BaseChatProvider.resolve(
    support_agent: @support_agent, target: @portfolio_company, analyst: @user
  )
end

When('the chat provider is resolved with target the FM entity') do
  @provider = BaseChatProvider.resolve(
    support_agent: @support_agent, target: @entity, analyst: @user
  )
end

Then('the provider class should be {string}') do |klass|
  expect(@provider.class.name).to eq(klass)
end

Then('the wrapped assistant class should be {string}') do |klass|
  expect(@provider.send(:wrapped_assistant).class.name).to eq(klass)
end

Then('the provider mode should be {string}') do |mode|
  expect(@provider.send(:mode).to_s).to eq(mode)
end

Then("the provider's tools count should match the wrapped assistant's tools count") do
  expect(@provider.tools.size).to eq(@provider.send(:wrapped_assistant).tools.size)
end

Then('every provider tool should have a non-empty description') do
  bad = @provider.tools.reject { |t| t.description.is_a?(String) && !t.description.strip.empty? }
  expect(bad).to be_empty,
                      "tools missing description: #{bad.map { |tool| tool.class.name }.inspect}"
end

Then("the provider's system prompt should equal the wrapped assistant's system prompt") do
  expect(@provider.system_prompt).to eq(@provider.send(:wrapped_assistant).system_prompt)
end
