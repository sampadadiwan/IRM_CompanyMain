
Given('there is an unapproved KPI {string} for the company') do |args|
  @kpi_report ||= FactoryBot.create(:kpi_report, entity: @entity, portfolio_company: @portfolio_company, user: @user, as_of: Date.today.beginning_of_month)
  @kpi = Kpi.new(kpi_report: @kpi_report, entity: @entity, portfolio_company: @portfolio_company, status: :unapproved)
  key_values(@kpi, args)
  @kpi.investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: @kpi.name, entity: @entity, investor: @portfolio_company)
  @kpi.save!
end

Given('the following unapproved KPIs exist for the company:') do |table|
  @kpi_report ||= FactoryBot.create(:kpi_report, entity: @entity, portfolio_company: @portfolio_company, user: @user, as_of: Date.today.beginning_of_month)
  table.hashes.each do |row|
    mapping = InvestorKpiMapping.find_by(standard_kpi_name: row['name'], entity: @entity, investor: @portfolio_company)
    FactoryBot.create(:kpi, kpi_report: @kpi_report, entity: @entity, portfolio_company: @portfolio_company, name: row['name'], value: row['value'].to_f, status: :unapproved, investor_kpi_mapping: mapping)
  end
end

And('I am on the KPI reports page for the portfolio company in grid view with staged data') do
  visit kpi_reports_path(portfolio_company_id: @portfolio_company.id, grid_view: true, view_unapproved: true, entity_id: @entity.id)
end

When('I approve the KPI {string}') do |kpi_name|
  kpi = Kpi.unapproved.find_by(name: kpi_name)
  within(".value_#{kpi.id}") do
    click_on "Approve"
  end
  # Handle the custom popup
  if page.has_css?("#confirmModal", wait: 5)
    within("#confirmModal") do
      click_on I18n.t("common.proceed")
    end
  end
  sleep 1
end

When('I approve all staged KPIs') do
  find(".ti-settings").click # Open Actions dropdown
  click_on "Approve All Staged"
  if page.has_css?("#confirmModal", wait: 5)
    within("#confirmModal") do
      click_on I18n.t("common.proceed")
    end
  end
  sleep 1
end

Then('I should see the KPI {string} with value {string} as approved') do |name, value|
  # Approved KPIs should not have the "Pending" badge or text-warning
  kpi = Kpi.approved.find_by(name: name)
  within(".value_#{kpi.id}") do
    expect(page).to have_content(value)
    expect(page).not_to have_content("Pending")
  end
end

Then('I should see the following KPIs as approved:') do |table|
  table.hashes.each do |row|
    step "I should see the KPI \"#{row['name']}\" with value \"#{row['value']}\" as approved"
  end
end

And('the KPI {string} should have {string} status in the database') do |name, status|
  expect(Kpi.find_by(name: name).status).to eq(status)
end

And('all KPIs for {string} should have {string} status in the database') do |company_name, status|
  pc = Investor.find_by(investor_name: company_name)
  expect(Kpi.where(portfolio_company_id: pc.id).pluck(:status).uniq).to eq([status])
end
