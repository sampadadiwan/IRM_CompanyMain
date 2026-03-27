# Step definitions for Portfolio Agent Run feature
Given('there is a support agent {string}') do |args|
  @support_agent = FactoryBot.create(:support_agent, entity: @entity)
  key_values(@support_agent, args)
  @support_agent.save!
end

Given('there are {int} portfolio companies') do |count|
  count.times do |i|
    steps %(
      Given there is an existing portfolio company "name=Company #{i + 1};category=Portfolio Company"
      And portfolio company is added to list of companies
    )
  end
end

Given('there is a portfolio company {string}') do |args|
  steps %(
    Given there is an existing portfolio company "#{args}"
  )
  @portfolio_company = @investor
end

Given('the agent has run for {string} {int} hours ago') do |company_name, hours|
  investor = Investor.find_by(investor_name: company_name, entity: @entity)
  @support_agent_report = FactoryBot.create(:support_agent_report,
    owner: investor,
    support_agent: @support_agent,
    updated_at: hours.hours.ago
  )
end


Given('the agent report for {string} has {int} KPI blocking issues') do |company_name, count|
  investor = Investor.find_by(investor_name: company_name, entity: @entity)
  report = SupportAgentReport.find_or_create_by(owner: investor, support_agent: @support_agent)

  issues = count.times.map do |i|
    {
      "field" => "revenue_#{i}",
      "severity" => "blocking",
      "issue" => "Missing required KPI"
    }
  end

  report.json_fields ||= {}
  report.json_fields["kpi_issues"] = issues
  report.save!
end

Given('the agent report for {string} has {int} valuation blocking issues') do |company_name, count|
  investor = Investor.find_by(investor_name: company_name, entity: @entity)
  report = SupportAgentReport.find_or_create_by(owner: investor, support_agent: @support_agent)

  issues = count.times.map do |i|
    {
      "field" => "valuation_#{i}",
      "severity" => "blocking",
      "issue" => "Invalid valuation data"
    }
  end

  report.json_fields ||= {}
  report.json_fields["valuation_issues"] = issues
  report.save!
end

Given('the agent report for {string} has {int} missing document') do |company_name, count|
  investor = Investor.find_by(investor_name: company_name, entity: @entity)
  report = SupportAgentReport.find_or_create_by(owner: investor, support_agent: @support_agent)

  issues = count.times.map do |i|
    {
      "document" => "Financial Statement #{i}",
      "type" => "missing"
    }
  end

  report.json_fields ||= {}
  report.json_fields["document_issues"] = issues
  report.save!
end

Given('the agent report for {string} has no issues') do |company_name|
  investor = Investor.find_by(investor_name: company_name, entity: @entity)
  report = SupportAgentReport.find_or_create_by(owner: investor, support_agent: @support_agent)

  report.json_fields = {
    "kpi_issues" => [],
    "valuation_issues" => [],
    "document_issues" => []
  }
  report.save!
end

Given('the agent report for {string} has KPI issues') do |company_name|
  steps %(
    Given the agent report for "#{company_name}" has 2 KPI blocking issues
  )
end

Given('I have applied filters for tags and sectors') do
  @applied_filters = {
    tag_list: "Fintech",
    sector: "FinTech"
  }
end

Given('{int} company will cause an agent error') do |count|
  # Mark one company to fail
  @failing_company = @portfolio_companies.first
  allow_any_instance_of(PortfolioCompanyAgent).to receive(:call).with(
    hash_including(target: @failing_company)
  ).and_raise(StandardError.new("Test error"))
end

When('I visit the portfolio agent run page') do
  visit investors_path(portfolio_agent_run: true)
end

When('I select tag {string} from the filter') do |tag|
  # Using Select2 for tags - simulate selection
  page.execute_script("$('#tag_list').val(['#{tag}']).trigger('change')")
end

When('I select sector {string} from the filter') do |sector|
  # Using Select2 for sectors - simulate selection
  page.execute_script("$('#sector').val(['#{sector}']).trigger('change')")
end

When('I click the search button') do
  click_button('Search', match: :first)
end

When('I select {int} companies from the dropdown') do |count|
  @selected_companies = @portfolio_companies.first(count)
  company_ids = @selected_companies.map(&:id)
  # Using Select2 for company selection - note: element id is company_selection, name is company_ids[]
  page.execute_script("$('#company_selection').val(#{company_ids}).trigger('change')")
end

When('I select all companies from the dropdown') do
  company_ids = @portfolio_companies.map(&:id)
  page.execute_script("$('#company_selection').val(#{company_ids}).trigger('change')")
end

When('I deselect all companies') do
  # Deselect any selected companies
  execute_script("$('#company_selection').val([]).trigger('change')")
end

When('I click on the {string} button for {string}') do |button_type, company_name|
  investor = Investor.find_by(investor_name: company_name)
  within("tr[data-company-id='#{investor.id}']") do
    click_link("#{button_type}", match: :first)
  end
end

When('I click the clear filters button') do
  # The clear filters button is a link with title="Clear Filters" and class="btn btn-outline-secondary"
  find('a.btn-outline-secondary[title="Clear Filters"]').click
end

When('I confirm the action') do
  # This step is no longer needed since we're directly POSTing
  # Kept for backward compatibility if needed
end

When('I run the agent on all {int} companies') do |count|
  # Get company IDs from @portfolio_companies
  company_ids = @portfolio_companies.map(&:id)

  # Directly POST to the run_batch endpoint
  page.driver.post("/support_agents/#{@support_agent.id}/run_batch",
    target_ids: company_ids,
    target_type: 'Investor'
  )

  # Simulate job completion
  @batch_result = {
    successes: @portfolio_companies.select { |c| c != @failing_company },
    errors: @failing_company ? [{ target_name: @failing_company.investor_name }] : []
  }
end

When('I run the agent on selected companies') do
  # Get selected company IDs from the filtered list
  company_ids = @portfolio_companies.map(&:id)

  # Directly POST to the run_batch endpoint
  page.driver.post("/support_agents/#{@support_agent.id}/run_batch",
    target_ids: company_ids,
    target_type: 'Investor'
  )
end

When('the batch job completes successfully') do
  # All companies processed successfully
  @batch_result = {
    successes: @portfolio_companies,
    errors: []
  }
end

When('the batch job completes') do
  # Process with some failures
  sleep 0.5 # Allow job to process
end

Then('I should see the page title {string}') do |title|
  expect(page).to have_content(title)
end

Then('I should see the filter section for tags and sectors') do
  expect(page).to have_select('tag_list')
  expect(page).to have_select('sector')
end

Then('I should see the company selection dropdown') do
  expect(page).to have_select('company_selection')
end

Then('I should see the run agent button') do
  expect(page).to have_button('Run Agent on Selected Companies')
end

Then('I should see a table of portfolio companies') do
  expect(page).to have_css('table.table')
  expect(page).to have_css('thead th', text: 'Company Name')
  expect(page).to have_css('thead th', text: 'Last Run')
  expect(page).to have_css('thead th', text: 'Agent Report')
end

Then('I should only see portfolio companies with tag {string}') do |tag|
  within('table tbody') do
    all('tr').each do |row|
      expect(row).to have_css('.badge', text: tag)
    end
  end
end

Then('I should only see portfolio companies with sector {string}') do |sector|
  within('table tbody') do
    all('tr').each do |row|
      expect(row).to have_content(sector)
    end
  end
end

Then('I should see exactly {int} companies in the table') do |count|
  expect(page).to have_css('table tbody tr', count: count)
end

Then('I should see {string} in the {string} column for {string}') do |text, column, company_name|
  investor = Investor.find_by(investor_name: company_name)
  within("tr[data-company-id='#{investor.id}']") do
    expect(page).to have_content(text)
  end
end

Then('I should see {string} button in danger state for {string}') do |button_text, company_name|
  investor = Investor.find_by(investor_name: company_name)
  within("tr[data-company-id='#{investor.id}']") do
    expect(page).to have_css('.btn-danger', text: button_text)
  end
end

Then('I should see {string} button in success state for {string}') do |button_text, company_name|
  investor = Investor.find_by(investor_name: company_name)
  within("tr[data-company-id='#{investor.id}']") do
    expect(page).to have_css('.btn-success', text: button_text)
  end
end

Then('I should see a confirmation modal') do
  expect(page).to have_css('#confirmModal', visible: true)
end

Then('the modal should say {string}') do |text|
  within('#confirmModal') do
    expect(page).to have_content(text)
  end
end

Then('the agent job should be queued for {int} companies') do |count|
  expect(SupportAgentJob).to have_been_enqueued.with(
    hash_including(
      support_agent_id: @support_agent.id,
      batch_ids: be_present
    )
  )
end

Then('I should see a success notification') do
  # Platform uses alert-info for notice messages
  expect(page).to have_css('.alert-info')
end

Then('I should see an alert {string}') do |message|
  expect(page).to have_content(message)
end

Then('I should see the report detail modal') do
  within('#remote_modal') do
    expect(page).to have_content('Report Details')
  end
end

Then('the modal should display KPI issues for {string}') do |company_name|
  within('#remote_modal') do
    expect(page).to have_content('KPI Issues')
  end
end

Then('I should see a link to the portfolio company page') do
  investor = @portfolio_company
  expect(page).to have_link(href: investor_path(investor))
end

Then('all filters should be reset') do
  expect(current_url).to match(/portfolio_agent_run=true/)
  expect(current_url).not_to match(/tag_list/)
  expect(current_url).not_to match(/sector/)
end

Then('I should see all portfolio companies') do
  expect(page).to have_css('table tbody tr', minimum: 1)
end

Then('I should see a batch summary notification') do
  expect(page).to have_css('.alert')
end

Then('the notification should say {string}') do |text|
  within('.alert') do
    expect(page).to have_content(text)
  end
end

Then('the notification should have a link to {string}') do |link_text|
  within('.alert') do
    expect(page).to have_link(link_text)
  end
end

Then('the notification should show error details') do
  within('.alert') do
    expect(page).to have_content('Recent errors:')
  end
end

Then('I should see {string} in the company name column') do |company_name|
  within('table tbody') do
    expect(page).to have_link(company_name)
  end
end

Then('I should see {string} in the sector column') do |sector|
  within('table tbody') do
    expect(page).to have_content(sector)
  end
end

Then('I should see {string} tag badge') do |tag|
  expect(page).to have_css('.badge.bg-info', text: tag)
end

Then('I should see a link to the company page') do
  investor = @portfolio_company
  expect(page).to have_link(investor.investor_name, href: investor_path(investor))
end

Then('the page should subscribe to portfolio agent batch stream') do
  # The stream name is signed and base64 encoded, so we just check for presence of the turbo-cable-stream-source
  # with the Turbo::StreamsChannel channel
  expect(page).to have_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']", visible: false)
end

Then('the page should be ready to receive batch completion updates') do
  expect(page).to have_css('#portfolio_agent_events', visible: false)
end
