# frozen_string_literal: true

# Step definitions for portfolio_assistant_data_manager.feature and
# portfolio_assistant_output_formatting.feature -- exercise
# PortfolioAssistantDataManager, PortfolioAssistant, BaseAssistant#clean_response, and
# MarkdownHelper#markdown_to_html directly (no LLM round-trip), mirroring the style of
# portfolio_assistant_steps.rb.

Given('the portfolio assistant data manager is initialized for the user') do
  # PortfolioAssistantDataManager scopes every query through Pundit.policy_scope(@user,
  # Investor), which for a plain employee only returns investors with an explicit
  # AccessRight (InvestorPolicy::Scope#resolve -> for_employee). company_admin gets the
  # simpler entity-wide "where(entity_id: user.entity_id)" branch instead, which is what
  # these scenarios need without having to wire up individual AccessRight fixtures.
  @user.add_role(:company_admin)
  @data_manager = PortfolioAssistantDataManager.new(user: @user)
end

Given('the portfolio company has a valuation of {int} cents per share') do |per_share_value_cents|
  instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company)
  @valuation = FactoryBot.create(:valuation, owner: @portfolio_company, entity: @entity,
                                             investment_instrument: instrument, valuation_date: Time.zone.today,
                                             per_share_value_cents: per_share_value_cents)
end

When('I list valuations with no portfolio_company_id') do
  @valuations = @data_manager.list_valuations(portfolio_company_id: nil)
end

Then("the valuations should include the portfolio company's valuation") do
  expect(@valuations.pluck(:id)).to include(@valuation.id)
end

Given('the portfolio company has a portfolio investment') do
  # PortfolioInvestment has derived fields (net_amount_cents, aggregate_portfolio_investment,
  # etc.) that only get computed by the PortfolioInvestmentCreate operation's steps, not by
  # a plain FactoryBot.create -- mirrors the working pattern in validation_rules.rb.
  fund = FactoryBot.create(:fund, entity: @entity, currency: 'INR')
  instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company,
                                                         currency: 'INR')
  pi = FactoryBot.build(:portfolio_investment, fund: fund, entity: @entity, portfolio_company: @portfolio_company,
                                               investment_instrument: instrument, investment_date: Time.zone.today,
                                               ex_expenses_base_amount_cents: 1_000_000, quantity: 100)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "Failed to create portfolio investment: #{pi.errors.full_messages}" if result.failure?

  @portfolio_investment = pi
end

When('I list portfolio investments with no portfolio_company_id') do
  @portfolio_investments = @data_manager.list_portfolio_investments(portfolio_company_id: nil)
end

Then("the portfolio investments should include the portfolio company's investment") do
  expect(@portfolio_investments.pluck(:id)).to include(@portfolio_investment.id)
end

Given('the portfolio company has a document named {string}') do |name|
  @document = FactoryBot.create(:document, entity: @entity, owner: @portfolio_company, user: @user, name: name)
end

When('I list documents with no portfolio_company_id') do
  @documents = @data_manager.list_documents(portfolio_company_id: nil)
end

Then('the documents should include {string}') do |name|
  expect(@documents.pluck(:name)).to include(name)
end

Given('the portfolio company has a KPI {string} with no percentage change') do |kpi_name|
  mapping = FactoryBot.create(:investor_kpi_mapping, investor: @portfolio_company, entity: @entity,
                                                     reported_kpi_name: kpi_name, standard_kpi_name: kpi_name)
  kpi_report = FactoryBot.create(:kpi_report, entity: @entity, portfolio_company: @portfolio_company,
                                              user: @user, as_of: Time.zone.today.beginning_of_month)
  @kpi = FactoryBot.create(:kpi, kpi_report: kpi_report, entity: @entity, portfolio_company: @portfolio_company,
                                 name: kpi_name, value: '100', percentage_change: nil,
                                 investor_kpi_mapping: mapping)
end

When('I list portfolio KPIs for the portfolio company') do
  @kpis = @data_manager.list_portfolio_kpis(portfolio_company_ids: [@portfolio_company.id])
end

Then('the {string} KPI\'s percentage_change should be blank') do |kpi_name|
  row = @kpis.find { |k| k[:name] == kpi_name }
  expect(row).not_to be_nil
  expect(row[:percentage_change]).to be_nil
end

# fmv_cents is NOT set directly -- PortfolioComputations#compute_buy_metrics recomputes it
# from the auto-created valuation during PortfolioInvestmentCreate, so any direct override
# would just get overwritten. The Then step below reads back the real computed fmv_cents.
Given('the portfolio company has a portfolio investment of {int} cents in {string}') do |amount_cents, currency|
  # fund.currency stays INR; USD->INR and INR->USD rates already exist from the
  # entity's :with_exchange_rates trait, so any currency here that isn't INR must be USD.
  fund = @fund ||= FactoryBot.create(:fund, entity: @entity, currency: 'INR')
  instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company,
                                                         currency: currency)
  pi = FactoryBot.build(:portfolio_investment, fund: fund, entity: @entity, portfolio_company: @portfolio_company,
                                               investment_instrument: instrument, investment_date: Time.zone.today,
                                               ex_expenses_base_amount_cents: amount_cents, quantity: 100)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "Failed to create #{currency} portfolio investment: #{pi.errors.full_messages}" if result.failure?

  (@portfolio_investments_by_currency ||= {})[currency] = pi
end

When('I get the portfolio company snapshot') do
  @snapshot = @data_manager.get_portfolio_company_snapshot(portfolio_company_id: @portfolio_company.id)
end

Then("the snapshot's current_fmv should report a per-currency breakdown across the investments") do
  expect(@snapshot[:current_fmv]).to include('+')
  @portfolio_investments_by_currency.each do |currency, pi|
    expect(@snapshot[:current_fmv]).to include(Money.new(pi.reload.fmv_cents, currency).format)
  end
end

When('I bound a query relation with no explicit limit') do
  @bounded_relation = @data_manager.send(:bounded_limit, Investor.all, nil)
end

When('I bound a query relation with an explicit limit of {int}') do |limit|
  @bounded_relation = @data_manager.send(:bounded_limit, Investor.all, limit)
end

Then('the resulting SQL should apply the default query limit of {int}') do |limit|
  expect(@bounded_relation.to_sql).to include("LIMIT #{limit}")
end

Then('the resulting SQL should apply a limit of {int}') do |limit|
  expect(@bounded_relation.to_sql).to include("LIMIT #{limit}")
end

When('I ask PortfolioAssistant for its default report queries') do
  @report_queries = PortfolioAssistant.new(user: @user).default_report_queries
end

Then('it should return more than one query') do
  expect(@report_queries.size).to be > 1
end

Given('there is a chat response with content {string}') do |content|
  @response = RubyLLM::Message.new(role: :assistant, content: content)
end

Given('there is a chat response with the following content:') do |content|
  @response = RubyLLM::Message.new(role: :assistant, content: content)
end

When('the assistant cleans the response') do
  @response = PortfolioAssistant.new(user: @user).send(:clean_response, @response)
end

Then('the response content should equal {string}') do |expected|
  expect(@response.content).to eq(expected)
end

When('I render the markdown {string} to HTML') do |markdown|
  helper = Object.new.extend(MarkdownHelper)
  @rendered_html = helper.markdown_to_html(markdown)
end

Then('the rendered HTML should include {string}') do |expected|
  expect(@rendered_html).to include(expected)
end

When('I call list_portfolio_companies with scope {string}') do |scope|
  @data_manager.list_portfolio_companies(scope: scope)
end

Then('the portfolio company {string} should still exist') do |name|
  expect(Investor.where(investor_name: name)).to be_any
end

When('I call list_documents with scope {string}') do |scope|
  @data_manager.list_documents(scope: scope)
end

Then('the document {string} should still exist') do |name|
  expect(Document.where(name: name)).to be_any
end
