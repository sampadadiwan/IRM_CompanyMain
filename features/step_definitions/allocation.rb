Given('I upload an allocation file {string}') do |file_name|
  interest = Interest.create!(secondary_sale_id: SecondarySale.last.id, user_id: User.last.id, investor_id: Investor.last.id, quantity: 1230, price: 1000)
  @import_allocation_file_name = file_name
  visit('/offers')
  first(:link, 'Show').click
  #sleep(0.2)
  click_on('Allocations')
  #sleep(2)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep(4)
  click_on("Save")
  #sleep(4)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep(5)
  ImportUpload.last.failed_row_count.should == 0
end

Then('I should find allocations created with correct data') do
  file_path = "./public/sample_uploads/#{@import_allocation_file_name}"
  sheet = Roo::Spreadsheet.open(file_path).sheet(0)

  headers = sheet.row(1)
  offer_id_index = headers.index("Offer Id")
  interest_id_index = headers.index("Interest Id")
  secondary_sale_id_index = headers.index("Secondary Sale Id")
  allocation_quantity_index = headers.index("Allocation Quantity")
  allocation_price_index = headers.index("Allocation Price")
  allocation_amount_index = headers.index("Allocation Amount")
  verified_index = headers.index("Verified")

  allocation = Allocation.first

  first_row = sheet.row(2)
  expect(allocation.offer_id).to eq(first_row[offer_id_index].to_i)
  expect(allocation.interest_id).to eq(first_row[interest_id_index].to_i)
  expect(allocation.quantity.to_d).to eq(first_row[allocation_quantity_index].to_d)
  expect(allocation.price.to_d).to eq(first_row[allocation_price_index].to_d)
  expect(allocation.amount).to(be_present)
  expect(allocation.verified).to eq(first_row[verified_index].downcase == 'yes')
  expect(Allocation.last.verified).to eq(sheet.row(3)[verified_index].downcase == 'yes')
end
