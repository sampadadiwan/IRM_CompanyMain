Given('I am at the form type page') do
  visit("/form_types")
  sleep(0.5)
end

When('I create a form type and custom grid view for {string}') do |form_type|
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select(form_type)
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')
  sleep(1)
end

When("I select each option and click Add") do

  select_box = find('select#grid_view_name_select')
  options = select_box.all('option').map(&:text)

  options.each do |option_text|
    select option_text, from: 'grid_view_name_select'
    sleep 0.25

    select_box = find('select#grid_view_name_select')
  end
end

Given('I visit Investor Page and find 6 columns in the grid') do
  visit('/investors')
  @expected_columns = %w[City Stakeholder PAN Tags Category Access]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit PortfolioInvestment Page and find 6 columns in the grid') do
  visit('/portfolio_investments')
  @expected_columns = ["For", "Company Name", "Investment Date", "Amount", "Quantity", "Cost Per Share", "FMV", "FIFO Cost", "Investment Type", "Notes"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

Given('I visit AggregatePortfolioInvestment Page and find 6 columns in the grid') do
  visit('/aggregate_portfolio_investments')
  @expected_columns = ["For", "Portfolio Company", "Fund Name", "Instrument", "Net Bought Amount", "Sold Amount", "Current Quantity", "Fmv", "Avg Cost / Share"]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I visit Custom Grid View page and uncheck {string}') do |column_name|
  form_type = FormType.first
  visit "/form_types/#{form_type.id}/configure_grids"
  sleep(0.25)
  within(:xpath, "//tr[contains(@class, 'column_#{column_name.downcase}')]") do
    find("form.deleteButton button").click
  end
  
  click_on('Proceed')
  sleep(0.25)
end


Given('I should not find {string} column in the Investor Grid') do |column_name|
  visit('/investors')
  sleep(0.25)
  
  column_title = column_name.capitalize
  
  expect(page).not_to have_selector('thead th', text: column_title)
end

