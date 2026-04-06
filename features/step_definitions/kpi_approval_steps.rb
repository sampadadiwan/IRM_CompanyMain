Given('there is an unapproved KPI {string} for the company') do |args|
  @kpi_report ||= FactoryBot.create(:kpi_report, entity: @entity, portfolio_company: @portfolio_company, user: @user, as_of: Date.today.beginning_of_month)
  @kpi = Kpi.new(kpi_report: @kpi_report, entity: @entity, portfolio_company: @portfolio_company, status: :unapproved)
  key_values(@kpi, args)
  @kpi.investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: @kpi.name, entity: @entity, investor: @portfolio_company)
  @kpi.save!
end

Given('the following unapproved KPIs exist for the company:') do |table|
  table.hashes.each do |row|
    as_of = Date.today.beginning_of_month
    if row['period_relative'].present?
      as_of = case row['period_relative']
              when 'last year'
                Date.today.beginning_of_year - 1.day
              when 'this month'
                Date.today.beginning_of_month
              when 'this quarter'
                # Ensure it's in the current quarter but NOT in the current month to avoid double counting in "this month" stat
                if Date.today.month % 3 == 0 # Last month of quarter (e.g. March, June, Sept, Dec)
                  Date.today.beginning_of_month - 1.month
                else
                  Date.today.beginning_of_month + 1.month
                end
              when 'this year'
                # For the sake of the test expectations, we want this to be in the current quarter but not current month
                if Date.today.month % 3 == 0 # Last month of quarter
                  Date.today.beginning_of_month - 2.months
                else
                  Date.today.beginning_of_month + 1.month
                end
              else
                Date.today.beginning_of_month
              end
    end

    kpi_report = KpiReport.find_or_create_by!(
      entity: @entity,
      portfolio_company_id: @portfolio_company.id,
      as_of: as_of,
      period: 'Month'
    ) do |r|
      r.user = @user
    end

    mapping = InvestorKpiMapping.find_by(standard_kpi_name: row['name'], entity: @entity, investor: @portfolio_company)
    FactoryBot.create(:kpi, kpi_report: kpi_report, entity: @entity, portfolio_company: @portfolio_company, name: row['name'], value: row['value'].to_f, status: :unapproved, investor_kpi_mapping: mapping)
  end
end

Then('I should see the following unapproved KPI stats:') do |table|
  table.hashes.each do |row|
    # Find the card with the subtitle and check the count
    within(".card", text: row['subtitle']) do
      expect(page).to have_css('[data-counters-target="output"]', text: row['count'])
    end
  end
end

And('the {string} card should link to the unapproved KPIs') do |subtitle|
  within(".card", text: subtitle) do
    link = find(:xpath, "..") # The link is the parent of the card
    # Instead of checking for exact encoded string, let's just check for the components
    # Use CGI.unescape to check the content
    decoded_url = CGI.unescape(link[:href])
    expect(decoded_url).to include('"name":"status"')
    expect(decoded_url).to include('"value":"unapproved"')
    expect(decoded_url).to include('kpis')
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

When('I reject the KPI {string}') do |kpi_name|
  kpi = Kpi.unapproved.find_by(name: kpi_name)
  within(".value_#{kpi.id}") do
    click_on "Reject"
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

Then('I should not see the KPI {string} with value {string}') do |_name, value|
  expect(page).not_to have_content(value)
end

And('the KPI {string} should not exist in the database') do |name|
  expect(Kpi.find_by(name: name)).to be_nil
end

And('all KPIs for {string} should have {string} status in the database') do |company_name, status|
  pc = Investor.find_by(investor_name: company_name)
  expect(Kpi.where(portfolio_company_id: pc.id).pluck(:status).uniq).to eq([status])
end
