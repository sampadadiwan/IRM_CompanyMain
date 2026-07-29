Given('the KPI workbook file {string} for a kpi report') do |workbook_file| # Store the workbook file path for later use
  @workbook_file = "public/sample_uploads/#{workbook_file}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"
  # user is required on KpiReport; create! surfaces validation errors instead of leaving an
  # unsaved report around (an unsaved owner makes the document save blow up much later)
  # tag_list is a plain string column on KpiReport ("Actual"/"Budget"/"IC"), not an array
  @kpi_report = KpiReport.create!(entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, as_of: Date.today, tag_list: 'Actual', user: @user)

  @document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPI", user_id: @user.id, file: File.open(@workbook_file), owner: @kpi_report)

  @document.save!
end

Given('the KPI workbook file {string} for a {string} kpi report') do |workbook_file, tag|
  @workbook_file = "public/sample_uploads/#{workbook_file}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"
  # user is required on KpiReport; create! surfaces validation errors instead of leaving an
  # unsaved report around (an unsaved owner makes the document save blow up much later)
  # tag_list is a plain string column on KpiReport ("Actual"/"Budget"/"IC"), not an array
  @kpi_report = KpiReport.create!(entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, as_of: Date.today, tag_list: tag, user: @user)

  @document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPI", user_id: @user.id, file: File.open(@workbook_file), owner: @kpi_report)

  @document.save!
end

And('the target KPIs are {string}') do |target_kpis_string|
  # Split the comma-separated string into an array and store it
  target_kpis_string.split(',').map(&:strip).each do |kpi_name|
    # Create a new InvestorKpiMapping for each KPI name
    mapping = @portfolio_company.investor_kpi_mappings.create!(entity_id: @portfolio_company.entity_id, reported_kpi_name: kpi_name, standard_kpi_name: kpi_name)
    puts "Created mapping: #{mapping.reported_kpi_name} -> #{mapping.standard_kpi_name}"
  end
  @portfolio_company.reload
end

And('I add new target KPIs {string}') do |target_kpis_string|
  steps %(
    And the target KPIs are "#{target_kpis_string}"
  )
end

And('the following KPI mappings with denominations exist for the portfolio company:') do |table|
  table.hashes.each do |row|
    @portfolio_company.investor_kpi_mappings.create!(
      entity_id: @portfolio_company.entity_id,
      reported_kpi_name: row['reported_kpi_name'],
      standard_kpi_name: row['reported_kpi_name'],
      denomination: row['denomination'].downcase
    )
  end
  @portfolio_company.reload
end

Then('the KPI {string} should have a value of {float}') do |kpi_name, expected_value|
  kpi = Kpi.find_by(name: kpi_name, portfolio_company_id: @portfolio_company.id)
  expect(kpi).not_to be_nil, "KPI #{kpi_name} not found"
  expect(kpi.value.to_f).to eq(expected_value)
end

When('the KpiWorkbookReader processes the file') do
  # Ensure previous steps have set the necessary variables
  expect(@workbook_file).not_to be_nil, "Workbook file path not set in Given step"
  expect(@portfolio_company.investor_kpi_mappings).not_to be_nil, "Target KPIs not set in And step"
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

  # Ensure all created KPIs are unapproved
  Kpi.all.each do |kpi|
    expect(kpi.status).to eq('unapproved')
    expect(kpi.approved_at).to be_nil
  end

  @extracted_kpis.each do |_key, kpi_report|
    puts "Validating report as_of: #{kpi_report.as_of} with kpis: #{kpi_report.kpis.length}"
  end
end

Given('the string {string}') do |input|
  @input_string = input
end

When('I check if it is date-like {string}') do |locale|
  I18n.locale = locale.to_sym
  @result = KpiDateUtils.date_like?(@input_string)
  I18n.locale = I18n.default_locale
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
    expected_date = Date.local_parse(expected_date_string)
    expect(@parsed_date).to eq(expected_date), "Expected date #{expected_date} for input, but got #{@parsed_date.inspect}"
  end
end

# Handle the case where the expected date is nil/empty
Then('the resulting date should be') do
  expect(@parsed_date).to be_nil, "Expected nil date for input, but got #{@parsed_date.inspect}"
end

Then('no KPI should be imported for future dates') do
  future_kpis = Kpi.joins(:kpi_report).where('kpi_reports.as_of > ?', Date.current)
  expect(future_kpis.count).to eq(0), "Expected no future KPIs, but found #{future_kpis.count}"
end

Then('KPIs should be imported for future dates') do
  future_kpis = Kpi.joins(:kpi_report).where('kpi_reports.as_of > ?', Date.current)
  expect(future_kpis.count).to be > 0, "Expected future KPIs to be imported, but found none"
end


Given('I note the kpi values for the target KPIs') do
  puts "KPIs created - IDs and values: #{Kpi.where(portfolio_company_id: @portfolio_company.id).pluck(:name).tally}"
  @kpi_values = Kpi.where(portfolio_company_id: @portfolio_company.id).order(:id).pluck(:id, :value).to_h
end

Given('I update the KPI workbook file to {string}') do |string|
  # Update the workbook file path to the new file for refresh
  @workbook_file = "public/sample_uploads/#{string}"
  expect(File.exist?(@workbook_file)).to be(true), "Test file not found: #{@workbook_file}"

  # Update the existing document with the new file
  @document.file = File.open(@workbook_file)
  @document.name = "KPIs"
  @document.save!
end

Then('I go to the kpi report page') do
  @kpi_report ||= @document.owner
  @kpi_report.user = @user
  @kpi_report.save!
  @kpi_report.reload
  visit kpi_report_path(@kpi_report)
  expect(page).to have_content("Kpi Report #{@kpi_report.portfolio_company} : ", wait: 5)
end

Then('the KPI data should be updated with the new values') do
  expect(page).to have_content("KPI Report refresh enqueued", wait: 5)
  not_equal = []
  equal = []
  @kpi_values.each do |id, old_value|
    kpi = Kpi.find(id)
    if kpi.value.to_f != old_value.to_f
      not_equal << [id, old_value, kpi.value]
    else
      equal << id
    end
  end

  puts "Updated KPIs (ID, old value, new value): #{not_equal}"
  expect(not_equal).not_to be_empty, "Expected some KPI values to be updated, but none were. Checked KPI IDs: #{equal}"


  new_kpis = Kpi.where.not(id: @kpi_values.keys)
  puts "New KPIs created: #{new_kpis.pluck(:id, :name, :value)}"
  expect(new_kpis.count).to be > 0, "Expected new KPIs to be created, but found none"
  expect(new_kpis.pluck(:name).uniq).to include("EBITDA", "COD %"), "Expected new KPIs 'EBITDA' and 'COD %' to be created, but they were not found among new KPIs: #{new_kpis.pluck(:name).uniq}"

  puts "All KPIs after refresh: #{Kpi.where(portfolio_company_id: @portfolio_company.id).pluck(:name).tally}"
end

# --- Steps for KPI parser fixes (branch: feature/kpi-workbook-parser-fixes) ---

# Verifies that KpiReports with each expected tag exist for the portfolio company
Then('KPI reports should exist with tags {string}') do |tags_string|
  expected_tags = tags_string.split(',').map(&:strip).sort
  actual_tags = KpiReport.where(portfolio_company_id: @portfolio_company.id)
                         .pluck(:tag_list).compact.uniq.sort
  expect(actual_tags).to match_array(expected_tags),
    "Expected tags #{expected_tags}, got #{actual_tags}"
end

# Verifies that each tag has KpiReports for the same set of periods
Then('each tag should have KPI reports for the same periods') do
  # Exclude the seed report created in the Given step (as_of today) — only compare
  # the reports the KpiWorkbookReader created from the workbook periods
  reports = KpiReport.where(portfolio_company_id: @portfolio_company.id).where.not(id: @kpi_report&.id)
  by_tag = reports.group_by(&:tag_list)
  periods_per_tag = by_tag.transform_values { |reps| reps.map(&:as_of).sort }

  # All tags should cover the same periods
  all_period_sets = periods_per_tag.values.uniq
  expect(all_period_sets.size).to eq(1),
    "Expected all tags to cover the same periods, got: #{periods_per_tag.inspect}"
end

# Verifies that child InvestorKpiMappings were created under a parent
Then('child mappings should be created under {string} with names {string}') do |parent_name, children_string|
  expected_children = children_string.split(',').map(&:strip).sort
  parent = InvestorKpiMapping.find_by(
    standard_kpi_name: parent_name,
    investor: @portfolio_company
  )
  expect(parent).not_to be_nil, "Parent mapping '#{parent_name}' not found"

  actual_children = parent.children.pluck(:reported_kpi_name).sort
  expect(actual_children).to match_array(expected_children),
    "Expected children #{expected_children} under '#{parent_name}', got #{actual_children}"
end

# Verifies the prefixed standard_kpi_name for a child under a specific parent
Then('the standard KPI name for {string} under {string} should be {string}') do |child_name, parent_name, expected_standard|
  parent = InvestorKpiMapping.find_by(
    standard_kpi_name: parent_name,
    investor: @portfolio_company
  )
  expect(parent).not_to be_nil, "Parent mapping '#{parent_name}' not found"

  child = parent.children.find_by(reported_kpi_name: child_name)
  expect(child).not_to be_nil, "Child '#{child_name}' not found under '#{parent_name}'"
  expect(child.standard_kpi_name).to eq(expected_standard),
    "Expected standard name '#{expected_standard}', got '#{child.standard_kpi_name}'"
end

# Verifies that each auto-created child mapping has at least one Kpi value imported
Then('child KPIs should have values imported for each child mapping') do
  child_mappings = InvestorKpiMapping.where(investor: @portfolio_company)
                                     .where.not(ancestry: nil)
  expect(child_mappings.count).to be > 0, "No child mappings found"

  child_mappings.each do |cm|
    kpi_count = Kpi.where(
      investor_kpi_mapping_id: cm.id,
      portfolio_company_id: @portfolio_company.id
    ).count
    expect(kpi_count).to be > 0,
      "No KPI values imported for child '#{cm.standard_kpi_name}' (mapping #{cm.id})"
  end
end

# Verifies that KpiReports were created for specific month dates
Then('KPI reports should be created for months {string}') do |dates_string|
  expected_dates = dates_string.split(',').map { |d| Date.parse(d.strip) }
  actual_dates = KpiReport.where(portfolio_company_id: @portfolio_company.id)
                          .pluck(:as_of).uniq.sort

  expected_dates.each do |expected|
    expect(actual_dates).to include(expected),
      "Expected KPI report for #{expected}, found: #{actual_dates}"
  end
end

# Records the child mapping count for later idempotency check
And('I note the child mapping count under {string}') do |parent_name|
  parent = InvestorKpiMapping.find_by(
    standard_kpi_name: parent_name,
    investor: @portfolio_company
  )
  expect(parent).not_to be_nil, "Parent mapping '#{parent_name}' not found"
  @child_mapping_count = parent.children.count
  puts "Child mapping count under '#{parent_name}': #{@child_mapping_count}"
end

# Re-runs the KpiWorkbookReader (for idempotency tests)
When('the KpiWorkbookReader processes the file again') do
  @portfolio_company.reload
  reader = KpiWorkbookReader.new(
    @kpi_report, @document,
    @portfolio_company.investor_kpi_mappings,
    @user, @portfolio_company
  )
  @extracted_kpis = reader.extract_kpis
end

# Verifies no duplicate child mappings were created on re-upload
Then('there should be no duplicate child mappings under {string}') do |parent_name|
  parent = InvestorKpiMapping.find_by(
    standard_kpi_name: parent_name,
    investor: @portfolio_company
  )
  expect(parent).not_to be_nil, "Parent mapping '#{parent_name}' not found"

  children_names = parent.children.pluck(:standard_kpi_name)
  duplicates = children_names.tally.select { |_, count| count > 1 }
  expect(duplicates).to be_empty,
    "Duplicate child mappings found: #{duplicates}"

  expect(parent.children.count).to eq(@child_mapping_count),
    "Child count changed from #{@child_mapping_count} to #{parent.children.count} after re-upload"
end
