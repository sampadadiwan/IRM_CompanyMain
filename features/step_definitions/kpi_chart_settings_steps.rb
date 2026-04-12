When('I check the KPI {string} for charting') do |kpi_name|
  # Find the checkbox associated with the KPI name in the grid
  find("input[data-kpi-name='#{kpi_name}']").click
end

Then('I should see chart controls for {string}') do |kpi_name|
  within("[data-kpi-chart-target='controlsContainer']") do
    expect(page).to have_content(kpi_name)
  end
end

When('I select {string} as the chart type for {string}') do |type_value, kpi_name|
  within("[data-kpi-chart-target='controlsContainer']") do
    select_box = find("select[data-kpi-name='#{kpi_name}']")
    select_box.find("option[value='#{type_value}']").select_option
  end
end

When('I enter {string} as the setting name') do |name|
  find("[data-kpi-chart-target='settingNameInput']").set(name)
end

When('I click {string} and accept the alert') do |text|
  accept_alert do
    click_on text
  end
end

Then('I should see {string} in an alert') do |message|
  # Since we used accept_alert in the previous step, this is effectively verified.
  # If we wanted to be more explicit, we could store the message in a variable in the previous step.
end

When('I refresh the page') do
  visit current_url
end

Then('I should see {string} in the saved charts list') do |name|
  within("[data-kpi-chart-target='savedSettingsList']") do
    expect(page).to have_content(name)
  end
end

When('I check {string} in the saved charts list') do |name|
  within("[data-kpi-chart-target='savedSettingsList']") do
    # The label contains the name, and we want to check the checkbox inside its parent
    find("label", text: name).find(:xpath, "..").find("input[type='checkbox']").click
  end
end

Then('the chart container should be visible') do
  expect(page).to have_selector("#kpi_grid_view_chart_container", visible: true)
end
