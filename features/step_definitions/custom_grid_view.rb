Given('I am at the form type page') do
  visit("/form_types")
  sleep(0.5)
end

When('I create a form type and custom grid view') do
  click_link('New Form Type')
  find('select[name="form_type[name]"]').select('Investor')
  click_on('Save')
  sleep(0.5)
  click_on('Configure Grids')
  sleep(1)
  expect(CustomGridView.count).to(eq(1))
  expect(GridViewPreference.count).to(eq(6))
end

Given('I visit Investor Page and find 6 columns in the grid') do
  visit('/investors')
  @expected_columns = %w[City Stakeholder PAN Tags Category Access]
  @expected_columns.each do |column_name|
    expect(page).to have_text(column_name)
  end
end

When('I visit Custom Grid View page and uncheck city') do
  @custom_grid_view = CustomGridView.first
  visit custom_grid_view_path(@custom_grid_view)
  sleep(0.25)
  click_on('Edit')
  sleep(0.25)
  checkbox = find('tr.column_City input[type="checkbox"]')
  checkbox.uncheck
  click_on('Save Changes')
end

Given('I should not find city column in the Investor Grid') do
  visit('/investors')
  sleep(0.25)
  expect(page).not_to have_selector('thead th', text: 'City')
end
