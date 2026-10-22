Given('Given I upload a kpis file for the company') do
  visit(kpi_reports_path)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  @import_file = "kpis.xlsx"
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
end

Given('Given I upload a kpis file for the portfolio company') do
  @portfolio_company ||= Investor.portfolio_companies.last
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpis-tab"))
  page.execute_script("document.body.style.zoom = '80%'")
  sleep(2)
  click_on("Actions")
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  @import_file = "kpis.xlsx"
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 5)
  uploads_before = ImportUpload.count
  click_on("Save")
  # Wait for Save to create the ImportUpload row (was sleep 7)
  eventually { expect(ImportUpload.count).to be > uploads_before }
  @iu = ImportUpload.last
  # perform_now runs the job synchronously, so the result is ready on return (a sleep(4) followed it)
  ImportUploadJob.perform_now(@iu.id)
  expect(@iu.reload.failed_row_count == 0).to be true
end

# Parameterized variant of "Given I upload a kpi mappings file for the company" above, for
# regression scenarios that need a specific mappings sheet (e.g. a real customer file that
# reproduced a bug) rather than the shared investor_kpi_mappings_test_1.xlsx fixture. `file` is
# relative to public/sample_uploads/, same as every other file-path step in this codebase.
Given('Given I upload a kpi mappings file {string} for the portfolio company') do |file|
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpi-mappings-tab"))
  page.execute_script("document.body.style.zoom = '80%'")
  sleep(2)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Mapping Upload")
  @import_file = file
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
  click_on("Save")
  sleep(2)
  @iu = ImportUpload.last
  ImportUploadJob.perform_now(@iu.id)
  sleep(4)
  expect(@iu.reload.failed_row_count == 0).to be true
end

# Imports a full KPI workbook (multi-sheet, dates-as-columns — the format KpiWorkbookReader reads,
# distinct from the single-row-per-datapoint "kpis.xlsx" format the legacy ImportKpi service above
# reads) against the portfolio company. Attaches the file as the report's "KPIs" document and runs
# the real ImportKpiWorkbookJob directly, the same way kpi_upload_validation_steps.rb's "the workbook
# is imported for the KPI report" does — scripting the wizard's Uppy file picker for a real multi-sheet
# workbook (vs. the small in-memory fixtures those wizard scenarios generate) is exactly the kind of
# interaction this codebase's own comments already call out as unreliable to automate (see
# kpi_wizard_helpers.rb). The shell report's own as_of/period is otherwise a no-op here: the reader
# scans every period it finds in the sheets regardless (confirmed against this real file - it created
# 21 KpiReports spanning 10 quarters from Q1 FY24 to Q2 FY26, only one of which is this shell), it just
# also flags the requested one as not found if it doesn't happen to match, which is harmless.
Given('I import the KPI workbook {string} for the portfolio company') do |file|
  @kpi_report = KpiReport.new(entity: @entity, portfolio_company: @portfolio_company, user: @user,
                              as_of: Date.today.beginning_of_quarter, period: "Quarter", tag_list: "Actual",
                              enable_portco_upload: true)
  @kpi_report.save!(validate: false)
  document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPIs", user_id: @user.id,
                                          file: File.open(File.absolute_path("./public/sample_uploads/#{file}")), owner: @kpi_report)
  document.save!
  ImportKpiWorkbookJob.perform_now(@kpi_report.id, @user.id)
end

Then('there should be {string} Kpis for the portfolio company') do |count|
  expect(Kpi.where(portfolio_company: @portfolio_company).count).to eq(count.to_i)
end

When('I go to the Kpis tab on the investor show page for the portfolio company') do
  # Cleared here (rather than at scenario start) so setup emails - e.g. from creating the
  # investor/entity - don't get swept into the "no error email" check below.
  ActionMailer::Base.deliveries.clear
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpis-tab"))
  page.execute_script("document.body.style.zoom = '80%'")
  sleep(2)
end

# Mirrors the real dropdown-menu interaction the "Actions" button drives (see the .ti-settings
# dropdown in kpi_reports/_grid_view.html.erb) -
# opens the menu and clicks a plain link inside it, e.g. "View Including Staged". Distinct from
# "I approve all staged KPIs" (kpi_approval_steps.rb), which opens the same menu for a button_to that
# needs the confirm-modal handled, not a plain link.
When('I click Actions then {string} on the Kpis page') do |link_text|
  click_on("Actions")
  click_on(link_text)
  sleep(1)
end

Then('all pending KPIs for the portfolio company should be approved without error') do
  # Approve all now runs in KpiApproveAllJob (inline in test, so the count below is already 0)
  expect(page).to have_content("pending KPIs in the background")
  expect(Kpi.where(portfolio_company: @portfolio_company).unapproved.count).to eq(0)
  # Approve All runs KpiApproveService (in KpiApproveAllJob, inline in test), which cumulates and recomputes percentage
  # change for every affected report inline - the same call chain that raised "Out of sort memory"
  # in production. A failure there doesn't necessarily fail the request (KpiCumulateJob rescues and
  # emails on error rather than raising - see "a KPI cumulation error email should be sent" above),
  # so the success flash alone isn't proof nothing went wrong; checking no error email was sent closes
  # that gap.
  # Checked across every delivery rather than just emails_sent_to(@user.email): KpiCumulateJob mails
  # the user who triggered the approval, but a failure deeper in the chain can notify someone else,
  # and a missed recipient would make this assertion pass for the wrong reason.
  error_mail = ActionMailer::Base.deliveries.find { |m| m.subject.match?(/error/i) }
  expect(error_mail).to be_nil, "Expected no error email, but got: #{error_mail&.subject}"
end

# And Given I upload a kpi mappings file for the company
And('Given I upload a kpi mappings file for the company') do
  @portfolio_company ||= Investor.portfolio_companies.last
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpi-mappings-tab"))
  page.execute_script("document.body.style.zoom = '80%'")
  sleep(2)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Mapping Upload")
  @import_file = "investor_kpi_mappings_test_1.xlsx"
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
  click_on("Save")
  sleep(2)
  @iu = ImportUpload.last
  ImportUploadJob.perform_now(@iu.id)
  sleep(4)
  expect(@iu.reload.failed_row_count == 0).to be true
end

Then('There should be {string} Kpi Report with {string} Kpis created') do |kpi_report_count, kpi_count|
  KpiReport.count.should == kpi_report_count.to_i
  Kpi.count.should == kpi_count.to_i
  Kpi.unapproved.count.should == kpi_count.to_i
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
    kpi = kpis[idx - 1]
    puts "Checking import of #{kpi.name}"
    kpi.name.should
    user_data["Name"].strip
    kpi.kpi_report.period.should
    user_data["Period"].strip
    kpi.value.should
    user_data["Value"].to_f
    kpi.kpi_report.as_of.should == user_data["As Of"]
  end
end

Then('when I setup the KPI mappings for the portfolio company') do
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpi-mappings-tab"))
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  sleep(2)
  click_on("Generate From Last Report")
  sleep(2)
end

Then('when I view the KPI report for the portfolio company in grid view') do
  visit(kpi_reports_path(entity_id: @portfolio_company.investor_entity_id, grid_view: true, view_unapproved: true))
end

Then('when I view the KPI report for the portfolio company in grid view as owner') do
  visit(kpi_reports_path(portfolio_company_id: @portfolio_company.id, grid_view: true, entity_id: @user.entity_id, view_unapproved: true))
end

Then('when I view the KPI report in grid view') do
  visit(kpi_reports_path(grid_view: true, entity_id: @user.entity_id, view_unapproved: true))
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
  # Try to find if there is an investor record for this entity in the current user's entity
  investor = Investor.find_by(investor_entity_id: kpi_entity.id, entity_id: @user.entity_id)
  if investor
    visit(kpi_reports_path(portfolio_company_id: investor.id, grid_view: true))
  else
    visit(kpi_reports_path(entity_id: kpi_entity.id, grid_view: true))
  end
end

Then('I should not see the KPI Reports') do
  KpiReport.all.each do |kpi_report|
    page.should_not have_content(I18n.l(kpi_report.as_of))
  end
end

Then('I should see the KPI Report') do
  KpiReport.all.each do |kpi_report|
    page.should have_content(I18n.l(kpi_report.as_of, format: :month_year))
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
  mapping = InvestorKpiMapping.find_or_create_by(standard_kpi_name: @kpi.name, entity: @entity, investor: @portfolio_company, reported_kpi_name: @kpi.name)
  @kpi.investor_kpi_mapping = mapping
  @kpi.save!
end

# comparator_tag: pass "none" for a flat threshold (no comparator KPI needed) — RAG status then
# computes automatically the moment the KPI's own value is saved, via Kpi#recompute_rag_status!.
Given('an Investor KPI Mapping for {string} exists with RAG comparator {string}, direction {string}, red threshold {float}, green threshold {float}') do |kpi_name, comparator_tag, direction, red, green|
  investor_kpi_mapping = InvestorKpiMapping.find_or_initialize_by(standard_kpi_name: kpi_name, entity: @entity, investor: @portfolio_company, reported_kpi_name: kpi_name)
  investor_kpi_mapping.rag_comparator_tag = comparator_tag == 'none' ? nil : comparator_tag
  investor_kpi_mapping.rag_direction = direction
  investor_kpi_mapping.rag_red_threshold = red
  investor_kpi_mapping.rag_green_threshold = green
  investor_kpi_mapping.save!
end

# Approves the same-as_of KPI carrying this tag (e.g. "Budget" or the default "Actual" — see
# kpi_reports.tag_list's DB default in db/schema.rb, there's no untagged/nil state to special-case
# here), via KpiApprover — the same service the "Approve" button in the grid calls — so the
# RAG-on-approval callback path (not just the RAG-on-value-save path) gets exercised.
When('the KPI {string} tagged {string} is approved') do |kpi_name, tag|
  kpi = Kpi.joins(:kpi_report).where(name: kpi_name, portfolio_company_id: @portfolio_company.id, 'kpi_reports.tag_list': tag).first
  KpiApprover.call(kpi.id, @user.id)
end

# Same idea as above, but disambiguated by as_of instead of tag — for the PriorPeriod comparator,
# where both the subject and its comparator typically share the same (blank) tag_list.
When('the KPI {string} as of {string} is approved') do |kpi_name, as_of|
  kpi = Kpi.joins(:kpi_report).where(name: kpi_name, portfolio_company_id: @portfolio_company.id, 'kpi_reports.as_of': Date.parse(as_of)).first
  KpiApprover.call(kpi.id, @user.id)
end

# Mirrors "... is approved" above, but reverting via Kpi#unapprove! (the model method backing the
# "Unapprove" button on the KPI show page) instead of KpiApprover — exercises the cascade that
# clears this KPI's own rag_status and re-evaluates dependents that may have been judging
# themselves against it as a comparator.
When('the KPI {string} tagged {string} is unapproved') do |kpi_name, tag|
  kpi = Kpi.joins(:kpi_report).where(name: kpi_name, portfolio_company_id: @portfolio_company.id, 'kpi_reports.tag_list': tag).first
  kpi.unapprove!
end

Then('the KPI {string} should have RAG status {string}') do |kpi_name, expected_rag_status|
  kpi_under_test(kpi_name).rag_status.should == expected_rag_status
end

Then('the KPI {string} should have no RAG status') do |kpi_name|
  kpi_under_test(kpi_name).rag_status.should be_nil
end

# A comparator KPI often shares its name with the actual KPI it judges, so Kpi.find_by(name:) is
# ambiguous. Two different shapes of ambiguity show up here:
#  - same-as_of comparators (Budget/PriorYear/etc.): the actual is whichever same-named KPI's
#    report is NOT tagged with the mapping's rag_comparator_tag — excluded below.
#  - the PriorPeriod comparator: both rows share the same (blank) tag_list, so that exclusion is
#    a no-op, but they have different as_of dates — the "subject" of the assertion is always the
#    latest one, regardless of which was inserted first (a scenario may create the prior period
#    before or after the one it's judging, to exercise both the live and cascaded-recompute paths).
def kpi_under_test(kpi_name)
  mapping = InvestorKpiMapping.find_by(standard_kpi_name: kpi_name, entity: @entity, investor: @portfolio_company)
  scope = Kpi.joins(:kpi_report).where(name: kpi_name, portfolio_company_id: @portfolio_company.id)
  scope = scope.where.not('kpi_reports.tag_list': mapping.rag_comparator_tag) if mapping&.rag_comparator_tag.present?
  scope.order('kpi_reports.as_of DESC, kpis.id DESC').first.reload
end

When('I attempt to save an Investor KPI Mapping for {string} with RAG comparator {string}, direction {string}, red threshold {float}, green threshold {float}') do |kpi_name, comparator_tag, direction, red, green|
  @attempted_mapping = InvestorKpiMapping.find_or_initialize_by(standard_kpi_name: kpi_name, entity: @entity, investor: @portfolio_company, reported_kpi_name: kpi_name)
  @attempted_mapping.rag_comparator_tag = comparator_tag == 'none' ? nil : comparator_tag
  @attempted_mapping.rag_direction = direction
  @attempted_mapping.rag_red_threshold = red
  @attempted_mapping.rag_green_threshold = green
  @attempted_mapping.save
end

Then('the mapping save should fail with an error about RAG thresholds') do
  @attempted_mapping.errors.any?.should == true
  @attempted_mapping.persisted?.should == false
end

When('I visit the Investor KPI Mapping show page for {string}') do |kpi_name|
  mapping = InvestorKpiMapping.find_by(standard_kpi_name: kpi_name, entity: @entity, investor: @portfolio_company)
  visit investor_kpi_mapping_path(mapping)
end

Given('KPI is enabled for the user') do
  @user ||= User.first
  @user.permissions.set(:enable_kpis)
  @user.save!
  @user.entity.permissions.set(:enable_kpis)
  @user.entity.save!
end

Given('I upload an investor kpis mappings file for the company') do
  visit(new_import_upload_path('import_upload[entity_id]': @entity.id, 'import_upload[import_type]': "InvestorKpiMapping"))

  fill_in('import_upload_name', with: "Test Upload")
  # select("InvestorKpiMapping", from: "import_upload_import_type")
  @import_file = "investor_kpi_mappings_test.xlsx"
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
end

Given('I upload an investor kpis mappings file {string} for the company') do |file|
  visit(new_import_upload_path('import_upload[entity_id]': @entity.id, 'import_upload[import_type]': "InvestorKpiMapping"))

  fill_in('import_upload_name', with: "Test Upload")
  @import_file = file
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{@import_file}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
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

  InvestorKpiMapping.all
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    kpi_map = InvestorKpiMapping.find_by(standard_kpi_name: user_data["Standard Kpi Name"].strip, reported_kpi_name: user_data["Reported Kpi Name"].strip, entity: @entity)
    puts "Checking import of #{kpi_map.standard_kpi_name} (ID: #{kpi_map.id})"

    kpi_map.standard_kpi_name.should
    user_data["Standard Kpi Name"].strip
    kpi_map.reported_kpi_name.should
    user_data["Reported Kpi Name"].strip
    kpi_map.category.should
    user_data["Category"].strip
    kpi_map.data_type.should
    user_data["Data Type"].strip.downcase
    kpi_map.parent_id.should == user_data["Parent Id"].strip.to_i if user_data["Parent Id"].present?
    kpi_map.position.should == user_data["Position"] if user_data["Position"].present?
    kpi_map.show_in_report.should
    user_data["Show In Report"].to_s.downcase
    kpi_map.lower_threshold.should == user_data["Lower Threshold"] if user_data["Lower Threshold"].present?
    kpi_map.upper_threshold.should == user_data["Upper Threshold"] if user_data["Upper Threshold"].present?
  end
end

Given('the following KPI mappings exist for the portfolio company:') do |table|
  table.hashes.each do |row|
    FactoryBot.create(:investor_kpi_mapping,
                      investor: @portfolio_company,
                      entity: @portfolio_company.entity,
                      reported_kpi_name: row['reported_kpi_name'],
                      standard_kpi_name: row['reported_kpi_name'])
  end
end

Given('I am on the KPI upload page for the portfolio company') do
  # Kpis is a dropdown tab on the stakeholder page; ?tab= opens the screen directly
  visit(investor_path(@portfolio_company, tab: "kpis-tab"))
  sleep(1)

  click_on("Actions")
  click_on("New")
  sleep(1)
end

When('I upload the kpi workbook {string} for validation') do |workbook_file|
  @import_file = workbook_file
  advance_kpi_wizard_to(:upload) # the file input lives on the wizard's "Upload & Validate KPIs" step
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
end

# The workbook check is server-side (KpiReportsController#validate_upload → KpiWorkbookReader#validate);
# the verdict is rendered into #kpi_validation_panel by turbo_stream after the upload completes.
Then('I should see a validation report with the message {string}') do |message|
  within('#kpi_validation_panel') do
    expect(page).to have_content(message, wait: 15)
  end
end

And('the report should list {string} found KPIs') do |count|
  within('#kpi_validation_panel') do
    expect(page).to have_content("#{count} of ", wait: 15)
    expect(page).to have_content("expected KPIs found")
  end
end

And('the report should list {string} missing KPIs') do |count|
  # "Missing" KPIs render as red badges (bg-danger-subtle) inside the "expected KPIs found" tile —
  # there is no separate "Missing: ..." line to match on anymore.
  within('#kpi_validation_panel') do
    expect(page).to have_css('.badge.bg-danger-subtle', count: count.to_i, wait: 15)
  end
end

Then('I should see a validation error with the message {string}') do |error_message|
  within('#kpi_validation_panel') do
    expect(page).to have_content(error_message, wait: 15)
  end
end

# KPI cumulate test steps

Given('the following Monthly KPI Reports exist with KPIs:') do |table|
  @entity ||= Entity.last || FactoryBot.create(:entity)
  @portfolio_company ||= Investor.last || FactoryBot.create(:investor, entity: @entity)
  @user ||= User.last || FactoryBot.create(:user, entity: @entity)

  # Ensure mappings exist for these KPIs
  table.hashes.each do |row|
    mode = row['cumulate_mode'] || 'cumulate'
    mapping = InvestorKpiMapping.where(
      entity_id: @entity.id,
      investor_id: @portfolio_company.id,
      standard_kpi_name: row['name']
    ).first_or_initialize
    mapping.reported_kpi_name = row['name']
    mapping.autofill = mode
    mapping.save!
  end

  table.hashes.each do |row|
    as_of = Date.parse(row['as_of'])
    period = row['period'] || 'Month'
    tag_list = row['tag_list'] || 'Actual'
    status = row['status'] || 'approved'
    kpi_report = KpiReport.find_or_create_by!(entity: @entity, portfolio_company_id: @portfolio_company.id, period:, as_of:, tag_list:) do |r|
      r.user = @user
    end
    mapping = InvestorKpiMapping.find_by(standard_kpi_name: row['name'], entity: @entity, investor: @portfolio_company)
    FactoryBot.create(:kpi, kpi_report:, entity: @entity, portfolio_company_id: @portfolio_company.id, name: row['name'], value: row['value'].to_f, investor_kpi_mapping: mapping, status: status.to_sym)
  end
end

When('I run the KPI cumulate method for {string}') do |kpi_name|
  kpi = Kpi.joins(:investor_kpi_mapping).where(name: kpi_name).first
  kpi.autofill
end

When('I run the KpiCumulateJob for the portfolio company') do
  KpiCumulateJob.perform_now(@portfolio_company.id, user_id: @user.id)
end

# Mirrors KpiApproveService's call: cumulation runs first, then the percentage-change job runs
# inside the same perform — the ordering guarantee under test.
When('I run the KpiCumulateJob with percentage change computation') do
  KpiCumulateJob.perform_now(@portfolio_company.id, user_id: @user.id, compute_percentage_change: true)
end

Then('the {string} KPI {string} for {string} should have a percentage change') do |period, name, as_of|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: date }).last
  expect(kpi).not_to be_nil
  expect(kpi.percentage_change).to be_present
end

# The cumulative must carry the source KPI's mapping — a mapping-less cumulative would fail
# Kpi's investor_kpi_mapping_id presence validation and never be written.
Then('the {string} KPI {string} for {string} should be linked to the {string} mapping') do |period, name, as_of, mapping_name|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: date }).last
  expect(kpi).not_to be_nil
  expect(kpi.investor_kpi_mapping&.standard_kpi_name).to eq(mapping_name)
end

# Forces every Kpi#save during the job to fail, simulating a validation failure on the
# cumulative records (the source KPIs in this scenario are already persisted, so only the
# cumulatives save during the run). The job must report these, not swallow them.
Given('cumulative KPI saves will fail') do
  ActionMailer::Base.deliveries.clear
  allow_any_instance_of(Kpi).to receive(:save).and_return(false)
end

Then('a KPI cumulation error email should be sent') do
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present
  expect(mail.subject).to include("Errors in KPI cumulation")
end

Given('an Investor KPI Mapping for {string} with formula {string} and mode {string}') do |name, formula, mode|
  mapping = InvestorKpiMapping.where(
    entity_id: @entity.id,
    investor_id: @portfolio_company.id,
    standard_kpi_name: name
  ).first_or_initialize
  mapping.reported_kpi_name = name
  mapping.autofill = mode
  mapping.compute_formula = formula
  mapping.save!
end

Then('I should see a {string} KPI {string} for {string} with value {string}') do |period, name, as_of, value|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: date }).last
  expect(kpi).not_to be_nil
  expect(kpi.value.to_f).to eq(value.to_f)
end

Then('I should NOT see a {string} KPI {string} for {string}') do |period, name, as_of|
  date = Date.parse(as_of)
  kpi = Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: date }).last
  expect(kpi).to be_nil
end

Then('the {string} KPI {string} for {string} should have {int} record') do |period, name, as_of, count|
  date = Date.parse(as_of)
  kpis = Kpi.joins(:kpi_report).where(name: name, entity_id: @entity.id, portfolio_company_id: @portfolio_company.id, kpi_reports: { period: period, as_of: date })
  expect(kpis.count).to eq(count)
end

Then('Quarterly KPI should be cumulated correctly for {string}') do |kpi_name|
  quarterly_kpis = Kpi.joins(:kpi_report).where(name: kpi_name, 'kpi_reports.period': "Quarter")
  quarterly_kpis.count.should
  quarterly_kpis.each do |kpi|
    puts "Checking Quarterly KPI #{kpi.name} for period #{kpi.kpi_report.as_of}"
    quarter = ((kpi.kpi_report.as_of.month - 1) / 3) + 1
    year = kpi.kpi_report.as_of.year
    months_in_quarter = Date.new(year, ((quarter - 1) * 3) + 1, 1)..Date.new(year, ((quarter - 1) * 3) + 3, -1)
    expected_sum = Kpi.joins(:kpi_report).where(name: kpi_name, 'kpi_reports.period': "Month", 'kpi_reports.as_of': months_in_quarter, 'kpi_reports.tag_list': 'Actual').sum(:value)
    kpi.value.should == expected_sum
    puts "Expected sum: #{expected_sum}, Actual sum: #{kpi.value}"
  end
end

Then('YTD KPI should be cumulated correctly for {string}') do |kpi_name|
  ytd_kpis = Kpi.joins(:kpi_report).where(name: kpi_name, 'kpi_reports.period': "YTD")
  ytd_kpis.count.should
  ytd_kpis.each do |kpi|
    months = (kpi.portfolio_company.json_fields['month_offset_for_fy'] || 3).to_i
    puts "Checking YTD KPI #{kpi.name} for period #{kpi.kpi_report.as_of}"

    year_start = kpi.portfolio_company.start_of_financial_year_date(kpi.kpi_report.as_of)
    # YTD sum should be from start of FY up to the current report's as_of date
    months_so_far = year_start..kpi.kpi_report.as_of

    expected_sum = Kpi.joins(:kpi_report).where(name: kpi_name, 'kpi_reports.period': "Month", 'kpi_reports.as_of': months_so_far, 'kpi_reports.tag_list': 'Actual', portfolio_company_id: kpi.portfolio_company_id).sum(:value)

    binding.pry if kpi.value != expected_sum
    kpi.value.should == expected_sum
    puts "Expected sum: #{expected_sum}, Actual sum: #{kpi.value}"
  end
end
