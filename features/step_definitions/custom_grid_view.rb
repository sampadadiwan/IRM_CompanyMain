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

When('I visit Custom Grid View page and uncheck city') do
  form_type = FormType.first
  visit "/form_types/#{form_type.id}/configure_grids"
  sleep(0.25)
  within(:xpath, "//tr[contains(@class, 'column_city')]") do
    find("form.deleteButton button").click
  end
  click_on('Proceed')
  sleep(0.25)
end

Given('I should not find city column in the Investor Grid') do
  visit('/investors')
  sleep(0.25)
  expect(page).not_to have_selector('thead th', text: 'City')
end
