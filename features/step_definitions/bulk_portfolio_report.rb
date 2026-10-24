
# Stub LLm portfolio report extract response

def stub_doc_llm_context_call
  # DocLlmContext.call returns a context whose [:extracted_info] is a JSON *string* of the sections
  # (see doc_llm_context.rb) — generate_extract stores exactly that into the extract's `data`. The
  # stub must mirror that shape: a hash with an :extracted_info key holding the sections as JSON.
  # Returning the raw sections hash instead leaves result[:extracted_info] nil, so data stays nil.
  sections = {
    "Quarterly Update" =>
    ["Net Sales in Q4FY25 reached 168,188 crores, representing 9.9% QoQ growth and 29.8% YoY growth compared to Q4FY24 (129,611 crores), demonstrating sustained momentum across India and international markets.",
     "EBITDA turned positive at 15,137 crores in Q4FY25 versus breakeven in Q4FY24, marking a significant turnaround driven by operational leverage and improved unit economics with contribution margin expanding to 40.8%.",
     "Contribution Margin improved to 40.8% in Q4FY25 from 40.6% in prior quarters, reflecting lower Customer Acquisition Cost, better fulfillment utilization, and higher Average Order Value from bundle offerings.",
     "Order volume increased to 258 orders in Q4FY25 from 199 in Q4FY24 (29.6% growth), while Logistics costs remained relatively controlled at 36,841 crores despite 8.4% volume growth, indicating improved operational efficiency."],
    "Overview" =>
    ["Echo Inc is a leading cosmetics-focused e-commerce company operating across India with expanding presence in Southeast Asia (Indonesia) and the Middle East (UAE, GCC), founded by serial entrepreneur Kunal Bansal; the company has demonstrated strong product-market fit with 25.4% FY25 revenue growth to 605 crores and inflection to EBITDA profitability.",
     "Key products and services include a balanced portfolio across Makeup, Skincare, Fragrance, and Haircare with emphasis on growth segments including Clean Beauty lines and region-specific formulations (halal-certified SKUs for GCC); the company operates a direct-to-consumer e-commerce platform with localized assortment strategies and fast fulfillment capabilities."],
    "AI Risk" => ["Look a the business mix and highlight any risk tot..."],
    "Financial Analysis" => ["Perform a detailed analysis of the financial perfo..."],
    "Risk Factors" => ["Draft key questions that the fund manager may want to ask regarding potential risks..."]
  }
  allow(DocLlmContext).to receive(:call).and_return({ extracted_info: sections.to_json })
end

Given('there are {string} portfolio investments for the portfolio company in the fund') do |string|
end

Given('I setup a portfolio report {string}') do |string|
  params = string.split(";").map { |param| param.split(":") }.to_h
  @portfolio_report = PortfolioReport.create!(name: params["name"] || "Test Report", include_kpi: params["include_kpi"] == "true", include_portfolio_investments: params["include_portfolio_investments"] == "true", entity: @investor.entity, tags: params["tags"] || "TestTag")
  @portfolio_report.document_folder
  @portfolio_report.reload
  expect(@portfolio_report.document_folder).to be_present
  @template = Document.create!(name: "Portfolio Report Template", entity: @investor.entity, user_id: @user.id, owner: @portfolio_report, owner_type: "PortfolioReport", file: File.open(Rails.root.join("public/sample_uploads/portfolio_reports_test/portfolio_report_template.docx"), "rb"), template: true, download: true, printing: true)
  ["Overview", "Quarterly Update", "AI Risk", "Financial Analysis", "Risk Factors"].each do |section_name|
    PortfolioReportSection.create!(portfolio_report: @portfolio_report, name: section_name, data: "Sample data for #{section_name} section")
  end
end

Given('I go to the portfolio company show page') do
  @investor ||= Investor.last
  visit(investor_path(@investor))
end

Given('I trigger report generation') do
  stub_doc_llm_context_call
  @report_docs_count = Document.where("name like ?", "%#{@portfolio_report.name}%").count
  @extracts_count = PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: @portfolio_company.id).count
  companies = @portfolio_companies || [@investor]
  @extracts_count_by_company = companies.to_h do |pc|
    [pc.id, PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: pc.id).count]
  end
  click_on "Generate Report"
  sleep 5
  # expect(page).to have_content("Portfolio Report Generation completed", wait: 5)
  # expect(page).to have_content("Queued report generation for", wait: 5)
end

# start_date:01/01/2024;end_date:31/12/2025;generate_missing_extracts:true
Given('I fill in the form with {string}') do |string|
  params = string.split(";").map { |param| param.split(":") }.to_h
  @start_date = Date.parse(params["start_date"] || "01/01/2024")
  @end_date = Date.parse(params["end_date"] || "31/12/2025")
  fill_in "start_date", with: @start_date
  fill_in "end_date", with: @end_date
  check "generate_missing_extracts" if params["generate_missing_extracts"]
  check "only_missing_extracts" if params["only_missing_extracts"]
end

# Then('I should see the {string}') do |string|
#   expect(page).to have_content(string, wait: 5)
# end

Then('The portfolio report should be generated') do
  puts "All Documents"
  puts Document.all.pluck(:name)
  expect(Document.where("name like ?", "%#{@template.name}%").count).to be > @report_docs_count
  @document = Document.where("name like ?", "%#{@template.name}%").order(created_at: :desc).first
end

Then('The portfolio extract should be generated with data {string}') do |string|
  @portfolio_company = @investor
  if string == "present"
    expect(PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: @portfolio_company.id).count).to be > @extracts_count
    @extract = PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: @portfolio_company.id).order(created_at: :desc).first
    expect(@extract.data).to be_present
  else
    expect(PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: @portfolio_company.id).count).to be > @extracts_count
    @extract = PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: @portfolio_company.id).order(created_at: :desc).first
    expect(@extract.data).to be_blank
  end
end

Given('I add relevant documents to the kpi report') do
  @kpi_report = KpiReport.where(portfolio_company_id: @portfolio_company.id).order(:as_of).last
  @kpi_report.as_of = Date.parse("2024-04-01") # keep date within the time period of the report generation
  @kpi_report.save!
  @kpi_report.document_folder
  @kpi_report.reload
  expect(@kpi_report.document_folder).to be_present
  Document.create!(name: "KPIs", entity: @portfolio_company.entity, user_id: @user.id, file: File.open(Rails.root.join("public/sample_uploads/portfolio_reports_test/KPIs.xlsx"), "rb"), owner: @kpi_report, owner_type: "KpiReport", folder: @kpi_report.document_folder)
  Document.create!(name: "KPIs", entity: @portfolio_company.entity, user_id: @user.id, file: File.open(Rails.root.join("public/sample_uploads/portfolio_reports_test/KPIs.csv"), "rb"), owner: @kpi_report, owner_type: "KpiReport", folder: @kpi_report.document_folder)
  Document.create!(name: "Investor Presentation", entity: @portfolio_company.entity, user_id: @user.id, file: File.open(Rails.root.join("public/sample_uploads/portfolio_reports_test/investor_presentation.pdf"), "rb"), owner: @kpi_report, owner_type: "KpiReport", folder: @kpi_report.document_folder)
end

Given('There is a kpi report form type setup') do
  @form_type = FormType.create!(entity: @portfolio_company.entity, name: "KpiReport", tag: "Default")
  ["investor_presentation"].each do |name|
    FormCustomField.create!(form_type: @form_type, name: name, label: name.titleize, field_type: "File", required: false)
  end
end

# ── Multi-company / bulk-page helpers ──────────────────────────────────────────
# The Background sets up ONE fully-featured portfolio company (Ace Limited). These helpers add a
# second one and drive the legacy bulk-generate page so we can cover the multi-company flows
# (merged document, only_missing / generate_missing toggles) without re-doing the UI KPI upload.

# A second portfolio company that reuses the entity-level KPI form type + fund from the Background.
# It gets its own KPI report dated inside the report window (01/01/2024–31/12/2025) that OWNS the
# sample source documents, so GeneratePortfolioReportExtractsJob#source_documents can find them and
# an extract with data can be built for it. Both companies are tracked in @portfolio_companies; the
# original (Ace Limited) is restored as the "current" @portfolio_company/@investor.
Given('there is another portfolio company {string} with a documented kpi report') do |name_args|
  original = @portfolio_company

  steps %(Given there is an existing portfolio company "#{name_args}")
  second = @portfolio_company # `there is an existing portfolio company` points @investor at the new one

  kpi_report = KpiReport.create!(entity: second.entity, user: @user, portfolio_company: second,
                                 as_of: Date.parse("2024-04-01"), period: "Q1")
  kpi_report.document_folder
  kpi_report.reload
  {
    "KPIs" => "KPIs.xlsx",
    "Investor Presentation" => "investor_presentation.pdf"
  }.each do |doc_name, file|
    Document.create!(name: doc_name, entity: second.entity, user_id: @user.id,
                     file: File.open(Rails.root.join("public/sample_uploads/portfolio_reports_test/#{file}"), "rb"),
                     owner: kpi_report, owner_type: "KpiReport", folder: kpi_report.document_folder)
  end

  @portfolio_companies = [original, second]
  @portfolio_company = original
  @investor = original
end

Given('I go to the bulk portfolio report page') do
  visit(legacy_bulk_generate_portfolio_reports_path)
end

# Selects the tracked companies in the `portfolio_company_ids[]` multi-select. The field is a
# select2, whose real <select> is hidden — so we set `selected` on the underlying options directly
# and fire a change event (select2 reads the submitted value from that same underlying select),
# then submit the "Next" step which hands off to the options screen.
Given('I select the portfolio companies for bulk generation') do
  ids = (@portfolio_companies || [@investor]).map(&:id)
  ids.each do |id|
    page.execute_script(<<~JS)
      var sel = document.querySelector("select[name='portfolio_company_ids[]']");
      Array.from(sel.options).forEach(function(o) { if (o.value === '#{id}') o.selected = true; });
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    JS
  end
  click_on "Next"
  sleep 2
end

# Snapshot per-company extract counts, stub the LLM, then click "Generate Extracts Only" on the
# options screen (as opposed to "Generate Report", which the existing `I trigger report generation`
# step handles).
Given('I trigger extract generation') do
  stub_doc_llm_context_call
  companies = @portfolio_companies || [@investor]
  @extracts_count_by_company = companies.to_h do |pc|
    [pc.id, PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: pc.id).count]
  end
  click_on "Generate Extracts Only"
  sleep 5
end

# Asserts a NEW extract was created for every selected company, with data present or absent.
Then('an extract should be generated for each selected company with data {string}') do |presence|
  companies = @portfolio_companies || [@investor]
  companies.each do |pc|
    scope = PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: pc.id)
    expect(scope.count).to be > @extracts_count_by_company[pc.id]
    extract = scope.order(created_at: :desc).first
    if presence == "present"
      expect(extract.data).to be_present
    else
      expect(extract.data).to be_blank
    end
  end
end

# Asserts that companies which already had an extract were skipped (only_missing_extracts) — i.e.
# their extract count is unchanged — while companies without one got a new extract.
Then('a new extract should only be generated for companies without one') do
  companies = @portfolio_companies || [@investor]
  companies.each do |pc|
    scope = PortfolioReportExtract.where(portfolio_report_id: @portfolio_report.id, portfolio_company_id: pc.id)
    if @extracts_count_by_company[pc.id].positive?
      expect(scope.count).to eq(@extracts_count_by_company[pc.id])
    else
      expect(scope.count).to be > @extracts_count_by_company[pc.id]
    end
  end
end

# When several companies are generated in one full-report run, their individual .docx files are
# combined into a single merged document under "/Portfolio Reports/Generated Portfolio Reports".
Then('a single merged report document should be generated') do
  merged = Document.where("name LIKE ?", "%companies%").order(created_at: :desc).first
  expect(merged).to be_present
  expect(merged.folder.name).to eq("Generated Portfolio Reports")
  expect(merged.folder.parent.name).to eq("Portfolio Reports")
end

# Each company still gets its own individual report document (the merge is additive, not a
# replacement). Individual docs are named "<template> <company name> <start> to <end>".
Then('each selected company should also have its own report document') do
  companies = @portfolio_companies || [@investor]
  companies.each do |pc|
    expect(
      Document.where("name LIKE ?", "%#{@template.name} #{pc.investor_name}%")
    ).to exist, "expected an individual report document for #{pc.investor_name}"
  end
end
