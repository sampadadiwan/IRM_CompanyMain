Given('Given I upload an exchange_rates file {string}') do |file_name|
  visit(exchange_rates_path)
  click_on("Import")
  #sleep(1)
  fill_in('import_upload_name', with: "Exchange Rates Bulk Import Testing")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then("There should be 2 exchange rates created") do
  visit(import_upload_path(ImportUpload.last))
  #sleep(1)
  row_count = find_by_id('exchange_rates').all("tr").count
  # One for headers
  expect(row_count).to(eq(3))
  expect(ExchangeRate.where(as_of: Date.parse("14/05/2024")).count).to(eq(2))
end
