# frozen_string_literal: true

#
# Regression coverage for two authorization-bypass fixes made to the AI assistants:
#
#  1. AssistantsController#find_chat_owner now resolves owner_type/owner_id through
#     Pundit.policy_scope (restricted to an explicit ALLOWED_CHAT_OWNER_TYPES allowlist)
#     instead of a bare `params[:owner_type].constantize.find_by(id: params[:owner_id])`.
#     Before this fix, any authenticated user could open a chat "owned by" an arbitrary
#     record id -- including one belonging to a different tenant -- and that record's
#     display name was written into the chat's name and rendered back to them.
#
#  2. The *_assistant_data_manager.rb classes no longer route an LLM-supplied `scope`
#     string through `relation.send(scope) if relation.respond_to?(scope)`. AR relations
#     always respond_to? real methods like destroy_all/delete_all/update_all, so that
#     pattern would let a hallucinated or prompt-injected scope value (e.g. "destroy_all")
#     execute one of those against every row the current user's Pundit scope covers.

Given('the rival entity has a fund named {string}') do |name|
  @rival_fund = FactoryBot.create(:fund, entity: @another_entity, name: name)
end

Given('the rival entity has a portfolio company named {string}') do |name|
  @rival_portfolio_company = Investor.create!(
    entity_id: @another_entity.id,
    investor_name: name,
    primary_email: "#{name.parameterize}@example.com",
    category: 'Portfolio Company'
  )
end

Given('the owner user has the company_admin role') do
  @user.add_role(:company_admin)
end

Given('I am logged in as the owner user') do
  steps %(
    And I am signed in as the current user
  )
end

# Visits the real GET /assistants/assistant route with the given params -- the exact
# entry point AssistantsController#find_or_create_chat/#find_chat_owner guards.
def visit_assistant_chat(assistant_type:, owner_type: nil, owner_id: nil)
  query = { assistant_type: assistant_type, new: true }
  query[:owner_type] = owner_type if owner_type
  query[:owner_id] = owner_id if owner_id
  visit "/assistants/assistant?#{query.to_query}"
end

When('I request a Specific Fund Assistant chat owned by the rival fund') do
  visit_assistant_chat(assistant_type: 'SpecificFundAssistant', owner_type: 'Fund', owner_id: @rival_fund.id)
end

When('I request a Portfolio Company Assistant chat owned by the rival portfolio company') do
  visit_assistant_chat(assistant_type: 'PortfolioCompanyAssistant', owner_type: 'Investor', owner_id: @rival_portfolio_company.id)
end

When('I request an assistant chat with owner_type {string} and the rival user\'s id') do |owner_type|
  visit_assistant_chat(assistant_type: 'PortfolioCompanyAssistant', owner_type: owner_type, owner_id: @another_user.id)
end

Then('no chat should exist owned by the rival fund') do
  expect(Chat.where(owner_type: 'Fund', owner_id: @rival_fund.id)).to be_none
end

Then('no chat should exist owned by the rival portfolio company') do
  expect(Chat.where(owner_type: 'Investor', owner_id: @rival_portfolio_company.id)).to be_none
end

Then('no chat should exist owned by the rival user') do
  expect(Chat.where(owner_type: 'User', owner_id: @another_user.id)).to be_none
end
