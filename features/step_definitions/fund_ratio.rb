Given("an Bulk Upload is performed for FundRatios") do
  visit(fund_path(@fund))
  click_on("Ratios")
  click_on("Upload")
  sleep(10)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/fund_ratios.xlsx"), make_visible: true)
  sleep(10)
  click_on("Save")
  sleep(2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should == 0
end

Given("there is a CapitalCommitment with {string}") do |arg|
  capital_commitment = CapitalCommitment.last
  key_values(capital_commitment, arg)
  capital_commitment.save!
end


And("I should find Fund Ratios created with correct data for Fund") do
  visit(fund_path(@fund))
  click_on("Ratios")
  sleep(2)
  expect(page).to have_content("R1")
  expect(page).to have_content("0.06")
end

And("I should find Fund Ratios created with correct data for API") do
  fund_ratio = FundRatio.find_by(owner: AggregatePortfolioInvestment.last)
  expect(fund_ratio.name).to(eq("R2"))
  expect(fund_ratio.value).to(eq("0.28383838e0".to_d))
  expect(fund_ratio.display_value).to(eq("0.3"))
  expect(fund_ratio.end_date).to(eq(Date.parse("21/04/2025")))
end

And("I should find Fund Ratios created with correct data for Investor") do
  fund_ratio = FundRatio.find_by(owner_type: "Investor")
  expect(fund_ratio.name).to(eq("R3"))
  expect(fund_ratio.value).to(eq("0.18383838e0".to_d))
  expect(fund_ratio.display_value).to(eq("0.2"))
  expect(fund_ratio.end_date).to(eq(Date.parse("21/05/2025")))
end

And("I should find Fund Ratios created with correct data for Capital Commitment") do
  visit(capital_commitment_path(CapitalCommitment.last))
  click_on("Ratios")
  expect(page).to have_content("R4")
  expect(page).to have_content("0.1")
  expect(page).to have_content("21/06/2025")
end