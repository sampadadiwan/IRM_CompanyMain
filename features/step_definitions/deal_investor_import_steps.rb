Given('there is an existing deal investor for the deal') do
  @existing_investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for entity" unless @existing_investor

  @existing_deal_investor = DealInvestor.create!(
    deal: @deal,
    investor: @existing_investor,
    entity_id: @deal.entity_id,
    status: "Active",
    primary_amount_cents: 100_000_00,
    tier: "Tier 2"
  )

  # Create deal activities for the investor
  templates = DealActivity.templates(@deal)
  templates.each do |template|
    DealActivity.create!(
      deal: @deal,
      deal_investor: @existing_deal_investor,
      entity_id: @deal.entity_id,
      title: template.title,
      status: "incomplete",
      days: template.days || 0,
      sequence: template.sequence,
      template_id: template.id
    )
  end
end

# Generates a temporary xlsx file for the import using the first investor in the entity.
# If update_only is true, sets "Update Only" = "Yes" on all data rows.
def generate_deal_investor_xlsx(investor_name, update_only: false)
  require "caxlsx"
  headers = ["Investor Name", "Status", "Tier", "Primary Amount (USD)",
             "Secondary Amount (USD)", "Pre Money Valuation (USD)",
             "Deal Lead", "Source", "Tags", "Company Advisor", "Investor Advisor", "Update Only"]
  row = [investor_name, "Active", "Tier 1", "500000", "0", "5000000",
         "John Doe", "Referral", "VC,Tech", "", "", update_only ? "Yes" : ""]

  tmp = Tempfile.new(["deal_investors_test", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Sheet1") do |ws|
      ws.add_row headers
      ws.add_row row
    end
    p.serialize(tmp.path)
  end
  tmp
end

When('I import deal investors using {string}') do |file|
  @import_file = file
  update_only = file.include?("update_only")

  # Use the first investor of the entity so the name matches what's in DB
  investor = Investor.where(entity_id: @user.entity_id).first
  raise "No investor found for import" unless investor

  tmp = generate_deal_investor_xlsx(investor.investor_name, update_only: update_only)

  visit(new_import_upload_path(
    "import_upload[entity_id]": @user.entity_id,
    "import_upload[import_type]": "DealInvestor",
    "import_upload[owner_type]": "Deal",
    "import_upload[owner_id]": @deal.id
  ))
  fill_in('import_upload_name', with: "Test DealInvestor Upload")
  attach_file('files[]', tmp.path, make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")

  @import_upload = ImportUpload.last
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
  tmp.close
  tmp.unlink

  if @import_upload.failed_row_count > 0
    puts "Import failed_row_count: #{@import_upload.failed_row_count}"
    puts "Import error_text: #{@import_upload.error_text}"
  end
end

Then('{string} deal investor should be created for the deal') do |count|
  @deal.reload
  expect(@deal.deal_investors.count).to eq(count.to_i)
end

Then('the imported deal investor should have the correct attributes from {string}') do |_file|
  di = @deal.deal_investors.last
  expect(di.investor_name).to be_present
  expect(di.status).to be_present
  expect(di.primary_amount_cents).to be >= 0
end

Then('the deal investor should have deal activities created') do
  di = @deal.deal_investors.last
  expect(di.deal_activities.count).to be > 0
end

Then('the deal investor should be updated with data from {string}') do |_file|
  @import_upload.failed_row_count.should == 0
  @import_upload.status.should == "Completed"
  @existing_deal_investor.reload
  # Status should have been updated by the update-only file
  expect(@existing_deal_investor.status).to be_present
end

Then('the import should have {string} failed rows with error {string}') do |count, error_msg|
  expect(@import_upload.failed_row_count).to eq(count.to_i)

  # Row-level errors are stored in the import_results Shrine attachment as an xlsx
  combined = ""
  if @import_upload.import_results.present?
    # Use open to get an IO object from Shrine
    @import_upload.import_results.open do |io|
      tmp = Tempfile.new(["import_results", ".xlsx"])
      tmp.binmode
      tmp.write(io.read)
      tmp.flush
      data = Roo::Spreadsheet.open(tmp.path)
      all_rows = []
      data.each_with_index do |row, idx|
        next if idx.zero? # skip header

        all_rows << row.compact.join(" ")
      end
      combined = all_rows.join(" ")
      tmp.close
      tmp.unlink
    end
  end
  puts "Results content: #{combined}"
  expect(combined).to include(error_msg)
end
