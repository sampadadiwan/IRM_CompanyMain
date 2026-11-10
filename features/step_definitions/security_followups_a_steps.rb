# frozen_string_literal: true

# Steps for features/security/security_review_2026_10_followups.feature — follow-ups F1 (Customer Support
# Agent SQL tool scoped by FmQueryScope), F2 (tasks heading / kanban source name only visible records),
# F3 (CiProfile details sanitized) and F4 (portfolio report agent in the company's firm).
# Design: docs/security/security_review_2026_10.md (cards H5, L13, L14, C3).
#
# Reused from elsewhere:
#   lp_assistant_steps.rb           — "the query response should include …" (reads @run_query_response)
#   lp_portfolio_steps.rb           — "the assistant answer should (not) name …" (reads @run_query_response)
#   security_core_medium_a_steps.rb — "the firm … with company admin …", "… has an investor …", "… is signed in",
#                                     "the response (does not) mention(s) …", "the page loads", cma_* helpers
#   ai_portfolio_reports_steps.rb   — "a portfolio company … exists"
#   login.rb                        — "Im logged in as a user … for an entity …"

module SecurityFollowupsAHelpers
  # F1: the fund manager firms of the scenario, by name
  def sfa_firms
    @sfa_firms ||= {}
  end

  # F1: the support SQL tool exactly as FmCsChatProvider wires it for this firm's CS agent and FM user
  def sfa_fm_query_tool(firm_name)
    firm = sfa_firms.fetch(firm_name)
    provider = FmCsChatProvider.new(support_agent: firm[:agent], target: firm[:user], analyst: firm[:user])
    provider.tools.find { |tool| tool.is_a?(FmRunQueryTool) }
  end

  # F2: a kanban card of `firm` (on a fresh board, as the M12 steps make one) whose source is `source`
  def sfa_create_kanban_card(firm, title, source)
    board = KanbanBoard.create!(name: "#{firm.name} Board", entity: firm)
    board.update!(owner: board)
    column = board.kanban_columns.first || KanbanColumn.create!(name: "Todo", sequence: 1, entity: firm, kanban_board: board)
    # data_source_* are permitted card params: the id may name any firm's record
    KanbanCard.create!(kanban_board: board, kanban_column: column, entity: firm, title:, info_field: "",
                       data_source_type: source.class.name, data_source_id: source.id)
  end
end
World(SecurityFollowupsAHelpers)

# ---- F1 — Customer Support Agent SQL tool ---------------------------------------------------------

Given("these fund manager firms for the support SQL tool:") do |table|
  table.hashes.each do |row|
    # The fund manager firm, its fund, an investor with a PAN and the investor's KYC
    firm = FactoryBot.create(:entity, name: row["firm"], entity_type: "Investment Fund")
    FactoryBot.create(:fund, entity: firm, name: row["fund"])
    investor = cma_create_investor(firm, row["investor"])
    investor.update_columns(pan: row["pan"])
    FactoryBot.create(:investor_kyc, entity: firm, investor:, kyc_type: "individual", full_name: row["kyc name"])
    # The firm's Customer Support Agent and one of its employees chatting with it
    agent = FactoryBot.create(:support_agent, entity: firm, agent_type: "CustomerSupportAgent", name: "Customer Support Agent")
    user = FactoryBot.create(:user, entity: firm)
    user.add_role(:employee)
    sfa_firms[row["firm"]] = { entity: firm, agent:, user: }
  end
end

When("the support agent of {string} runs the query {string}") do |firm_name, sql|
  # The real FmCsChatProvider wiring; the LLM is replaced by the fixed SQL
  @run_query_response = sfa_fm_query_tool(firm_name).execute(sql:)
  puts "\n####FmRunQueryTool response####\n#{@run_query_response}\n"
end

When("the support agent of {string} runs the example query of its system prompt") do |firm_name|
  # Drift guard: the one query the CS agent's prompt documents, run exactly as written there
  firm = sfa_firms.fetch(firm_name)
  prompt = FmCsChatProvider.new(support_agent: firm[:agent], target: firm[:user], analyst: firm[:user]).system_prompt
  sql = prompt[/^\s*Example: (SELECT .+)$/, 1]
  expect(sql).to be_present
  @run_query_response = sfa_fm_query_tool(firm_name).execute(sql:)
  puts "\n####FmRunQueryTool prompt example####\n#{sql}\n#{@run_query_response}\n"
end

Then("the support query executes") do
  # Executes = neither refused by validation nor failed in the database (an empty result is fine)
  expect(@run_query_response).not_to start_with("Query rejected", "SQL execution failed", "No ")
end

# ---- F2 — Name leaks ------------------------------------------------------------------------------

Given("{string} has a deal {string}") do |firm_name, name|
  cma_create_deal(cma_firm(firm_name), name)
end

Given("{string} has a deal investor {string}") do |firm_name, investor_name|
  # A deal of the firm with one deal investor, made as the M14 steps make one
  firm = cma_firm(firm_name)
  investor = cma_create_investor(firm, investor_name)
  deal = cma_create_deal(firm, "#{investor_name} Deal")
  @sfa_deal_investors ||= {}
  @sfa_deal_investors[investor_name] = FactoryBot.create(:deal_investor, deal:, entity: firm, investor:, status: "Active")
end

Given("{string} has a kanban card {string} sourced from the deal investor {string}") do |firm_name, title, investor_name|
  sfa_create_kanban_card(cma_firm(firm_name), title, @sfa_deal_investors.fetch(investor_name))
end

When("they open the tasks list for the investor {string}") do |investor_name|
  # The list (not the board): its heading is the owner's name
  investor = Investor.find_by!(investor_name:)
  cma_request(:get, tasks_path(owner_type: "Investor", owner_id: investor.id))
end

When("they open the tasks list for the deal {string}") do |deal_name|
  deal = Deal.find_by!(name: deal_name)
  cma_request(:get, tasks_path(deal_id: deal.id))
end

When("they open the kanban card {string}") do |title|
  cma_request(:get, kanban_card_path(KanbanCard.find_by!(title:)))
end

When("they open the kanban card {string} in its side panel") do |title|
  # The off-canvas panel the board opens (turbo stream of kanban_cards/_offcanvas_show)
  cma_request(:get, kanban_card_path(KanbanCard.find_by!(title:), turbo: true))
end

# ---- F4 — Portfolio report agent's firm ---------------------------------------------------------

Given("the AI portfolio report on {string} was written by an analyst now at {string}") do |company_name, firm_name|
  # The analyst's user now belongs to another firm (moved, or a support user switched back)
  @sfa_other_firm = FactoryBot.create(:entity, name: firm_name, entity_type: "Investment Fund")
  analyst = FactoryBot.create(:user, entity: @sfa_other_firm)
  company = Investor.find_by!(investor_name: company_name)
  @sfa_report = FactoryBot.create(:ai_portfolio_report, portfolio_company: company, analyst:)
end

When("a text section of that report is generated") do
  # The agent call is replaced; the agent it is given is what the scenario checks
  allow(PortfolioReportAgent).to receive(:call) do |**kwargs|
    @sfa_agent_id = kwargs[:support_agent_id]
    double("result", success?: true)
  end
  section = @sfa_report.ai_report_sections.find_by!(section_type: "Company Overview")
  GenerateSectionContentJob.new.send(:generate_text_section, @sfa_report, section, "cached documents")
end

Then("the section was generated by the portfolio report agent of {string}") do |firm_name|
  agent = SupportAgent.find(@sfa_agent_id)
  expect(agent.agent_type).to eq("PortfolioReportAgent")
  expect(agent.entity.name).to eq(firm_name)
end

Then("{string} has no portfolio report agent") do |firm_name|
  expect(SupportAgent.where(agent_type: "PortfolioReportAgent", entity: Entity.find_by!(name: firm_name))).to be_empty
end
