Given('I am at the form type page') do
  visit("/form_types")
  #sleep(0.5)
end

Given('I am at the reports page') do
  visit("/reports")
  #sleep(0.5)
end

When('I create a report and custom grid view for {string}') do |report|
  select("Portfolio Investments", from: 'url')
  #sleep(0.5)
  find('a[aria-label="Save Report"]').click
  #sleep(0.5)
  fill_in('report_name', with: "PI Report")
  fill_in('report_category', with: "Portfolio Investments")
  click_on('Save')
  #sleep(0.5)
  visit("/reports")
  #sleep(0.5)
  find('.more-options.text-dark').click
  click_link("Configure Grid")
  #sleep(0.5)
end

When('I create a form type and custom grid view for {string}') do |form_type|
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select(form_type)
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')
  #sleep(1)
end

When('I create a derived field {string}') do |form_type|
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select(form_type)
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')

  click_link('Add Derived Field')
  sleep(2)
  fill_in "Enter Grid View Key", with: "instrument_name"
  fill_in "Label", with: "PI's Instrument"
  select "String", from: "Data Type"
  fill_in "Sequence", with: 1
  click_button "Save"
end

When("I select each option and click Add") do
  select_box = find('select#grid_view_name_select')
  options = select_box.all('option').map(&:text)

  options.each do |option_text|
    select option_text, from: 'grid_view_name_select'
    sleep(0.25)

    select_box = find('select#grid_view_name_select')
  end
end

Given('I visit Investor Page and find 6 columns in the grid') do
  visit('/investors')
  @expected_columns = %w[Stakeholder Tags Category Access]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit PortfolioInvestment Page and find 6 columns in the grid') do
  visit('/portfolio_investments')
  @expected_columns = ["Portfolio Company", "Investment Date", "Amount", "Quantity", "Cost Per Share", "FMV", "FIFO Cost", "Notes"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit PortfolioInvestment Page from reports') do
  visit(Report.first.url)
  @expected_columns = ["Portfolio Company", "Investment Date", "Amount", "Quantity", "Cost Per Share", "FMV", "FIFO Cost", "Notes"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit AggregatePortfolioInvestment Page and find 6 columns in the grid') do
  visit('/aggregate_portfolio_investments')
  @expected_columns = ["Portfolio Company", "Instrument", "Net Bought Amount", "Sold Amount", "Current Quantity", "Fmv", "Avg Cost / Share"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit CapitalCommitment Page and find 6 columns in the grid') do
  visit('/capital_commitments')
  @expected_columns = ["Type", "Folio", "Stakeholder", "Investing", "Entity", "Unit", "Type", "Committed", "Called", "Collected", "Distributed"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit InvestorKyc Page and find 6 columns in the grid') do
  visit('/investor_kycs')
  @expected_columns = ["Stakeholder", "Investing", "Entity", "Type", "Kyc", "Verified", "Expired"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit FundUnitSetting Page and find columns in the grid') do
  visit('/fund_unit_settings')
  @expected_columns = ["Class/Series", "Management Fee %", "Setup Fee %", "Carry", "ISIN"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I visit Custom Grid View page and uncheck {string}') do |column_name|
  form_type = FormType.first
  visit '/grid_view_preferences/configure_grids?owner_id=1&owner_type=FormType'
  #sleep(0.25)
  within(:xpath, "//tr[contains(@class, 'column_#{column_name.downcase}')]") do
    find("form.deleteButton button").click
  end
  
  click_on('Proceed')
  #sleep(0.25)
end

When('I visit Report Custom Grid View page and uncheck {string}') do |column_name|
  report = Report.first
  visit '/grid_view_preferences/configure_grids?owner_id=1&owner_type=Report'
  #sleep(0.25)
  within(:xpath, "//tr[contains(@class, 'column_#{column_name.downcase}')]") do
    find("form.deleteButton button").click
  end
  
  click_on('Proceed')
  #sleep(0.25)
end


Given('I should not find {string} column in the Investor Grid') do |column_name|
  visit('/investors')
  #sleep(0.25)
  
  column_title = column_name.capitalize
  
  expect(page).not_to have_selector('thead th', text: column_title)
end

Given('I should not find {string} column in the Portfolio Investment Grid') do |column_name|
  visit('/investors')
  #sleep(0.25)
  
  column_title = column_name.capitalize
  
  expect(page).not_to have_selector('thead th', text: column_title)
end

Given('I should not find {string} column in the Report PI Grid') do |column_name|
  visit(Report.first.url)
  #sleep(0.25)
  column_title = column_name.capitalize
  
  expect(page).not_to have_selector('thead th', text: column_title)
end

When("I visit Portfolio Investment AG Grid and find the derived field") do
  visit portfolio_investments_path(filter: true)
  check('ag_grid')
  find('button.search-button[aria-label="Search"]').click
  expect(page).to have_content("PI's Instrument")
end


When('I visit {string} Page and find columns in the grid') do |class_name|
  page_url = "/#{class_name.underscore.pluralize}"
  visit(page_url)
  # @expected_columns = class_name::STANDARD_COLUMNS.keys.compact
  @expected_columns = 
  case class_name.to_s
  when 'CapitalRemittance'
    ["Stakeholder", "Folio No", "Status", "Verified", "Due Amount", "Collected Amount", "Payment Date"]
  when 'CapitalCall'
    ["Name", "Due Date", "Call Amount", "Collected Amount", "Due Amount", "Approved"]
  when 'FundReport'
    ["Id", "Name", "Name Of Scheme", "Start Date", "End Date"]
  when "FundRatio"
    ["For", "Type", "Name", "Display Value", "On", "Scenario"]
  when "KpiReport"
    ["As Of", "Period", "Notes", "User", "For"]
  when "Offer"
     ["Investor", "User", "Quantity", "Price", "Allocation Quantity", "Allocation Amount", "Approved", "Verified", "Updated At"]
  end

  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I should not find {string} column in the {string} Grid') do |column, class_name|
  visit("/#{class_name.underscore.pluralize}")
  #sleep(0.25)
  column_title = column.titleize
  
  expect(page).not_to have_selector('thead th', text: column_title)
end
