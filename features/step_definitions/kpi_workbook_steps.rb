
Given('the KPI workbook file {string} for a kpi report') do |workbook_file|  # Store the workbook file path for later use
  @workbook_file = "public/sample_uploads/#{workbook_file}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"
  @kpi_report = KpiReport.create(entity_id: @entity.id, portfolio_company_id: @portfolio_company.id,  as_of: Date.today)

  @document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPI", user_id: @user.id, file: File.open(@workbook_file), owner: @kpi_report)

  @document.save!
end

And('the target KPIs are {string}') do |target_kpis_string|
  # Split the comma-separated string into an array and store it
  target_kpis_string.split(',').map(&:strip).each do |kpi_name|
    # Create a new InvestorKpiMapping for each KPI name
    @portfolio_company.investor_kpi_mappings.create!(entity_id: @portfolio_company.entity_id, reported_kpi_name: kpi_name, standard_kpi_name: kpi_name + " Standard")
  end
  @portfolio_company.reload
end

When('the KpiWorkbookReader processes the file') do
  # Ensure previous steps have set the necessary variables
  expect(@workbook_file).not_to be_nil, "Workbook file path not set in Given step"
  expect(@portfolio_company.investor_kpi_mappings).not_to be_nil, "Target KPIs not set in And step"
  @kpi_report = KpiReport.new(entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, as_of: Date.today, tag_list: "Actual")
  puts "Step Definition Placeholder: Processing workbook file #{@workbook_file} with target KPIs: #{@target_kpis}"
  # Instantiate the reader and extract KPIs
  begin
    reader = KpiWorkbookReader.new(@kpi_report, @document, @portfolio_company.investor_kpi_mappings, @user, @portfolio_company)
    @extracted_kpis = reader.extract_kpis
    puts reader.error_msg
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
  Kpi.count.should eq(count.to_i * @portfolio_company.investor_kpi_mappings.count)
  @extracted_kpis.each do |date, kpi_report|
    puts "Validating date: #{date} with entries: #{kpi_report.kpis.length}"
    puts "Expected KPIs: #{@portfolio_company.investor_kpi_mappings.pluck(:standard_kpi_name)} got #{kpi_report.kpis.map(&:name)}"
    kpi_report.kpis.length.should eq(@portfolio_company.investor_kpi_mappings.count)
  end
end


Given('the string {string}') do |input|
  @input_string = input
end

When('I check if it is date-like') do
  @result = KpiDateUtils.date_like?(@input_string)
end

Then('the result should be {word}') do |expected|
  expected_bool = expected == "true"
  expect(@result).to eq(expected_bool)
end


When('I parse the period string {string}') do |period_string|
  @period_string = period_string
  @parsed_date = KpiDateUtils.parse_period(period_string)
end


Then('the parsed type should be {string}') do |type|
  KpiDateUtils.detect_period_type(@period_string).downcase.should == type.downcase
end

# Handle the case where the input string itself might be empty in the feature file
When('I parse the period string') do
  # Pass an empty string explicitly for the blank input case
  @parsed_date = KpiDateUtils.parse_period("")
end


Then('the resulting date should be {string}') do |expected_date_string|
  if expected_date_string.blank?
    expect(@parsed_date).to be_nil, "Expected nil date for input, but got #{@parsed_date.inspect}"
  else
    expected_date = Date.parse(expected_date_string)
    expect(@parsed_date).to eq(expected_date), "Expected date #{expected_date} for input, but got #{@parsed_date.inspect}"
  end
end

# Handle the case where the expected date is nil/empty
Then('the resulting date should be') do
  expect(@parsed_date).to be_nil, "Expected nil date for input, but got #{@parsed_date.inspect}"
end