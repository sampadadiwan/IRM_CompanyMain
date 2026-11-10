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
  # With :inline job adapter the job runs synchronously and the completion flash
  # ("... generation completed.") replaces the async "will be generated" flash
  # before this assertion could catch it. Accept either message.
  expect(page).to have_content(
    /Fund report will be generated|generation completed/i,
    wait: 20
  )
  # expect(page).to have_content("CRISIL Report generation completed.")
  # Was sleep(5) before reading the document: retry until the generation job has stored it
  crisil_report = nil
  eventually(timeout: 20) do
    crisil_report = Document.where("name like ?", "%CRISIL Report%").last
    expect(crisil_report).to be_present
    expect(crisil_report.file).to be_present
  end
  expect(crisil_report.name.include?(@start_date.strftime('%d %B,%Y'))).to be_truthy
  expect(crisil_report.name.include?(@end_date.strftime('%d %B,%Y'))).to be_truthy
end
