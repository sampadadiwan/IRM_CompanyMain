Given('I ransack filter the {string}') do |filter_for|
  visit("/reports")

  within all("form").first do
    select "Commitments", from: "url"
  end
end

Given('I save the filtered data as a report {string}') do |string|
  find('a[data-bs-original-title="Save Report"] i.ti.ti-database').click
  fill_in('report_name', with: string)
  fill_in('report_category', with: "#{string} category") 
  fill_in('report_tag_list', with: "#{string} tags")
  fill_in('report_description', with: "#{string} description")
  click_on('Save')
end

Then('I should be able to view the report details') do
  sleep 2
  @report ||= Report.last
  visit("/reports/#{@report.id}")
  expect(page).to have_content(@report.name)
  expect(page).to have_content(@report.category)
  expect(page).to have_content(@report.tag_list)
  expect(page).to have_content(@report.description)
end

Given('I delete the report') do
  @report ||= Report.last
  visit("/reports/#{@report.id}")
  click_on('Delete')
  click_on('Proceed')
end

Then('The report should be deleted') do
  expect(page).to have_content("Report was successfully destroyed")
end
