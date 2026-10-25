# Steps for the portfolio report combined packet change (openspec/changes/portfolio-report-combined-packet).
# F4 extract steps first: features/fund/portfolio_report_extracts.feature

EXTRACT_PERIOD_START = Date.new(2024, 1, 1)
EXTRACT_PERIOD_END = Date.new(2025, 12, 31)

# Records what the language model was given instead of calling it.
def stub_doc_llm_context_recording
  @llm_calls = []
  sections = { "Quarterly Update" => ["Revenue grew in the period."] }
  allow(DocLlmContext).to receive(:call) do |**args|
    @llm_calls << args
    { extracted_info: sections.to_json }
  end
end

def create_company_kpi(name, value, as_of, display_value: nil)
  mapping = FactoryBot.create(:investor_kpi_mapping, investor: @investor, entity: @investor.entity,
                                                     reported_kpi_name: name, standard_kpi_name: name)
  kpi_report = KpiReport.create!(entity: @investor.entity, user: @user, portfolio_company: @investor,
                                 as_of: as_of, period: "Q2")
  FactoryBot.create(:kpi, kpi_report: kpi_report, entity: @investor.entity, portfolio_company: @investor,
                          name: name, value: value, display_value: display_value, investor_kpi_mapping: mapping)
end

Given('the company has notes and KPIs but no documents') do
  # Tagged with the report's tag, as the extract only uses notes that match it
  Note.create!(details: "Delta signed a new distributor in June", entity: @investor.entity, user: @user,
               owner: @investor, on: Date.new(2024, 6, 15), tags: @portfolio_report.tags)
  create_company_kpi("Revenue", 1200, Date.new(2024, 6, 30))
  # An earlier report in the period: only the latest KPI report is used
  create_company_kpi("Headcount", 40, Date.new(2024, 3, 31))
end

Given('the company has KPIs but no documents or notes') do
  create_company_kpi("Revenue", 1200, Date.new(2024, 6, 30))
end

Given('the company has a Revenue KPI shown as {string} but no documents or notes') do |display_value|
  create_company_kpi("Revenue", 1_200_000, Date.new(2024, 6, 30), display_value:)
end

Given('the company has no documents, notes or KPIs in the period') do
  expect(Kpi.where(portfolio_company_id: @investor.id)).to be_empty
  expect(Note.where(owner: @investor)).to be_empty
end

When('the extract is generated for the company') do
  stub_doc_llm_context_recording
  @job = GeneratePortfolioReportExtractsJob.new
  allow(@job).to receive(:send_notification).and_call_original
  @extract, @extract_message = @job.generate_extract(@investor, @portfolio_report, EXTRACT_PERIOD_START,
                                                     EXTRACT_PERIOD_END, @user.id, notify: true)
end

When('the extracts are generated for the company in a bulk run') do
  stub_doc_llm_context_recording
  @job = GeneratePortfolioReportExtractsJob.new
  allow(@job).to receive(:send_notification).and_call_original
  allow(EntityMailer).to receive_message_chain(:with, :doc_gen_errors, :deliver_now)
  @job.perform([@investor.id], @portfolio_report.id, EXTRACT_PERIOD_START, EXTRACT_PERIOD_END, @user.id)
end

Then('the bulk run reports the missing documents in one warning at the end') do
  expect(@job).to have_received(:send_notification)
    .with(a_string_matching(/No documents found for Delta Inc.*Extract built from notes and KPIs/), @user.id, "warning").once
end

Then('the extract has data') do
  expect(@extract.reload.data).to be_present
end

Then('the extract has no data') do
  expect(@extract.reload.data).to be_blank
end

Then('the extract records no source documents') do
  expect(@extract.reload.source_document_ids).to be_blank
end

Then('a warning says no documents were found and the extract was built from notes and KPIs') do
  expect(@job).to have_received(:send_notification)
    .with(a_string_matching(/No documents found for Delta Inc.*Extract built from notes and KPIs/), @user.id, "warning")
  expect(@extract_message).to be_nil
end

Then('no warning is shown') do
  expect(@job).not_to have_received(:send_notification).with(anything, anything, "warning")
end

Then('the LLM was given the notes and the KPIs') do
  call = @llm_calls.last
  expect(call[:notes].to_a).not_to be_empty
  expect(call[:kpis]).to include("Revenue: 1200.0 (as of 2024-06-30)")
  expect(call[:kpis]).not_to include("Headcount")
end

Then('the LLM was given the KPIs and no notes') do
  call = @llm_calls.last
  expect(call[:notes].to_a).to be_empty
  expect(call[:kpis]).to include("Revenue: 1200.0")
end

Then('the LLM was given the KPI as {string}') do |text|
  expect(@llm_calls.last[:kpis]).to include("Revenue: #{text} (as of 2024-06-30)")
end

Then('the LLM was given the documents and notes but no KPIs') do
  call = @llm_calls.last
  expect(call[:documents].to_a).not_to be_empty
  expect(call[:kpis]).to be_nil
end

Then('the LLM was not called') do
  expect(@llm_calls).to be_empty
end

Then('the company is reported as having nothing to extract from') do
  expect(@extract_message).to include("No documents found for Delta Inc")
end

# ── Widget (H12, E15) ──────────────────────────────────────────────────────────

Given('the company has extracts for the report:') do |table|
  table.hashes.each do |row|
    end_date = Date.parse(row["end_date"])
    data = row["data"] == "yes" ? { "Quarterly Update" => ["Update ending #{row['end_date']}"] }.to_json : nil
    @extracts = (@extracts || []) << PortfolioReportExtract.create!(
      entity: @investor.entity, portfolio_company: @investor, portfolio_report: @portfolio_report,
      start_date: end_date - 3.months, end_date: end_date, data: data
    )
  end
end

Given('the company has {int} blank extracts newer than those') do |count|
  latest = @extracts.map(&:end_date).max
  count.times do |i|
    end_date = latest + (i + 1).months
    @extracts << PortfolioReportExtract.create!(
      entity: @investor.entity, portfolio_company: @investor, portfolio_report: @portfolio_report,
      start_date: end_date - 1.month, end_date: end_date, data: i.even? ? nil : {}
    )
  end
end

Given('the company dashboard has a Portfolio Report widget for the report') do
  DashboardWidget.create!(entity: @investor.entity, dashboard_name: "Portfolio Company Dashboard",
                          widget_name: "Portfolio Report", size: "XL", tags: "test", position: 1,
                          metadata: "{portfolio_report_id: #{@portfolio_report.id}}")
end

When('I open the company dashboard') do
  visit(dashboard_investor_path(@investor))
end

Then('the widget shows the extract ending {string}') do |end_date|
  expect(page).to have_content("Update ending #{end_date}")
end

Then('the widget does not show any extract') do
  expect(page).not_to have_content("Update ending")
end

# ── Delete (H13, E16, E18, X15, X16) ───────────────────────────────────────────

When('I open the details page of the extract ending {string}') do |end_date|
  @extract = @extracts.find { |e| e.end_date == Date.parse(end_date) }
  visit(portfolio_report_extract_path(@extract))
end

When('I click Delete and confirm') do
  accept_confirm { click_on "Delete" }
  # Wait for the redirect so later steps see the extract as deleted
  expect(page).to have_content("Portfolio report extract deleted successfully.")
end

When('I click Delete and cancel') do
  dismiss_confirm { click_on "Delete" }
end

Then('I am on the extract list of the report with {string}') do |message|
  expect(page).to have_current_path(portfolio_report_extracts_path(portfolio_report_id: @portfolio_report.id))
  expect(page).to have_content(message)
end

Then('the extract no longer exists') do
  expect(PortfolioReportExtract.where(id: @extract.id)).to be_empty
end

Then('the extract still exists') do
  expect(PortfolioReportExtract.where(id: @extract.id)).to exist
end

Then('the details page is unchanged') do
  expect(page).to have_current_path(portfolio_report_extract_path(@extract))
  expect(page).to have_button("Delete")
end

Given('a user {string} with no access rights in the same entity') do |first_name|
  @other_user = FactoryBot.create(:user, entity: @entity, first_name:)
end

Given('a company admin {string} of another entity') do |first_name|
  @other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @other_user = FactoryBot.create(:user, entity: @other_entity, first_name:)
  @other_user.add_role(:company_admin)
end

When('{string} signs in') do |first_name|
  user = User.find_by!(first_name:)
  Capybara.reset_sessions!
  log_in(user)
end

# Builds and submits a real DELETE form from any rendered page, the same workaround the role update
# steps use (the Playwright driver has no rack_test style delete).
When('{string} sends a delete request for the extract ending {string}') do |_first_name, end_date|
  @extract = @extracts.find { |e| e.end_date == Date.parse(end_date) }
  visit(root_path)
  page.execute_script(<<~JS)
    (function () {
      const f = document.createElement('form'); f.method = 'POST'; f.action = '#{portfolio_report_extract_path(@extract)}';
      const add = (n, v) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); };
      add('authenticity_token', document.querySelector('meta[name="csrf-token"]')?.content || '');
      add('_method', 'delete');
      document.body.appendChild(f); f.submit();
    })();
  JS
  sleep(2)
end

Then('the policy refuses {string} to delete the extract') do |first_name|
  user = User.find_by!(first_name:)
  expect(PortfolioReportExtractPolicy.new(user, @extract).destroy?).to be(false)
end

Given('the company has an extract with data for the whole period') do
  @extracts = (@extracts || []) << PortfolioReportExtract.create!(
    entity: @investor.entity, portfolio_company: @investor, portfolio_report: @portfolio_report,
    start_date: EXTRACT_PERIOD_START, end_date: EXTRACT_PERIOD_END,
    data: { "Quarterly Update" => ["Update ending #{EXTRACT_PERIOD_END}"] }.to_json
  )
end

When('I open the details page of the extract for the whole period') do
  @extract = @extracts.last
  visit(portfolio_report_extract_path(@extract))
end

When('the report is generated for the company with generate missing extracts {string}') do |on_or_off|
  stub_doc_llm_context_recording
  PortfolioReportJob.perform_now(@portfolio_report.id, @template.id, EXTRACT_PERIOD_START, EXTRACT_PERIOD_END, @user.id,
                                 portfolio_company_ids: [@investor.id], generate_missing_extracts: on_or_off == "on")
end

Then('a new extract with data exists for the company and period') do
  extracts = PortfolioReportExtract.matching(@portfolio_report.id, @investor.id, EXTRACT_PERIOD_START, EXTRACT_PERIOD_END)
  expect(extracts.count).to eq(1)
  expect(extracts.first.id).not_to eq(@extract.id)
  expect(extracts.first.data).to be_present
end

Then('only an empty extract exists for the company and period') do
  extracts = PortfolioReportExtract.matching(@portfolio_report.id, @investor.id, EXTRACT_PERIOD_START, EXTRACT_PERIOD_END)
  expect(extracts.count).to eq(1)
  expect(extracts.first.id).not_to eq(@extract.id)
  expect(extracts.first.data).to be_blank
end

# ── Consolidated report (F1: features/fund/consolidated_portfolio_report.feature) ──────────────────

REPORT_FIXTURES = "public/sample_uploads/portfolio_reports_test".freeze
PACKET_PERIOD_START = Date.new(2026, 1, 1)
PACKET_PERIOD_END = Date.new(2026, 9, 30)

After do
  FileUtils.rm_rf(@packet_run_dir) if @packet_run_dir
end

# The text of a .docx, paragraph by paragraph, in document order.
def docx_text(path)
  xml = Zip::File.open(path) { |zip| zip.read("word/document.xml") }
  Nokogiri::XML(xml).remove_namespaces!.xpath("//p").map { |p| p.xpath(".//t").map(&:text).join }.join("\n")
end

def create_report_template(report, name, fixture)
  report.document_folder
  report.reload
  Document.create!(name:, entity: report.entity, user_id: @user.id, owner: report, owner_type: "PortfolioReport",
                   file: Rails.root.join(REPORT_FIXTURES, fixture).open("rb"), template: true, download: true, printing: true)
end

Given('a consolidated portfolio report {string} with template {string}') do |report_name, template_name|
  @consolidated_report = PortfolioReport.create!(name: report_name, entity: @user.entity, tags: "TestTag", consolidated: true)
  @consolidated_template = create_report_template(@consolidated_report, template_name, "cover_and_summary_template.docx")
end

# Created in the order given, as the first company created is not the first alphabetically
Given('portfolio companies {string} are created in that order') do |names|
  @portfolio_companies = names.split(",").map(&:strip).map do |name|
    steps %(Given there is an existing portfolio company "name=#{name};category=Portfolio Company")
    @investor
  end
end

Given('{string} has a Revenue KPI of {int}') do |company_name, value|
  company = Investor.find_by!(investor_name: company_name)
  mapping = FactoryBot.create(:investor_kpi_mapping, investor: company, entity: company.entity, show_in_report: true,
                                                     reported_kpi_name: "Revenue", standard_kpi_name: "Revenue")
  kpi_report = KpiReport.create!(entity: company.entity, user: @user, portfolio_company: company,
                                 as_of: Date.new(2026, 3, 31), period: "Q1")
  FactoryBot.create(:kpi, kpi_report:, entity: company.entity, portfolio_company: company, name: "Revenue",
                          value:, investor_kpi_mapping: mapping)
end

# One buy in the fund, with the IRR run the report reads (latest on or before the period end)
Given('{string} has an IRR of {int} in the fund {string}') do |company_name, value, fund_name|
  company = Investor.find_by!(investor_name: company_name)
  entity = company.entity
  fund = Fund.find_by(name: fund_name, entity_id: entity.id) || FactoryBot.create(:fund, entity:, name: fund_name)
  instrument = FactoryBot.create(:investment_instrument, entity:, portfolio_company: company)
  pi = FactoryBot.build(:portfolio_investment, entity:, fund:, portfolio_company: company, investment_instrument: instrument,
                                               quantity: 100, investment_date: Date.new(2025, 1, 10))
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?

  FactoryBot.create(:fund_ratio, entity:, fund:, owner: company, name: "IRR", value:, end_date: Date.new(2026, 3, 31))
end

When('I create a portfolio report {string} ticking Consolidated') do |name|
  visit(new_portfolio_report_path)
  fill_in "Name", with: name
  check "Consolidated"
  click_on "Save"
  expect(page).to have_content(name)
  @consolidated_report = PortfolioReport.find_by!(name:)
end

When('I create a portfolio report {string} without ticking Consolidated and leave the section blank') do |name|
  visit(new_portfolio_report_path)
  fill_in "Name", with: name
  click_on "Save"
  expect(page).to have_content(name)
end

When('I create a portfolio report {string} ticking Consolidated with the section {string} filled in') do |name, section|
  visit(new_portfolio_report_path)
  fill_in "Name", with: name
  fill_in "Section Name", with: section
  fill_in "Section Data", with: "Summarise the company"
  check "Consolidated"
  click_on "Save"
  expect(page).to have_content(name)
  @consolidated_report = PortfolioReport.find_by!(name:)
end

When('I open the new portfolio report form') do
  visit(new_portfolio_report_path)
end

When('I tick Consolidated') do
  check "Consolidated"
end

When('I untick Consolidated') do
  uncheck "Consolidated"
end

Then('the sections and the Add Section button are shown') do
  expect(page).to have_field("Section Name")
  expect(page).to have_link("Add Section")
end

Then('the sections and the Add Section button are hidden') do
  expect(page).to have_no_field("Section Name")
  expect(page).to have_no_link("Add Section")
end

Given('the portfolio report {string} has a template') do |name|
  PortfolioReportTemplate.create!(portfolio_report: PortfolioReport.find_by!(name:), name: "Default", output_format: "word")
end

When('I visit the portfolio reports page') do
  visit(portfolio_reports_path)
end

Then('the portfolio report {string} shows as ready') do |name|
  expect(find("tr", text: name)).to have_content("Ready")
end

Then('the portfolio report {string} has no sections') do |name|
  expect(PortfolioReport.find_by!(name:).portfolio_report_sections).to be_empty
end

Then('the portfolio report {string} has the section {string}') do |name, section|
  expect(PortfolioReport.find_by!(name:).portfolio_report_sections.pluck(:name)).to eq([section])
end

When('I reopen the portfolio report for editing') do
  visit(edit_portfolio_report_path(@consolidated_report || @portfolio_report))
end

Then('the Consolidated box is ticked') do
  expect(page).to have_checked_field("Consolidated")
end

Then('the Consolidated box is not ticked') do
  expect(page).to have_unchecked_field("Consolidated")
end

When('the consolidated report is built for the selected companies') do
  @packet_run_dir = Rails.root.join("tmp/packet_test_#{SecureRandom.hex(4)}").to_s
  FileUtils.mkdir_p(@packet_run_dir)
  @extract_count_before = PortfolioReportExtract.count
  path = PortfolioReportConsolidatedDocGenerator.new(@portfolio_companies, @consolidated_template, PACKET_PERIOD_START,
                                                     PACKET_PERIOD_END, @user.id, output_dir: @packet_run_dir).call
  @consolidated_text = docx_text(path)
end

Then('the document text lists {string} in that order, each once') do |names|
  positions = names.split(",").map(&:strip).map do |name|
    expect(@consolidated_text.scan(name).size).to eq(1), "expected #{name} exactly once in:\n#{@consolidated_text}"
    @consolidated_text.index(name)
  end
  expect(positions).to eq(positions.sort)
end

Then('the document shows {string} with {string} IRR {int}') do |company, fund, value|
  expect(@consolidated_text).to match(%r{#{Regexp.escape(company)}\n#{Regexp.escape(fund)}\nIRR: #{value}(\.0+)?\nMOIC: N/A\n})
end

Then('the document shows {string} with no fund lines') do |company|
  expect(@consolidated_text).to match(/#{Regexp.escape(company)}\n(?!Alpha Fund)/)
end

Given('a consolidated portfolio report {string} with the fund totals template') do |report_name|
  @consolidated_report = PortfolioReport.create!(name: report_name, entity: @user.entity, tags: "TestTag", consolidated: true)
  @consolidated_template = create_report_template(@consolidated_report, "Fund totals", "fund_totals_template.docx")
end

# A number custom field (investment_commitment) and a text one (company_note) on the Investor form type; the note is set
# on every company named, the commitment is the value given, a company left out has neither
Given('the companies have these custom fields: {string}') do |pairs|
  entity = @user.entity
  form_type = entity.form_types.where(name: "Investor").last || FormType.create!(entity:, name: "Investor", tag: "Default")
  { "investment_commitment" => "NumberField", "company_note" => "TextField" }.each do |name, field_type|
    FormCustomField.find_or_create_by!(form_type:, name:) do |field|
      field.label = name.titleize
      field.field_type = field_type
      field.required = false
    end
  end
  @portfolio_companies.each do |company|
    company.form_type = form_type
    company.skip_cf_before_save = true
    company.save!
  end
  pairs.split(",").map { |pair| pair.split("=").map(&:strip) }.each do |name, value|
    company = @portfolio_companies.find { |candidate| candidate.investor_name == name }
    company.skip_cf_before_save = true
    company.update!(json_fields: company.json_fields.merge("investment_commitment" => value, "company_note" => "note of #{name}"))
  end
end

def fund_total_lines(fund)
  text = @consolidated_text
  lines = text.scan(/^Line: #{Regexp.escape(fund)} \| FMV ([\d,.]+) \| COST ([\d,.]+)$/)
  total = text[/^Total #{Regexp.escape(fund)}\n.*?(?=^Total [^FcnN]|\z)/m]
  [lines.map { |fmv, cost| [fmv.delete(",").to_d, cost.delete(",").to_d] }, total]
end

Then('the {string} total FMV and cost are the sums of the companies\' lines') do |fund|
  lines, total = fund_total_lines(fund)
  expect(lines).not_to be_empty, "no company lines for #{fund} in:\n#{@consolidated_text}"
  expect(total).to be_present, "no total for #{fund} in:\n#{@consolidated_text}"
  expect(total[/^Total FMV: ([\d,.]+)$/, 1].delete(",").to_d).to eq(lines.sum(&:first))
  expect(total[/^Total cost: ([\d,.]+)$/, 1].delete(",").to_d).to eq(lines.sum(&:last))
  expect(@consolidated_text.scan(/^Total #{Regexp.escape(fund)}$/).size).to eq(1)
end

Then('the {string} total commitment is {int}') do |fund, value|
  _, total = fund_total_lines(fund)
  amount = total.to_s[/^Total commitment: ([\d,.]+)$/, 1]
  expect(amount).to be_present, "no commitment total for #{fund} in:\n#{@consolidated_text}"
  expect(amount.delete(",").to_d).to eq(value.to_d)
end

Then('the {string} total has no value for the text field') do |fund|
  _, total = fund_total_lines(fund)
  expect(total).to match(/^Total note: ?$/)
end

Then('no extract was created') do
  expect(PortfolioReportExtract.count).to eq(@extract_count_before)
  expect(PortfolioReportExtract.count).to eq(0)
end

# ── The packet run (F2: features/fund/portfolio_report_combined_packet.feature) ─────────────────────

SECTION_NAMES = ["Overview", "Quarterly Update", "AI Risk", "Financial Analysis", "Risk Factors"].freeze

Given('a normal portfolio report {string} with templates {string}') do |report_name, template_names|
  @reports ||= {}
  @templates ||= {}
  report = PortfolioReport.create!(name: report_name, entity: @user.entity, tags: "TestTag")
  SECTION_NAMES.each { |name| PortfolioReportSection.create!(portfolio_report: report, name:, data: "Sample data for #{name}") }
  template_names.split(",").map(&:strip).each do |template_name|
    @templates[template_name] = create_report_template(report, template_name, "portfolio_report_template.docx")
  end
  @reports[report_name] = report
end

Given('a consolidated portfolio report {string} with the fixture template {string}') do |report_name, template_name|
  @reports ||= {}
  @templates ||= {}
  report = PortfolioReport.create!(name: report_name, entity: @user.entity, tags: "TestTag", consolidated: true)
  fixture = template_name == "Legal Disclaimer" ? "legal_disclaimer_template.docx" : "cover_and_summary_template.docx"
  @templates[template_name] = create_report_template(report, template_name, fixture)
  @reports[report_name] = report
end

Given('extracts with data exist for {string} for report {string}') do |company_names, report_name|
  company_names.split(",").map(&:strip).each do |company_name|
    PortfolioReportExtract.create!(
      entity: @user.entity, portfolio_company: Investor.find_by!(investor_name: company_name), portfolio_report: @reports[report_name],
      start_date: PACKET_PERIOD_START, end_date: PACKET_PERIOD_END, source_document_ids: [],
      data: SECTION_NAMES.index_with { |name| ["#{name} point for #{company_name}"] }.to_json
    )
  end
end

# Rows are "Report:Template" pairs in the order they appear on the options page
def parse_packet_rows(rows)
  rows.split(",").map(&:strip).map do |row|
    report_name, template_name = row.split(":").map(&:strip)
    [@reports.fetch(report_name), @templates.fetch(template_name)]
  end
end

Given('the run is for the companies {string}') do |names|
  @selected_company_names = names.split(",").map(&:strip)
end

Given('no extracts exist') do
  PortfolioReportExtract.destroy_all
end

Given('generating the consolidated part {string} will fail') do |template_name|
  allow(PortfolioReportConsolidatedDocGenerator).to receive(:new).and_wrap_original do |original, *args, **kwargs|
    raise "#{template_name} exploded" if args[1].name == template_name

    original.call(*args, **kwargs)
  end
end

def capture_run_alerts
  @alerts = []
  allow_any_instance_of(PortfolioReportJob).to receive(:send_notification) do |_job, message, _user_id, level = "success"|
    @alerts << [message, level]
  end
end

def run_packet(rows, generate_missing: false, legacy_signature: false)
  capture_run_alerts
  pairs = parse_packet_rows(rows)
  first_report, first_template = pairs.first
  companies = @selected_company_names ? Investor.portfolio_companies.where(investor_name: @selected_company_names) : Investor.portfolio_companies
  options = { portfolio_company_ids: companies.pluck(:id), generate_missing_extracts: generate_missing }
  options[:additional_parts] = pairs.drop(1).map { |report, template| { "portfolio_report_id" => report.id, "template_id" => template.id } } unless legacy_signature
  PortfolioReportJob.perform_now(first_report.id, first_template.id, PACKET_PERIOD_START, PACKET_PERIOD_END, @user.id, **options)
end

When('I run the portfolio report with rows {string}') do |rows|
  run_packet(rows)
end

When('I run the portfolio report with rows {string} and generate missing extracts on') do |rows|
  stub_doc_llm_context_call
  run_packet(rows, generate_missing: true)
end

# E9: a job queued before this change, with only the original arguments
When('a job queued with only the original arguments is performed for {string}') do |rows|
  run_packet(rows, legacy_signature: true)
end

Given('generating {string} for {string} will fail') do |_template_name, company_name|
  allow(PortfolioReportDocGenerator).to receive(:new).and_wrap_original do |original, *args, **kwargs|
    raise "#{company_name} exploded" if args.first.investor_name == company_name

    original.call(*args, **kwargs)
  end
end

Given('generating the consolidated part will fail') do
  allow(PortfolioReportConsolidatedDocGenerator).to receive(:new).and_raise("Cover exploded")
end

Given('every part will fail to generate') do
  allow(PortfolioReportDocGenerator).to receive(:new).and_raise("Company part exploded")
  allow(PortfolioReportConsolidatedDocGenerator).to receive(:new).and_raise("Cover exploded")
end

Given('joining the parts will fail') do
  allow(DocxMerger).to receive(:merge).and_raise("Merge exploded")
end

def combined_documents(name_prefix)
  Document.where("name LIKE ?", "#{name_prefix} 2026-01-01 to 2026-09-30 - % companies").order(:id)
end

def combined_text(name_prefix)
  document = combined_documents(name_prefix).last
  expect(document).to be_present, "no combined document named like #{name_prefix}"
  document.file.download { |file| return docx_text(file.path) }
end

Then('one combined document {string} exists in Portfolio Reports \/ Generated Portfolio Reports') do |name|
  documents = Document.where(name:)
  expect(documents.count).to eq(1)
  expect(documents.first.folder.name).to eq("Generated Portfolio Reports")
  expect(documents.first.folder.parent.name).to eq("Portfolio Reports")
end

Then('the combined document {string} reads in this order: {string}') do |name_prefix, markers|
  text = combined_text(name_prefix)
  positions = markers.split("|").map(&:strip).map do |marker|
    expect(text).to include(marker), "expected #{marker.inspect} in:\n#{text}"
    text.index(marker)
  end
  expect(positions).to eq(positions.sort)
end

# The company pages are everything between the cover's closing page and the disclaimer
def company_pages(name_prefix)
  text = combined_text(name_prefix)
  start_at = text.index("Summary notes") || 0
  end_at = text.index("Legal Disclaimer") || text.length
  text[start_at...end_at]
end

Then('in the combined document {string} the company pages run {string}') do |name_prefix, companies|
  pages = company_pages(name_prefix)
  positions = companies.split(",").map(&:strip).map { |company| pages.index(company) }
  expect(positions.compact.size).to eq(positions.size), "company missing from the pages: #{pages}"
  expect(positions).to eq(positions.sort)
end

Then('in the combined document {string} the company pages do not include {string}') do |name_prefix, company|
  expect(company_pages(name_prefix)).not_to include(company)
end

Then('the combined document {string} contains {string}') do |name_prefix, text|
  expect(combined_text(name_prefix)).to include(text)
end

Then('each company has its own {string} report document') do |template_name|
  Investor.portfolio_companies.each do |company|
    expect(Document.where("name LIKE ?", "#{template_name} #{company.investor_name} %")).to exist, "no #{template_name} for #{company.investor_name}"
  end
end

Then('{string} has its own {string} report document') do |company_name, template_name|
  expect(Document.where("name LIKE ?", "#{template_name} #{company_name} %").count).to eq(1)
end

Then('{string} has no {string} report document') do |company_name, template_name|
  expect(Document.where("name LIKE ?", "#{template_name} #{company_name} %")).to be_empty
end

Then('no document exists for the consolidated part {string}') do |template_name|
  expect(Document.where("name LIKE ?", "#{template_name} 2%")).to be_empty
end

Then('no combined document exists') do
  expect(Document.where("name LIKE ?", "% 2026-01-01 to 2026-09-30 - % companies")).to be_empty
end

Then('{int} combined documents named {string} exist') do |count, name_prefix|
  expect(combined_documents(name_prefix).count).to eq(count)
end

Then('the completion message says {string}') do |text|
  expect(@alerts.map(&:first).join("\n")).to include(text)
end

Then('the completion message links to {string}') do |document_name|
  expect(@alerts.map(&:first).join("\n")).to include(document_name)
end

Then('the completion message is a success') do
  expect(@alerts.last.last).to eq("success")
end

Then('the completion message is an error') do
  expect(@alerts.last.last).to eq("danger")
end

Then('an error email is sent') do
  expect(ActionMailer::Base.deliveries).not_to be_empty
end

Then('{int} extracts exist for report {string}') do |count, report_name|
  expect(PortfolioReportExtract.where(portfolio_report_id: @reports[report_name].id).count).to eq(count)
end

Then('every part of the combined document {string} after the first starts a new page without a break paragraph of its own') do |name_prefix|
  combined_documents(name_prefix).last.file.download do |file|
    body = Zip::File.open(file.path) { |zip| Nokogiri::XML(zip.read("word/document.xml")).remove_namespaces! }
    # the cover comes first; each company page and the disclaimer then start a page
    expect(body.xpath("//pPr/pageBreakBefore").size).to eq(Investor.portfolio_companies.count + 1)
    own = Zip::File.open(Rails.root.join(REPORT_FIXTURES, "cover_and_summary_template.docx").to_s) { |zip| zip.read("word/document.xml") }
    break_paragraphs = "//p[r/br[@type='page']]"
    expect(body.xpath(break_paragraphs).size).to eq(Nokogiri::XML(own).remove_namespaces!.xpath(break_paragraphs).size)
  end
end

Then('the combined document {string} package is intact') do |name_prefix|
  document = combined_documents(name_prefix).last
  document.file.download do |file|
    Zip::File.open(file.path) do |zip|
      rels = Nokogiri::XML(zip.read("word/_rels/document.xml.rels")).remove_namespaces!
      relationships = rels.xpath("//Relationship")
      missing = relationships.reject { |rel| rel["TargetMode"] == "External" || zip.find_entry("word/#{rel['Target']}") }
      expect(missing.map { |rel| rel["Target"] }).to be_empty
      duplicates = relationships.group_by { |rel| [rel["Type"], rel["Target"]] }.select { |_, group| group.size > 1 }
      expect(duplicates.keys).to be_empty
      used = Nokogiri::XML(zip.read("word/document.xml")).xpath("//@r:embed|//@r:id", "r" => DocxMerger::R_NS).map(&:value)
      expect(used - relationships.map { |rel| rel["Id"] }).to be_empty
    end
  end
end

# ── The parts list (F3: features/fund/portfolio_report_parts_list.feature) ──────────────────────────

# The runs are recorded instead of queued, so a scenario can see what the page handed to the job.
# The app server runs in this process, so the stub applies to the request too.
Given('report runs and extract runs are recorded instead of queued') do
  @queued_runs = []
  @queued_extracts = []
  allow(PortfolioReportJob).to receive(:perform_later) { |*args, **kwargs| @queued_runs << { args:, kwargs: } }
  allow(GeneratePortfolioReportExtractsJob).to receive(:perform_later) { |*args| @queued_extracts << args }
end

Given('a normal portfolio report {string} with no templates') do |report_name|
  @reports ||= {}
  @reports[report_name] = PortfolioReport.create!(name: report_name, entity: @user.entity, tags: "TestTag")
end

When('I open the options page for the selected companies') do
  visit(legacy_bulk_generate_portfolio_reports_path)
  steps %(Given I select the portfolio companies for bulk generation)
end

def parts_row(number)
  all("[data-report-parts-target='row']", minimum: number)[number - 1]
end

Then('the options page has {int} report row(s)') do |count|
  expect(page).to have_css("[data-report-parts-target='row']", count:)
end

When('I click Add report') do
  click_on "Add report"
end

When('I remove report row {int}') do |number|
  parts_row(number).click_on("Remove")
end

Then('report row {int} has no Remove button') do |number|
  expect(parts_row(number)).to have_no_button("Remove")
end

When('I choose the report {string} in row {int}') do |report_label, number|
  parts_row(number).find("select[name$='[portfolio_report_id]']").select(report_label)
end

When('I choose the template {string} in row {int}') do |template_label, number|
  parts_row(number).find("select[name$='[report_template_id]']").select(template_label)
end

def row_option_texts(number, field)
  index = number - 1
  page.evaluate_script(<<~JS)
    Array.from(document.querySelectorAll("[data-report-parts-target='row']")[#{index}]
      .querySelectorAll("select[name$='[#{field}]'] option")).filter(o => !o.hidden).map(o => o.text.trim())
  JS
end

Then('row {int} offers only the templates {string}') do |number, templates|
  expect(row_option_texts(number, "report_template_id")).to eq(templates.split(",").map(&:strip))
end

Then('row {int} has the template {string} selected') do |number, template|
  expect(parts_row(number).find("select[name$='[report_template_id]']").value).to eq(@templates.fetch(template).id.to_s)
end

Then('the report choices read {string}') do |labels|
  expect(row_option_texts(1, "portfolio_report_id")).to eq(labels.split(",").map(&:strip))
end

When('I click {string} on the options page') do |button|
  click_on button
end

Then('{string} is shown beside row {int}') do |message, number|
  expect(parts_row(number)).to have_css(".invalid-feedback", text: message)
end

Then('{string} is no longer shown') do |message|
  expect(page).to have_no_content(message)
end

Then('{string} is shown on the options page') do |message|
  expect(page).to have_content(message)
end

Then('nothing was queued') do
  sleep 1
  expect(@queued_runs).to be_empty
  expect(@queued_extracts).to be_empty
end

Then('one report run was queued') do
  expect(eventually_queued_runs.size).to eq(1)
end

def eventually_queued_runs
  Timeout.timeout(5) { sleep 0.2 while @queued_runs.empty? }
  @queued_runs
rescue Timeout::Error
  @queued_runs
end

Then('the queued run starts with {string} and continues with {string}') do |first, rest|
  run = eventually_queued_runs.last
  report_ids = [run[:args].first] + run[:kwargs][:additional_parts].pluck("portfolio_report_id")
  expected = ([first] + rest.split(",").map(&:strip).reject(&:empty?)).map { |name| @reports.fetch(name).id }
  expect(report_ids).to eq(expected)
end

Then('the queued run has no additional reports') do
  expect(eventually_queued_runs.last[:kwargs][:additional_parts]).to eq([])
end

Then('extracts were queued only for {string}') do |report_name|
  Timeout.timeout(5) { sleep 0.2 while @queued_extracts.empty? }
  expect(@queued_extracts.pluck(1)).to eq([@reports.fetch(report_name).id])
  expect(@queued_extracts.first.first.size).to eq(Investor.portfolio_companies.count)
end

# A request like a script would send it, bypassing the page's own checks
def post_options_directly(fields)
  visit(legacy_bulk_generate_portfolio_reports_path)
  inputs = fields.map { |name, value| "add(#{name.to_json}, #{value.to_s.to_json});" }.join("\n")
  page.execute_script(<<~JS)
    (function () {
      const f = document.createElement('form'); f.method = 'POST'; f.action = '#{legacy_bulk_generate_options_portfolio_reports_path}';
      const add = (n, v) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); };
      add('authenticity_token', document.querySelector('meta[name="csrf-token"]')?.content || '');
      #{inputs}
      document.body.appendChild(f); f.submit();
    })();
  JS
  sleep 2
end

def posted_company_fields(extra_company_ids = [])
  (@portfolio_companies || [@investor]).map(&:id).concat(extra_company_ids).map { |id| ["portfolio_company_ids[]", id] }
end

def template_id_of(name)
  @templates.fetch(name).id
end

def report_id_of(name)
  @reports.fetch(name).id
end

# E6: row numbers with gaps
When('a request posts rows numbered 0, 2 and 5 for {string}, {string} and {string}') do |first, second, third|
  fields = posted_company_fields + [%w[mode full_report], %w[start_date 2026-01-01], %w[end_date 2026-09-30]]
  [[0, first], [5, third], [2, second]].each do |row, pair|
    report, template = pair.split(":")
    fields << ["parts[#{row}][portfolio_report_id]", report_id_of(report)]
    fields << ["parts[#{row}][report_template_id]", template_id_of(template)]
  end
  post_options_directly(fields)
end

# E8: the earlier single report form
When('a request posts one report {string} and template {string} without rows') do |report, template|
  fields = posted_company_fields + [%w[mode full_report], %w[start_date 2026-01-01], %w[end_date 2026-09-30],
                                    ["portfolio_report_id", report_id_of(report)], ["report_template_id", template_id_of(template)]]
  post_options_directly(fields)
end

# X3, X4, X12, X13, X14: tampered rows. Each row is "Report:Template", "Report:" (no template)
# or "Report:#<id>" for a template id taken as is.
When('a request posts the rows {string} in mode {string}') do |rows, mode|
  fields = posted_company_fields + [["mode", mode], %w[start_date 2026-01-01], %w[end_date 2026-09-30]]
  rows.split(",").map(&:strip).each_with_index do |row, index|
    report, template = row.split(":", 2)
    report_id = report.start_with?("#") ? report.delete_prefix("#") : report_id_of(report)
    template_id = if template.to_s.empty? then ""
                  elsif template.start_with?("#") then template.delete_prefix("#")
                  else template_id_of(template)
                  end
    fields << ["parts[#{index}][portfolio_report_id]", report_id]
    fields << ["parts[#{index}][report_template_id]", template_id]
  end
  post_options_directly(fields)
end

Given('another entity has a report {string} and a portfolio company {string}') do |report_name, company_name|
  @other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @other_report = PortfolioReport.create!(name: report_name, entity: @other_entity)
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor", name: company_name)
  @other_company = FactoryBot.create(:investor, entity: @other_entity, investor_entity:, investor_name: company_name, category: "Portfolio Company")
end

When('a request posts a row naming the other entity\'s report') do
  fields = posted_company_fields + [["mode", "full_report"], ["start_date", "2026-01-01"], ["end_date", "2026-09-30"],
                                    ["parts[0][portfolio_report_id]", @other_report.id], ["parts[0][report_template_id]", 1]]
  post_options_directly(fields)
end

When('a request posts one row {string} that also names the other entity\'s company') do |row|
  report, template = row.split(":")
  fields = posted_company_fields([@other_company.id]) + [["mode", "full_report"], ["start_date", "2026-01-01"], ["end_date", "2026-09-30"],
                                                         ["parts[0][portfolio_report_id]", report_id_of(report)],
                                                         ["parts[0][report_template_id]", template_id_of(template)]]
  post_options_directly(fields)
end

Then('the queued run does not include the other entity\'s company') do
  run = eventually_queued_runs.last
  expect(run[:kwargs][:portfolio_company_ids]).not_to include(@other_company.id)
  expect(run[:kwargs][:portfolio_company_ids].size).to eq((@portfolio_companies || [@investor]).size)
end

When('{string} posts one row {string} to the options step') do |first_name, row|
  Capybara.reset_sessions!
  log_in(User.find_by!(first_name:))
  report, template = row.split(":")
  fields = posted_company_fields + [["mode", "full_report"], ["start_date", "2026-01-01"], ["end_date", "2026-09-30"],
                                    ["parts[0][portfolio_report_id]", report_id_of(report)],
                                    ["parts[0][report_template_id]", template_id_of(template)]]
  post_options_directly(fields)
end

# ── The company step (H14, E19) ─────────────────────────────────────────────────────────────────────

When('I open the company step') do
  visit(legacy_bulk_generate_portfolio_reports_path)
end

Then('Next is disabled') do
  expect(page).to have_button("Next", disabled: true)
end

Then('Next is enabled') do
  expect(page).to have_button("Next", disabled: false)
end

# The list is a select2; its real <select> is hidden, so the options are set directly (as the bulk steps do)
When('I choose the first company in the list') do
  page.execute_script(<<~JS)
    var sel = document.querySelector("select[name='portfolio_company_ids[]']");
    sel.options[0].selected = true;
    sel.dispatchEvent(new Event('change', { bubbles: true }));
  JS
end

When('I clear the company list') do
  page.execute_script(<<~JS)
    var sel = document.querySelector("select[name='portfolio_company_ids[]']");
    Array.from(sel.options).forEach(function(o) { o.selected = false; });
    sel.dispatchEvent(new Event('change', { bubbles: true }));
  JS
end

When('I preview with a fund that has no portfolio investments') do
  fund = FactoryBot.create(:fund, entity: @user.entity, name: "Empty Fund")
  visit(legacy_bulk_generate_portfolio_reports_path(previewed: true, fund_ids: [fund.id]))
end
