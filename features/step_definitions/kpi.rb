
  Given('Given I upload a kpis file for the company') do
    visit(kpi_reports_path)
    click_on("Upload")
    sleep(2)
    fill_in('import_upload_name', with: "Test Upload")
    @import_file = "kpis.xlsx"
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
    sleep(2)
    click_on("Save")
    sleep(2)
    ImportUploadJob.perform_now(ImportUpload.last.id)
    sleep(4)
  end

  Given('Given I upload a kpis file for the portfolio company') do
    visit(investor_path(@portfolio_company))
    page.execute_script("document.body.style.zoom = '80%'")
    click_on("Kpis")
    sleep(2)
    click_on("Actions")
    click_on("Upload")
    sleep(2)
    fill_in('import_upload_name', with: "Test Upload")
    @import_file = "kpis.xlsx"
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
    sleep(5)
    click_on("Save")
    sleep(7)
    ImportUploadJob.perform_now(ImportUpload.last.id)
    sleep(4)
  end

  Then('There should be {string} Kpi Report with {string} Kpis created') do |kpi_report_count, kpi_count|
    KpiReport.count.should == kpi_report_count.to_i
    Kpi.count.should == kpi_count.to_i
  end

  Then('the KPIs must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    kpis = Kpi.all
    data.each_with_index do |row, idx|
        next if idx.zero? # skip header row


        # create hash from headers and cells
        user_data = [headers, row].transpose.to_h
        kpi = kpis[idx-1]
        puts "Checking import of #{kpi.name}"
        kpi.name.should == user_data["Name"].strip
        kpi.kpi_report.period.should == user_data["Period"].strip
        kpi.value.should == user_data["Value"].to_f
        kpi.kpi_report.as_of.should == user_data["As Of"]
    end
  end


  Then('when I setup the KPI mappings for the portfolio company') do
    visit(investor_path(@portfolio_company))
    click_on("Kpi Mapping")
    page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
    sleep(2)
    click_on("Generate From Last Report")
    sleep(2)
  end

  Then('when I view the KPI report for the portfolio company in grid view') do
    visit(kpi_reports_path(entity_id: @portfolio_company.investor_entity_id, grid_view: true))
  end


  Then('when I view the KPI report for the portfolio company in grid view as owner') do
    visit(kpi_reports_path(portfolio_company_id: @portfolio_company.id, grid_view: true, entity_id: @user.entity_id))
  end

  Then('when I view the KPI report in grid view') do
    visit(kpi_reports_path(grid_view: true))
  end

  Then('I should see the KPI Report with all Kpis') do
    Kpi.all.each do |kpi|
        within(".value_#{kpi.id}") do
            page.should have_content(number_with_delimiter(kpi.value.round(2), delimiter: ','))
        end
    end
  end



When('I go to the KPIs of the company {string}') do |name|
  kpi_entity = Entity.where(name: name).first
  visit(kpi_reports_path(entity_id: kpi_entity.id, grid_view: true))
end

Then('I should not see the KPI Reports') do
  KpiReport.all.each do |kpi_report|
    page.should_not have_content(kpi_report.as_of.strftime("%d/%m/%Y"))
  end
end

Then('I should see the KPI Report') do
  KpiReport.all.each do |kpi_report|
    page.should have_content(kpi_report.as_of.strftime("%d/%m/%Y"))
  end
end

When('Im given access to the KPI Reports') do
  KpiReport.all.each do |kpi_report|
    investor = kpi_report.entity.investors.where(investor_name: @investor_user.entity.name).first
    kpi_report.access_rights.create!(access_to_investor_id: investor.id, entity_id: kpi_report.entity_id, owner: kpi_report, access_type: "KpiReport", notify: false)
  end
end


# Use a simple object or mock for the reader instance in the background step,
# as we only need to test the 'parse_period' method directly.
# We don't need a real document, user, or portfolio company for this specific test.
Given('a KpiWorkbookReader is initialized') do
  # We don't need a full instance, just access to the method.
  # Store the default fiscal start month if needed.
  @fiscal_start_month = 4 # Default from the method signature
end

Given('a KpiWorkbookReader is initialized with fiscal start month {int}') do |start_month|
  @fiscal_start_month = start_month
end

When('I parse the period string {string}') do |period_string|
  # Instantiate a dummy reader just to call the instance method.
  # Pass nil for dependencies not needed by parse_period.
  # Using Struct to avoid needing real objects for dependencies.
  dummy_doc = Struct.new(:name, :id).new('dummy_doc', 1)
  dummy_user = Struct.new(:name).new('dummy_user')
  dummy_pc = Struct.new(:name, :id, :entity_id).new('dummy_pc', 1, 1)

  reader = KpiWorkbookReader.new(dummy_doc, [], dummy_user, dummy_pc)
  @parsed_date = reader.send(:parse_period, period_string, fiscal_year_start_month: @fiscal_start_month)
end

# Handle the case where the input string itself might be empty in the feature file
When('I parse the period string') do
  dummy_doc = Struct.new(:name, :id).new('dummy_doc', 1)
  dummy_user = Struct.new(:name).new('dummy_user')
  dummy_pc = Struct.new(:name, :id, :entity_id).new('dummy_pc', 1, 1)

  reader = KpiWorkbookReader.new(dummy_doc, [], dummy_user, dummy_pc)
  # Pass an empty string explicitly for the blank input case
  @parsed_date = reader.send(:parse_period, "", fiscal_year_start_month: @fiscal_start_month)
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