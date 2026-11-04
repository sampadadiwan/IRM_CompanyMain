# frozen_string_literal: true

# Portfolio Company Assistant tool resilience — features/ai/assistants/portfolio_company_assistant_resilience.feature.
# Reuses "{string} is a fund manager at {string} with the fund {string}" (ai_chat_steps.rb).

Given('Golden Angels has the portfolio company {string}') do |name|
  company_entity = FactoryBot.create(:entity, name:, entity_type: "Company")
  @portfolio_company = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: company_entity.id,
                                                    investor_name: name, category: "Portfolio Company")
end

When('the Portfolio Company Assistant for {string} takes its snapshot') do |name|
  company = Investor.find_by!(investor_name: name)
  @snapshot = PortfolioCompanyAssistantDataManager.new(user: @user, portfolio_company: company).get_portfolio_company_snapshot
end

Then('the snapshot names {string}') do |name|
  expect(@snapshot).to be_a(Hash)
  expect(@snapshot[:name]).to eq(name)
end

When('an assistant tool fails with {string}') do |message|
  failing = Object.new
  failing.define_singleton_method(:get_portfolio_company_snapshot) { raise message }
  tool = PortfolioCompanyAssistantTools::GetPortfolioCompanySnapshot.new(failing)
  tool.singleton_class.prepend(BaseAssistant::ToolErrorsAsResults)
  @tool_result = tool.call
end

Then('the model gets the error {string}') do |error|
  expect(@tool_result).to eq({ error: })
end

Given('a Portfolio Company Assistant conversation on {string} ended with an unanswered {string} call') do |name, tool_name|
  @chat = Chat.create!(user: @user, entity: @entity, owner: Investor.find_by!(investor_name: name),
                       assistant_type: "PortfolioCompanyAssistant", name: "#{name} chat", model: PortfolioCompanyAssistant::AI_MODEL)
  @chat.messages.create!(role: "user", content: "Summarise the totals")
  call_message = @chat.messages.create!(role: "assistant", content: "")
  @pending_call = RubyLLM::ActiveRecord::ToolCall.create!(message: call_message, tool_call_id: "call_1", name: tool_name, arguments: {})
end

When('the assistant prepares to answer the next question') do
  @closed = BaseAssistant.close_pending_tool_calls!(@chat)
end

Then('{int} unanswered tool call is closed with an error result') do |count|
  expect(@closed).to eq(count)
  expect(@pending_call.reload.result).to be_present
  expect(@pending_call.result.content).to include("did not complete earlier")
end

Then('the conversation accepts a new question') do
  expect { @chat.reload.to_llm.raise_if_pending_tool_calls! }.not_to raise_error
end
