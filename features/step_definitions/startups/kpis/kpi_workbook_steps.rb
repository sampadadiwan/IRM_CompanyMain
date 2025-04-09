# features/step_definitions/startups/kpis/kpi_workbook_steps.rb

require 'rspec/expectations' # Include RSpec matchers for assertions

# Using instance variables (@variable) to share state between steps within a scenario

Given('the KPI workbook file {string} exists') do |workbook_file|
  # Store the workbook file path for later use
  @workbook_file = "public/sample_uploads/#{workbook_file}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"
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
    reader = KpiWorkbookReader.new(@workbook_file, @target_kpis)
    @extracted_kpis = reader.extract_kpis
    puts @extracted_kpis
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
  
  @extracted_kpis.each do |kpi, entries|
    puts "Validating KPI: #{kpi} with entries: #{entries.length}"
    entries.length.should eq(count.to_i)
  end
  # Example structure for expected data (you'll need to define this based on your Excel files):
  # expected_data = {
  #   'revenuefromoperations' => [
  #     KpiWorkbookReader::KpiEntry.new('Sheet1', 'Revenue from operations', 'Jan-24', Date.new(2024, 1, 1), 10000),
  #     # ... other entries for this KPI
  #   ],
  #   'ebitda' => [
  #     KpiWorkbookReader::KpiEntry.new('Sheet1', 'EBITDA', 'Jan-24', Date.new(2024, 1, 1), 5000),
  #     # ... other entries for this KPI
  #   ]
  #   # ... other KPIs
  # }

  # You might load expected data from a helper method or fixture file based on @workbook_file
  # expected_data = load_expected_kpi_data(@workbook_file)

  # Perform assertions:
  # expect(@extracted_kpis.keys.sort).to eq(expected_data.keys.sort)
  #
  # expected_data.each do |kpi, expected_entries|
  #   expect(@extracted_kpis[kpi]).to match_array(expected_entries) # Use match_array for order-independent comparison
  # end

  # --- End Placeholder ---

  # For now, we'll just check that the result is a Hash (basic structure check)
  expect(@extracted_kpis).to be_a(Hash)

  # You should replace the above Hash check with detailed assertions against expected data.
  puts "Step Definition Placeholder: Add specific data validation for #{@workbook_file}"
end

# Helper method example (to be defined elsewhere, e.g., features/support/kpi_helpers.rb)
# def load_expected_kpi_data(workbook_file)
#   case File.basename(workbook_file)
#   when 'MIS Samples.xlsx'
#     # return expected data hash for MIS Samples.xlsx
#   when 'MIS Sample2.xlsx'
#     # return expected data hash for MIS Sample2.xlsx
#   when 'MIS Sample3.xlsx'
#     # return expected data hash for MIS Sample3.xlsx
#   else
#     {}
#   end
# end