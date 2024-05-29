Given('Given I upload an exchange_rates file') do
  visit(exchange_rates_path)
	click_on("Import")
  sleep(1)
  fill_in('import_upload_name', with: "Exchange Rates Bulk Import Testing")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/exchange_rates.xlsx'), make_visible: true)
  sleep(4)
  click_on("Save")
  sleep(4)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then("There should be 2 exchange rates created") do
	expect(ExchangeRate.count).to(eq(2))
end