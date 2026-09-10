# frozen_string_literal: true

# Steps for features/ai/cp_cs_extraction_agent.feature
#
# The LLM is always stubbed — extraction scenarios exercise the pipeline
# (citation guard, dedup, review gate), never a real model call.
# Reuses the LLM stub pattern from side_letter_obligation_steps.rb.

# Three cited obligations (one-time CP / event-triggered CP / recurring CS) + one
# uncited row the citation guard must discard.
STANDARD_CP_CS_EXTRACTION = [
  { "obligation_type" => "reporting", "title" => "Board approval before closing",
    "description" => "Board resolution approving the investment must be obtained before disbursement.",
    "source_clause" => "Clause 3.1(a)", "trigger_type" => "one_time",
    "trigger_description" => "Prior to first disbursement",
    "frequency_rrule" => nil,
    "next_due_date" => (Date.today + 30).iso8601, "owner_team" => "legal",
    "legal_category" => "condition_precedent", "confidence" => 0.94 },
  { "obligation_type" => "notice", "title" => "Regulatory clearance notice",
    "description" => "Notify investor within 10 business days of obtaining regulatory clearance.",
    "source_clause" => "Clause 5.2", "trigger_type" => "deal_event",
    "trigger_description" => "On receipt of regulatory approval",
    "frequency_rrule" => nil,
    "next_due_date" => nil, "owner_team" => "legal",
    "legal_category" => "condition_precedent", "confidence" => 0.89 },
  { "obligation_type" => "reporting", "title" => "Quarterly compliance certificate",
    "description" => "Deliver compliance certificate within 30 days of each quarter end.",
    "source_clause" => "Clause 8.4(b)", "trigger_type" => "calendar_event",
    "trigger_description" => "Within 30 days of quarter-end",
    "frequency_rrule" => "FREQ=QUARTERLY;INTERVAL=1",
    "next_due_date" => (Date.today + 45).iso8601, "owner_team" => "finance",
    "legal_category" => "condition_subsequent", "confidence" => 0.91 },
  # No source_clause — must be discarded by the citation guard
  { "obligation_type" => "other", "title" => "General cooperation clause",
    "description" => "Parties agree to cooperate in good faith.", "trigger_type" => "ongoing",
    "legal_category" => "condition_subsequent", "confidence" => 0.35 }
].freeze

# LLM response with a changed title for the first obligation (delta scenario)
CHANGED_CP_EXTRACTION = STANDARD_CP_CS_EXTRACTION.map(&:dup).tap do |rows|
  rows[0] = rows[0].merge("title" => "Revised board approval before closing")
end.freeze

# ── Helpers ──────────────────────────────────────────────────────────────────

def stub_cp_cs_llm(payload)
  mock_chat = double("chat")
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
  allow(mock_chat).to receive(:ask).and_return(payload.to_json)
end

# Creates a document tagged with the given tag on a portfolio investment
def create_tagged_document(portfolio_investment, tag)
  FactoryBot.create(:document,
                    entity: portfolio_investment.entity,
                    owner: portfolio_investment,
                    name: "#{tag} Agreement",
                    tag_list: tag,
                    folder: portfolio_investment.document_folder,
                    user: @user)
end

# Creates a portfolio investment via the Trailblazer operation so all
# computed fields (aggregate, net amounts, base cost) are set correctly.
def create_portfolio_investment(entity:, fund:, portfolio_company:, instrument:)
  pi = FactoryBot.build(:portfolio_investment,
                        entity: entity,
                        fund: fund,
                        portfolio_company: portfolio_company,
                        investment_instrument: instrument,
                        investment_date: Date.today - 6.months,
                        ex_expenses_base_amount_cents: 10_000_000,
                        quantity: 100)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  expect(result.success?).to be(true), "PI creation failed: #{pi.errors.full_messages}"
  pi
end

# Finds and approves an obligation by title, ensuring an owner is set
def approve_cp_cs_obligation(title)
  obligation = SideLetterObligation.find_by!(title: title, review_status: "pending_review")
  obligation.update!(owner_team: "legal") unless obligation.owner_present?
  result = ObligationApprove.call(obligation: obligation, user: @user)
  expect(result.success?).to be(true)
  obligation.reload
end

# ── Background ───────────────────────────────────────────────────────────────

Given('there is a portfolio company {string} with a fund and investment') do |company_name|
  @fund = FactoryBot.create(:fund, entity: @entity)
  @portfolio_company = FactoryBot.create(:investor, entity: @entity,
                                                     investor_entity: @entity,
                                                     investor_name: company_name,
                                                     category: "Portfolio Company")
  @investment_instrument = FactoryBot.create(:investment_instrument,
                                             entity: @entity,
                                             portfolio_company: @portfolio_company)
  @portfolio_investment = create_portfolio_investment(
    entity: @entity, fund: @fund,
    portfolio_company: @portfolio_company, instrument: @investment_instrument
  )
end

Given('there is a CP\/CS extraction agent configured with tag {string}') do |tag|
  @entity.support_agents.set!(:cp_cs_extraction_agent)
  # The obligation policy gates on the SLO agent flag — enable it so the
  # show page and matrix are accessible for CP/CS obligations too.
  @entity.support_agents.set!(:side_letter_obligation_agent)

  @support_agent = FactoryBot.create(
    :support_agent,
    entity: @entity,
    agent_type: "CpCsExtractionAgent",
    name: "CP/CS Extraction",
    json_fields: {
      "investment_doc_tag" => tag,
      "default_reminder_days_before" => "7",
      "overdue_escalation_days" => "3",
      "notify_tag" => ""
    }
  )
end

Given('the LLM extracts standard CP\/CS obligations') do
  stub_cp_cs_llm(STANDARD_CP_CS_EXTRACTION)
end

# ── Document setup ───────────────────────────────────────────────────────────

Given('the portfolio investment has a document tagged {string}') do |tag|
  @tagged_doc = create_tagged_document(@portfolio_investment, tag)
end

Given('the portfolio company has {int} investments with documents tagged {string}') do |count, tag|
  @extra_investments = []
  count.times do
    instrument = FactoryBot.create(:investment_instrument,
                                   entity: @entity,
                                   portfolio_company: @portfolio_company)
    pi = create_portfolio_investment(
      entity: @entity, fund: @fund,
      portfolio_company: @portfolio_company, instrument: instrument
    )
    create_tagged_document(pi, tag)
    @extra_investments << pi
  end
end

Given('the portfolio company has {int} investment without a tagged document') do |count|
  count.times do
    instrument = FactoryBot.create(:investment_instrument,
                                   entity: @entity,
                                   portfolio_company: @portfolio_company)
    create_portfolio_investment(
      entity: @entity, fund: @fund,
      portfolio_company: @portfolio_company, instrument: instrument
    )
  end
end

# ── Extraction runs ──────────────────────────────────────────────────────────

When('the CP\/CS agent runs for the portfolio investment') do
  @extraction_result = CpCsExtractionAgent.call(
    support_agent_id: @support_agent.id,
    target: @portfolio_investment,
    entity_id: @entity.id
  )
  expect(@extraction_result.success?).to be(true)
end

When('the CP\/CS agent runs for the portfolio company') do
  @extraction_result = CpCsExtractionAgent.call(
    support_agent_id: @support_agent.id,
    target: @portfolio_company,
    entity_id: @entity.id
  )
  expect(@extraction_result.success?).to be(true)
end

Given('the CP\/CS agent has already run for the portfolio investment') do
  result = CpCsExtractionAgent.call(
    support_agent_id: @support_agent.id,
    target: @portfolio_investment,
    entity_id: @entity.id
  )
  expect(result.success?).to be(true)
end

When('the CP\/CS agent runs for the portfolio investment again') do
  @extraction_result = CpCsExtractionAgent.call(
    support_agent_id: @support_agent.id,
    target: @portfolio_investment,
    entity_id: @entity.id
  )
  expect(@extraction_result.success?).to be(true)
end

When('the LLM extracts a changed CP obligation') do
  stub_cp_cs_llm(CHANGED_CP_EXTRACTION)
end

# ── Obligation assertions ────────────────────────────────────────────────────

Then('{int} obligations should be pending review for the portfolio investment') do |count|
  scope = SideLetterObligation.where(sourceable: @portfolio_investment,
                                     review_status: "pending_review")
  expect(scope.count).to eq(count)
end

Then('{int} obligations should be pending review across all investments') do |count|
  pi_ids = PortfolioInvestment.where(portfolio_company: @portfolio_company).pluck(:id)
  scope = SideLetterObligation.where(sourceable_type: "PortfolioInvestment",
                                     sourceable_id: pi_ids,
                                     review_status: "pending_review")
  expect(scope.count).to eq(count)
end

Then('each obligation should be linked to the portfolio investment via sourceable') do
  obligations = SideLetterObligation.where(sourceable: @portfolio_investment)
  obligations.each do |obl|
    expect(obl.sourceable_type).to eq("PortfolioInvestment")
    expect(obl.sourceable_id).to eq(@portfolio_investment.id)
    expect(obl.side_letter_id).to be_nil
  end
end

Then('each investment should have {int} obligations linked via sourceable') do |count|
  # Only check investments that were set up with tagged documents
  pi_ids = @extra_investments.map(&:id)
  expect(pi_ids).not_to be_empty
  pi_ids.each do |pi_id|
    scope = SideLetterObligation.where(sourceable_type: "PortfolioInvestment",
                                       sourceable_id: pi_id,
                                       review_status: "pending_review")
    expect(scope.count).to eq(count)
  end
end

Then('the agent report should note discarded items for missing citation') do
  report = SupportAgentReport.where(owner: @portfolio_investment, support_agent: @support_agent).last
  discarded = report.json_fields["extraction_issues"].find { |i| i["type"] == "discarded" }
  expect(discarded).to be_present
  expect(discarded["message"]).to include("source clause citation")
end

# ── Delta / dedup assertions ─────────────────────────────────────────────────

Given('the {string} CP\/CS obligation is approved') do |title|
  @approved_obligation = approve_cp_cs_obligation(title)
end

Then('a pending delta obligation should exist for the changed clause') do
  delta = SideLetterObligation.where(
    sourceable: @portfolio_investment,
    source_clause: "Clause 3.1(a)",
    review_status: "pending_review",
    delta: true
  )
  expect(delta.count).to eq(1)
  expect(delta.first.title).to eq("Revised board approval before closing")
end

# ── Lifecycle assertions ─────────────────────────────────────────────────────

When('the CP\/CS obligation {string} is approved') do |title|
  @target_obligation = approve_cp_cs_obligation(title)
end

Then('exactly {int} task should exist for the CP\/CS obligation') do |count|
  expect(@target_obligation.reload.tasks.count).to eq(count)
end

Then('the task category should be {string}') do |category|
  expect(@target_obligation.reload.tasks.last.category).to eq(category)
end

Then('the CP\/CS obligation should be armed') do
  expect(@target_obligation.reload.armed?).to be(true)
end

When('the CP\/CS obligation is fired with a due date {int} days out') do |days|
  result = ObligationFire.call(obligation: @target_obligation, due_date: Date.today + days, user: @user)
  expect(result.success?).to be(true)
end

# ── UI assertions ────────────────────────────────────────────────────────────

When('I visit the CP\/CS obligation page for {string}') do |title|
  @target_obligation = SideLetterObligation.find_by!(title: title)
  visit side_letter_obligation_path(@target_obligation)
end

Then('I should see {string} on the obligation page') do |text|
  expect(page).to have_content(text)
end

Then('I should see the fund name on the obligation page') do
  expect(page).to have_content(@fund.name)
end
