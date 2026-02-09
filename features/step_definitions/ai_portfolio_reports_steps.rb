Given('I am logged in as an analyst') do
  @entity = FactoryBot.create(:entity)
  @user = FactoryBot.create(:user, entity: @entity)
  @investor_user = @user  # Set this for the login step
  steps %(
    Given I login as the investor user
  )
end

Given('a portfolio company {string} exists') do |name|
  @investor_entity = FactoryBot.create(:entity, entity_type: "Company")
  @portfolio_company = FactoryBot.create(:investor, 
    name: name, 
    entity: @entity,
    investor_entity: @investor_entity
  )
end


Given('I am at the AI portfolio reports page') do
  visit ai_portfolio_reports_path
end

When('I create a new AI portfolio report for {string}') do |company_name|
  click_on "New Report"
  select company_name, from: 'Portfolio company'
  click_on "Create Report"
end

Then('an AI portfolio report should be created') do
  @report = AiPortfolioReport.last
  expect(@report).to be_present
end

Given('an AI portfolio report exists for {string}') do |company_name|
  company = Investor.find_by(name: company_name)
  @report = FactoryBot.create(:ai_portfolio_report,
    portfolio_company: company,
    analyst: @user
  )
end

When('I visit the AI portfolio report details page') do
  visit ai_portfolio_report_path(@report)
end

When('I open the chart modal') do
  click_on "Insert Chart"
end

When('I enter chart prompt {string}') do |prompt|
  fill_in 'chart-prompt-input', with: prompt
end

Then('the chart should be saved to the database') do
  expect(AgentChart.count).to be >= 1
end
