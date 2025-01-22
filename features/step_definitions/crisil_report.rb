Given('I generate Crisil report for the fund') do
  visit(fund_path(@fund))
  click_on("Fund Reports")
  click_on("Generate Reports")
  select("CRISILReport", from: "fund_report_name")
  @start_date = Time.zone.parse("01/01/2015")
  @end_date = Time.zone.parse("01/01/2025")
  fill_in('fund_report_start_date', with: @start_date)
  fill_in('fund_report_end_date', with: @end_date)
  click_on("Save")
end

Then('the Crisil report should be generated') do
  expect(page).to have_content("Fund report will be generated, please check back in a few mins.")
  sleep(5)
  # expect(page).to have_content("CRISIL Report generation completed.")
  crisil_report = Document.where("name like ?", "%CRISIL Report%").last
  expect(crisil_report).to be_present
  expect(crisil_report.file).to be_present
  expect(crisil_report.name.include?(@start_date.strftime('%d %B,%Y'))).to be_truthy
  expect(crisil_report.name.include?(@end_date.strftime('%d %B,%Y'))).to be_truthy
end
