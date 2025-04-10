# features/step_definitions/startups/kpis/kpi_workbook_steps.rb

require 'rspec/expectations' # Include RSpec matchers for assertions

# Using instance variables (@variable) to share state between steps within a scenario

Given('the KPI workbook file {string} for a kpi report') do |workbook_file|  # Store the workbook file path for later use
  @workbook_file = "public/sample_uploads/#{workbook_file}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"
  @kpi_report = KpiReport.create(entity_id: @entity.id, portfolio_company_id: @portfolio_company.id,  as_of: Date.today)

  @document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPI", user_id: @user.id, file: File.open(@workbook_file), owner: @kpi_report)
  @document.save!
end

And('the target KPIs are {string}') do |target_kpis_string|
  # Split the comma-separated string into an array and store it
  @target_kpis = target_kpis_string.split(',').map(&:strip)
end

When('the KpiWorkbookReader processes the file') do
  # Ensure previous steps have set the necessary variables
  expect(@workbook_file).not_to be_nil, "Workbook file path not set in Given step"
  expect(@target_kpis).not_to be_nil, "Target KPIs not set in And step"
  puts "Step Definition Placeholder: Processing workbook file #{@workbook_file} with target KPIs: #{@target_kpis}"
  # Instantiate the reader and extract KPIs
  begin
    reader = KpiWorkbookReader.new(@document, @target_kpis, @user, @portfolio_company)
    @extracted_kpis = reader.extract_kpis
  rescue StandardError => e
    # Store any exception raised during processing to check in the Then step if needed
    @processing_error = e
  end
end

Then('the extracted KPI data should be valid for the given workbook and targets with {string}') do |count|
  # Check if an error occurred during processing
  expect(@processing_error).to be_nil, "Error processing workbook: #{@processing_error&.message}"

  # Ensure the extracted data is not nil (even if empty)
  expect(@extracted_kpis).not_to be_nil

  # --- Placeholder for Data Validation ---
  # This is where you'll compare @extracted_kpis with the expected data
  # for the specific @workbook_file.
  @extracted_kpis.keys.length.should eq(count.to_i)
  @extracted_kpis.each do |date, kpi_report|
    puts "Validating date: #{date} with entries: #{kpi_report.kpis.length}"
    kpi_report.kpis.length.should eq(@target_kpis.length)
  end
end
