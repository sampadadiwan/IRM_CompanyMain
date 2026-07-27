# frozen_string_literal: true

CASH_TAG     = "CASH"
EXPENSE_TAG  = "EXPENSE"
BUFFER_TAG   = "BUFFER"

# ─── Support Agent Setup ────────────────────────────────────────────────────

Given('a cash flow support agent is configured for the entity') do
  @cash_max_days    = 30
  @proforma_max_days = 90

  @support_agent = SupportAgent.create!(
    entity:     @user.entity,
    name:       "Cash Flow Agent",
    agent_type: "CashFlowAssistantAgent",
    enabled:    true,
    llm_model:  "gemini-3-flash-preview",
    json_fields: {
      "cash_tags"         => CASH_TAG,
      "expense_tags"      => EXPENSE_TAG,
      "buffer_tags"       => BUFFER_TAG,
      "report_recipients" => "",
      "funds" => [
        {
          "fund_id" => @fund.id,
          "name"    => @fund.name,
          "staleness_thresholds" => {
            "cash_accounts_max_days" => @cash_max_days,
            "proforma_max_days"      => @proforma_max_days
          }
        }
      ]
    }
  )
end

# ─── Data Setup ─────────────────────────────────────────────────────────────

Given('the fund has cash account entries that are {int} days old') do |days|
  AccountEntry.create!(
    fund:               @fund,
    entity:             @fund.entity,
    name:               "Cash Balance",
    entry_type:         CASH_TAG,
    reporting_date:     days.days.ago.to_date,
    amount_cents:       100_000_000,
    capital_commitment: nil
  )
end

Given('the fund has no cash account entries') do
  # intentionally empty — no entries means no data
end

Given('the fund has a proforma investment that is {int} days old') do |days|

  investor_entity = FactoryBot.create(:entity, name: "Test Portfolio Co")

    investor = Investor.new(
    entity:        @fund.entity,
    investor_entity: investor_entity,
    investor_name: "Test Portfolio Co"
  )
    investor.save(validate: false) 


  agg = AggregatePortfolioInvestment.new(
    fund:   @fund,
    entity: @fund.entity,
    portfolio_company: investor,
    portfolio_company_name:   "Test Aggregate"
  )
  agg.save(validate: false)

  allow_any_instance_of(PortfolioInvestment).to receive(:update_name)
  pi = PortfolioInvestment.new(
    fund:         @fund,
    entity:       @fund.entity,
    aggregate_portfolio_investment: agg,
    portfolio_company:  investor,
    proforma:     true,
    amount_cents: 50_000_000,
    excused_folio_ids:              [],          # ← was missing (null: false in schema)
    created_at:   days.days.ago
  )
  pi.save(validate: false)
end


Given('the staleness threshold for cash is {int} days') do |days|
  funds_config = @support_agent.json_fields["funds"]
  funds_config.first["staleness_thresholds"]["cash_accounts_max_days"] = days
  @support_agent.update!(
    json_fields: @support_agent.json_fields.merge("funds" => funds_config)
  )
end

# ─── Execution ──────────────────────────────────────────────────────────────

When('I run the staleness checker') do
  checker      = CashFlowStalenessChecker.new(@support_agent)
  @fund_results = checker.check_all_funds
  @fund_result  = @fund_results.first
end

# ─── Assertions ─────────────────────────────────────────────────────────────

Then('the fund result status should be {string}') do |status|
  expect(@fund_result[:status]).to eq(status)
end

Then('there should be no block reasons') do
  expect(@fund_result[:block_reasons]).to be_empty
end

Then('the block reasons should mention {string}') do |text|
  all_reasons = @fund_result[:block_reasons].join(" ")
  expect(all_reasons).to include(text)
end


# ─── Expense Estimator Setup ────────────────────────────────────────────────

Given('the fund has no expense account entries') do
  # intentionally empty
end

Given('the fund has expense account entries for {int} month(s)') do |months|
  months.times do |i|
    AccountEntry.create!(
      fund:               @fund,
      entity:             @fund.entity,
      name:               "Expense Month #{i + 1}",
      entry_type:         EXPENSE_TAG,
      reporting_date:     (months - i).months.ago.to_date.beginning_of_month,
      amount_cents:       500_000_00,
      capital_commitment: nil
    )
  end
end

Given('the fund has growing expense account entries for {int} months') do |months|
  months.times do |i|
    AccountEntry.create!(
      fund:               @fund,
      entity:             @fund.entity,
      name:               "Expense Month #{i + 1}",
      entry_type:         EXPENSE_TAG,
      reporting_date:     (months - i).months.ago.to_date.beginning_of_month,
      amount_cents:       (300_000_00 + (i * 50_000_00)),
      capital_commitment: nil
    )
  end
end

# ─── Expense Estimator Execution ────────────────────────────────────────────

When('I run the expense estimator for {int} days') do |days|
  entities       = [@fund.entity] + @fund.entity.children.to_a
  @expense_result = ExpenseEstimator.new(@fund, entities, [EXPENSE_TAG]).estimate(forecast_days: days)
end

# ─── Expense Estimator Assertions ───────────────────────────────────────────

Then('the estimation method should be {string}') do |method|
  expect(@expense_result[:method]).to eq(method)
end

Then('the estimated total should be 0') do
  expect(@expense_result[:total]).to eq(0)
end

Then('the estimated total should be greater than 0') do
  expect(@expense_result[:total]).to be > 0
end

Then('each monthly prediction should be greater than the previous') do
  predictions = @expense_result[:monthly_predictions]
  predictions.each_cons(2) do |prev, curr|
    expect(curr).to be > prev
  end
end

# ─── Cash Flow Agent Setup ───────────────────────────────────────────────────

Given('the fund has fresh cash account entries worth {int} cents') do |amount|
  # SQLite does not auto-increment id in composite primary key tables,
  # so we generate it manually for the test environment.
  AccountEntry.create!(
    id:                 AccountEntry.maximum(:id).to_i + 1,
    fund:               @fund,
    entity:             @fund.entity,
    name:               "Cash Balance",
    entry_type:         CASH_TAG,
    reporting_date:     1.day.ago.to_date,
    amount_cents:       amount,
    capital_commitment: nil
  )
end

Given('the fund has a proforma investment worth {int} cents') do |amount|
  investor_entity = FactoryBot.create(:entity, name: "Test Portfolio Co")

  investor = Investor.new(
    entity:          @fund.entity,
    investor_entity: investor_entity,
    investor_name:   "Test Portfolio Co"
  )
  investor.save(validate: false)

  agg = AggregatePortfolioInvestment.new(
    fund:                   @fund,
    entity:                 @fund.entity,
    portfolio_company:      investor,
    portfolio_company_name: "Test Portfolio Co"
  )
  agg.save(validate: false)

  allow_any_instance_of(PortfolioInvestment).to receive(:update_name)
  pi = PortfolioInvestment.new(
    fund:                           @fund,
    entity:                         @fund.entity,
    aggregate_portfolio_investment: agg,
    portfolio_company:              investor,
    proforma:                       true,
    amount_cents:                   amount,
    excused_folio_ids:              [],
    investment_date:                30.days.from_now.to_date
  )
  pi.save(validate: false)
end

Given('no report recipients are configured') do
  @support_agent.json_fields["report_recipients"] = ""
  @support_agent.save!
end

Given('report recipients are configured as {string}') do |emails|
  @support_agent.json_fields["report_recipients"] = emails
  @support_agent.save!
end

# ─── Cash Flow Agent Execution ───────────────────────────────────────────────

When('I run the cash flow agent') do
  # Stub Turbo broadcasts — not needed in functional tests
  allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

  # Stub report renderer — tested separately, avoid file/S3 ops
  allow_any_instance_of(CashFlowReportRenderer).to receive(:save_to_fund_folder)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(nil)



  CashFlowAssistantAgent.call(
    support_agent_id: @support_agent.id,
    target:           @fund.entity,
    user_id:          @user.id
  )
end

# ─── Cash Flow Agent Assertions ──────────────────────────────────────────────

Then('a fund report should be saved with status {string}') do |status|
  @fund_report = SupportAgentReport.find_by(owner: @fund, support_agent: @support_agent)
  expect(@fund_report).to be_present
  expect(@fund_report.status).to eq(status.downcase)
end

Then('the fund report should show cash flow status {string}') do |status|
  data = @fund_report.json_fields
  actual = data["fund_status"] || data["status"]
  expect(actual).to eq(status)
end

Then('the net position should be positive') do
  expect(@fund_report.json_fields["net_position"].to_i).to be > 0
end

Then('the recommended call amount should be greater than 0') do
  expect(@fund_report.json_fields["recommended_call"].to_i).to be > 0
end

Then('no report email should be queued') do
  expect(ActionMailer::Base.deliveries).to be_empty
end

Then('a report email should be queued') do
  expect(ActionMailer::Base.deliveries).not_to be_empty
end
