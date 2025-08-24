

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
    visit(kpi_reports_path(grid_view: true, entity_id: @user.entity_id))
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
    page.should have_content(kpi_report.as_of.strftime("%b %Y"))
  end
end

When('Im given access to the KPI Reports') do
  KpiReport.all.each do |kpi_report|
    investor = kpi_report.entity.investors.where(investor_name: @investor_user.entity.name).first
    kpi_report.access_rights.create!(access_to_investor_id: investor.id, entity_id: kpi_report.entity_id, owner: kpi_report, access_type: "KpiReport", notify: false)
  end
end


When('I parse the period string {string} with fiscal start month {int}') do |date, fiscal_year_start_month|
  @parsed_date = KpiDateUtils.parse_period(date, fiscal_year_start_month:)
end

Given('a KpiReport {string} exists for the entity') do |args|
  @kpi_report = KpiReport.new(entity: @entity, portfolio_company_id: @portfolio_company.id, user: @user)
  key_values(@kpi_report, args)
  @kpi_report.save!
end

Given('a KPI {string} exists for the kpi report') do |args|
  @kpi = Kpi.new(kpi_report: @kpi_report, entity: @entity, portfolio_company_id: @portfolio_company.id)
  key_values(@kpi, args)
  @kpi.investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: @kpi.name, entity: @entity, investor: @portfolio_company)
  @kpi.save!
end



Given('an Investor KPI Mapping for {string} with RAG rules:') do |kpi_name, rag_rules_json|
  investor_kpi_mapping = InvestorKpiMapping.find_or_initialize_by(standard_kpi_name: kpi_name, entity: @entity, investor: @portfolio_company, reported_kpi_name: kpi_name)
  investor_kpi_mapping.rag_rules = JSON.parse(rag_rules_json)
  investor_kpi_mapping.save!
end

When('I compute the RAG status for KPI {string} with tagged KPI tag {string}') do |kpi_name, tagged_kpi_tag|
  kpi = Kpi.find_by(name: kpi_name)
  # Re-assign investor_kpi_mapping to ensure it has the latest rag_rules
  kpi.investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: kpi.name, entity: @entity, investor: @portfolio_company)
  kpi.set_rag_status_from_ratio(tagged_kpi_tag)
end

Then('the KPI {string} should have RAG status {string}') do |kpi_name, expected_rag_status|
  kpi = Kpi.find_by(name: kpi_name)
  kpi.rag_status.should == expected_rag_status
end

Given('KPI is enabled for the user') do
  @user ||= User.first
  @user.permissions.set(:enable_kpis)
  @user.save!
  @user.entity.permissions.set(:enable_kpis)
  @user.entity.save!
end

Given('I upload an investor kpis mappings file for the company') do
  visit(new_import_upload_path("import_upload[entity_id]": @entity.id, "import_upload[import_type]": "InvestorKpiMapping"))

  fill_in('import_upload_name', with: "Test Upload")
  # select("InvestorKpiMapping", from: "import_upload_import_type")
  @import_file = "investor_kpi_mappings_test.xlsx"
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
end

Then('There should be {string} Investor Kpi Mappings created') do |count|
  expect(InvestorKpiMapping.count).to eq(count.to_i)
end

Then('the Investor Kpi Mappings must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  kpi_maps = InvestorKpiMapping.all
  data.each_with_index do |row, idx|
      next if idx.zero? # skip header row


      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h
      kpi_map = kpi_maps[idx-1]
      puts "Checking import of #{kpi_map.standard_kpi_name}"

      kpi_map.standard_kpi_name.should == user_data["Standard Kpi Name"].strip
      kpi_map.reported_kpi_name.should == user_data["Reported Kpi Name"].strip
      kpi_map.category.should == user_data["Category"].strip
      kpi_map.data_type.should == user_data["Data Type"].strip.downcase
      kpi_map.parent_id.should == user_data["Parent Id"].strip.to_i if user_data["Parent Id"].present?
      kpi_map.position.should == user_data["Position"] if user_data["Position"].present?
      kpi_map.show_in_report.should == (user_data["Show In Report"].to_s.downcase == "yes")
      kpi_map.lower_threshold.should == user_data["Lower Threshold"] if user_data["Lower Threshold"].present?
      kpi_map.upper_threshold.should == user_data["Upper Threshold"] if user_data["Upper Threshold"].present?
  end
end
