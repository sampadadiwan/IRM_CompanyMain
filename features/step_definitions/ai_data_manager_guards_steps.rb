# frozen_string_literal: true

#
# Guards on AiDataManager's LLM-facing tools. See the feature file for the three sinks these
# arguments used to reach unchecked.

Given("there is a fund with a capital call for the compliance assistant") do
  @fund = FactoryBot.create(:fund, entity: @entity)
  @capital_call = FactoryBot.create(:capital_call, fund: @fund, entity: @entity)
  @data_manager = AiDataManager.new(@fund)
end

def record_tool_response(raw)
  @tool_response = JSON.parse(raw)
rescue JSON::ParserError
  @tool_response = raw
end

When("the compliance assistant calls get_data with associated_data {string}") do |associated_data|
  record_tool_response(@data_manager.get_data(associated_data: associated_data.presence))
end

When("the compliance assistant calls get_data on {string} where {string}") do |association, where|
  record_tool_response(@data_manager.get_data(associated_data: association, where: where, count: true))
end

When("the compliance assistant calls get_data on {string} summing {string}") do |association, sum_field|
  record_tool_response(@data_manager.get_data(associated_data: association, sum_field: sum_field))
end

When("the compliance assistant calls get_latest_data on {string} ordered by {string}") do |association, order_by|
  record_tool_response(@data_manager.get_latest_data(associated_data: association, order_by: order_by))
end

Then("the tool response should be an error mentioning {string}") do |fragment|
  expect(@tool_response).to be_a(Hash)
  expect(@tool_response["error"]).to be_present
  expect(@tool_response["error"]).to include(fragment)
end

When("the compliance assistant calls get_data on {string} for rows") do |association|
  record_tool_response(@data_manager.get_data(associated_data: association))
end

Then("the tool response should be an error") do
  expect(@tool_response).to be_a(Hash)
  expect(@tool_response["error"]).to be_present
end

Then("the logged query should be capped") do
  logged = @data_manager.audit_log.find { |key, _| key.to_s.include?("Query") }&.last
  expect(logged.to_s).to include("LIMIT #{AiDataManager::MAX_ROWS}")
end

Then("the tool response should not be an error") do
  expect(@tool_response).not_to be_a(Hash)
end

Then("the fund should still exist") do
  expect(Fund.where(id: @fund.id)).to be_any
end
