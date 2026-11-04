# frozen_string_literal: true

# Security review 2026-10, C3 (AI Portfolio Reports: tenant isolation, stored XSS, the pandoc call) and
# H3 (the support-agent chat window's target record).
# features/security/ai_portfolio_reports_isolation.feature, features/security/support_agent_chat_target.feature
# Worked examples: docs/security/security_review_2026_10.md (## C3 - AI Portfolio Reports, ## H3 - Support-agent chat target)
#
# @user / @entity come from the shared login steps ("Artha" in C3, Priya at "Golden Angels" in H3);
# "a portfolio company {string} exists" and "an AI portfolio report exists for {string}" (ai_portfolio_reports_steps.rb)
# give @portfolio_company and @report. Requests are sent as the screens' fetch / form calls send them,
# through the rack-test browser.

module SecurityC3H3Helpers
  EVALUATION_FOLDER = "Company Evaluation Agent"

  # C3-H - what a section legitimately holds: a chart placeholder, a web-source link, a table, inline style.
  RICH_SECTION_HTML = <<~HTML
    <h3 style="color: #1e40af;">Market</h3>
    <p style="margin-bottom: 1rem;">Source: <a href="https://news.example.com/robotics" target="_blank">Robotics Weekly</a></p>
    <table><tr><th>Year</th><th>Revenue</th></tr><tr><td colspan="1">2025</td><td>12</td></tr></table>
    <div class="ai-chart-container" data-chart-id="77" style="padding: 20px;">
      <div class="chart-placeholder" data-chart-config='{"labels":["2024","2025"],"datasets":[{"label":"Revenue","data":[8,12]}]}' data-chart-type="bar" style="background: white;"></div>
    </div>
  HTML

  # The last response of the rack-test browser
  def c3_send(verb, path, params = {}, headers = {})
    browser = page.driver.browser
    browser.public_send(verb, path, params, headers)
    @c3_response = browser.last_response
  end

  # Refused = WithAuthentication#deny_access: 403 (Turbo-Frame / API) or a redirect to the home page
  def c3_refused?(response)
    response.status == 403 || (response.redirect? && URI(response.location).path == "/")
  end

  def c3_section(report, section_type)
    report.ai_report_sections.find_by!(section_type:)
  end

  # Everything about a report the C3 refusals must leave untouched
  def c3_report_snapshot(report)
    report = AiPortfolioReport.find_by(id: report.id)
    return nil unless report

    { status: report.status, collated: report.collated_report_html,
      sections: report.ai_report_sections.order(:id).pluck(:id, :content_html, :content_html_with_web, :reviewed) }
  end

  # The folder and document rows of a tenant - C3-4, C3-5 must not add any
  def c3_tenant_counts(entity)
    { folders: Folder.where(entity_id: entity.id).count, documents: Document.where(entity_id: entity.id).count }
  end

  def c3_tenants
    @c3_tenants ||= {}
  end

  def c3_html(body, css)
    Nokogiri::HTML5(body).at_css(css)
  end

  # Elements and attributes a stored-XSS payload needs
  def c3_expect_no_active_content(node)
    expect(node.css("img, script, iframe, object, style")).to be_empty
    handlers = node.css("*").flat_map(&:attribute_nodes).select { |attr| attr.name.start_with?("on") }
    expect(handlers).to be_empty
  end

  # C3-H - the chart placeholder, the web link, the table and the inline style all survived
  def c3_expect_rich_content(node)
    expect(node.at_css(".chart-placeholder[data-chart-config][data-chart-type='bar']")).to be_present
    expect(node.at_css("[data-chart-id='77']")).to be_present
    expect(node.at_css("a[href='https://news.example.com/robotics']")).to be_present
    expect(node.at_css("table td[colspan]")).to be_present
    expect(node.at_css("h3[style*='color']")).to be_present
  end

  # A window request as the chat kit sends it (H3)
  def h3_window(verb, chattable_type, chattable_id, agent: @agent, message: nil)
    params = { "chattable_type" => chattable_type, "chattable_id" => chattable_id }
    params["message"] = message if message
    headers = verb == :get ? { "HTTP_TURBO_FRAME" => "agent-chat-#{agent.id}" } : { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }
    c3_send(verb, support_agent_chats_path(agent), params, headers)
    @window_status = @c3_response.status
    @stream = Nokogiri::HTML5.fragment(@c3_response.body)
  end
end
World(SecurityC3H3Helpers)

# ---- Shared set-up -------------------------------------------------------------------------------

Given('another firm {string} has a portfolio company {string} with an AI portfolio report') do |firm, company|
  @c3_zeta = FactoryBot.create(:entity, name: firm, entity_type: "Investment Fund")
  @c3_zeta_user = FactoryBot.create(:user, entity: @c3_zeta)
  @c3_zeta_company = FactoryBot.create(:investor, name: company, category: "Portfolio Company", entity: @c3_zeta,
                                                  investor_entity: FactoryBot.create(:entity, entity_type: "Company"))
  @c3_zeta_report = FactoryBot.create(:ai_portfolio_report, portfolio_company: @c3_zeta_company, analyst: @c3_zeta_user)
  # Content the refusals must leave as it is
  @c3_zeta_report.update!(collated_report_html: "<p>Zeta collated report</p>")
  c3_section(@c3_zeta_report, "Company Overview").update!(content_html: "<p>Zeta overview</p>")
  c3_tenants[firm] = @c3_zeta
  @c3_zeta_snapshot = c3_report_snapshot(@c3_zeta_report)
  @c3_zeta_counts = c3_tenant_counts(@c3_zeta)
end

Given("Zeta's report reads an evaluation folder holding {string}") do |document_name|
  ActiveRecord::Base.connected_to(role: :writing) do
    @c3_zeta_company.setup_document_folder unless @c3_zeta_company.document_folder
    @c3_zeta_company.reload
    folder = @c3_zeta_company.document_folder.children.find_or_create_by(name: SecurityC3H3Helpers::EVALUATION_FOLDER, entity_id: @c3_zeta.id)
    FactoryBot.create(:document, name: document_name, folder:, entity: @c3_zeta, user: @c3_zeta_user)
    @c3_zeta_report.update!(folder:)
  end
end

Given('{string} has an investment criteria template {string}') do |firm, name|
  @c3_templates ||= {}
  @c3_templates[name] = FactoryBot.create(:investment_criteria_template, name:, entity: c3_tenants.fetch(firm),
                                                                         created_by_user: @c3_zeta_user)
end

Given('report generation is stubbed') do
  # GenerateSectionContentJob runs inline under Cucumber and calls the LLM per section
  allow(GenerateSectionContentJob).to receive(:perform_later)
end

# ---- C3 requests ---------------------------------------------------------------------------------

When("I open Zeta's AI portfolio report pages") do
  report = @c3_zeta_report
  @c3_responses = [ai_portfolio_report_path(report), edit_ai_portfolio_report_path(report),
                   collated_report_ai_portfolio_report_path(report), export_pdf_ai_portfolio_report_path(report),
                   export_docx_ai_portfolio_report_path(report)].map { |path| c3_send(:get, path) }
end

When("I save Zeta's collated report as {string}") do |html|
  c3_send(:patch, save_collated_report_ai_portfolio_report_path(@c3_zeta_report), { content: html })
end

When("I delete Zeta's AI portfolio report") do
  c3_send(:delete, ai_portfolio_report_path(@c3_zeta_report))
end

When('I open the evaluation documents of {string}') do |company|
  c3_send(:get, evaluation_folder_documents_ai_portfolio_reports_path(portfolio_company_id: Investor.find_by!(name: company).id))
end

When('I upload an evaluation document {string} for {string}') do |name, company|
  cached = { id: "c3_#{SecureRandom.hex(6)}", storage: "cache", metadata: { filename: name, size: 1024, mime_type: "application/pdf" } }.to_json
  c3_send(:post, upload_evaluation_documents_ai_portfolio_reports_path,
          { portfolio_company_id: Investor.find_by!(name: company).id, documents: [{ name:, file: cached }] })
end

When("I save the {string} section of Zeta's report as {string}") do |section_type, html|
  section = c3_section(@c3_zeta_report, section_type)
  c3_send(:patch, ai_portfolio_report_ai_report_section_path(@c3_zeta_report, section), { ai_report_section: { content: html } })
end

When("I add {string} to the {string} section of Zeta's report") do |html, section_type|
  section = c3_section(@c3_zeta_report, section_type)
  c3_send(:post, add_content_ai_portfolio_report_ai_report_section_path(@c3_zeta_report, section), { content: html })
end

When('I save the {string} section of my report as:') do |section_type, html|
  section = c3_section(@report, section_type)
  # The doc string as the plain String the editor posts
  c3_send(:patch, ai_portfolio_report_ai_report_section_path(@report, section), { ai_report_section: { content: html.to_s } })
end

When('I save the {string} section of my report with a chart, a web link, a table and inline style') do |section_type|
  section = c3_section(@report, section_type)
  c3_send(:patch, ai_portfolio_report_ai_report_section_path(@report, section),
          { ai_report_section: { content: SecurityC3H3Helpers::RICH_SECTION_HTML } })
end

When('I add {string} to the {string} section of my report') do |html, section_type|
  section = c3_section(@report, section_type)
  c3_send(:post, add_content_ai_portfolio_report_ai_report_section_path(@report, section), { content: html })
end

Given('the {string} section of my report was stored before sanitizing as:') do |section_type, html|
  # update_columns skips before_save: a row written before the fix, which the view sink must still clean
  c3_section(@report, section_type).update_columns(content_html: html.to_s, reviewed: true)
end

Given("my report's collated HTML was stored before sanitizing with a local-file image") do
  # update_column skips before_save: a row written before the fix, which the DOCX view must still clean
  @report.update_column(:collated_report_html, '<p>Collated summary</p><img src="file:///etc/passwd"><script>alert(1)</script>')
end

When('I open the {string} section of my report') do |section_type|
  c3_send(:get, ai_portfolio_report_path(@report, section_id: c3_section(@report, section_type).id))
end

When('I create an AI portfolio report for {string}') do |company|
  c3_send(:post, ai_portfolio_reports_path,
          { ai_portfolio_report: { portfolio_company_id: Investor.find_by!(name: company).id, report_date: Time.zone.today.iso8601 },
            template_action: "skip" })
end

When('I create an AI portfolio report for {string} using the template {string}') do |company, template|
  c3_send(:post, ai_portfolio_reports_path,
          { ai_portfolio_report: { portfolio_company_id: Investor.find_by!(name: company).id, report_date: Time.zone.today.iso8601 },
            template_action: "use_existing", investment_criteria_template_id: @c3_templates.fetch(template).id })
end

Given('pandoc is recorded') do
  # pandoc is not installed on every machine: record the call and write a stand-in DOCX instead
  @c3_pandoc_calls = []
  allow(Open3).to receive(:capture3).and_wrap_original do |original, *args, **kwargs|
    next original.call(*args, **kwargs) unless args.first == "pandoc"

    @c3_pandoc_calls << { args:, input: File.read(args[1]) }
    File.binwrite(args[3], "PK stand-in docx")
    ["", "", double("pandoc status", success?: true, exitstatus: 0)]
  end
end

Given('PDF rendering is recorded') do
  # Record the HTML wkhtmltopdf would get, and return a stand-in PDF
  allow_any_instance_of(WickedPdf).to receive(:pdf_from_string) do |_pdf, html, *_rest|
    @c3_pdf_html = html
    "%PDF-1.4 stand-in"
  end
end

When('I export my report as DOCX') do
  c3_send(:get, export_docx_ai_portfolio_report_path(@report))
end

When('I export my report as PDF') do
  c3_send(:get, export_pdf_ai_portfolio_report_path(@report))
end

# ---- C3 outcomes ---------------------------------------------------------------------------------

Then('I am refused') do
  expect(c3_refused?(@c3_response)).to be(true), "expected a refusal, got #{@c3_response.status} #{@c3_response.location}"
end

Then('each of them is refused') do
  @c3_responses.each do |response|
    expect(c3_refused?(response)).to be(true), "expected a refusal, got #{response.status} #{response.location}"
  end
end

Then('the request succeeds') do
  ok = @c3_response.successful? || (@c3_response.redirect? && URI(@c3_response.location).path != "/")
  expect(ok).to be(true), "expected success, got #{@c3_response.status} #{@c3_response.location}"
end

Then("Zeta's report is unchanged") do
  expect(c3_report_snapshot(@c3_zeta_report)).to eq(@c3_zeta_snapshot)
end

Then('nothing was created in {string}') do |firm|
  expect(c3_tenant_counts(c3_tenants.fetch(firm))).to eq(@c3_zeta_counts)
end

When('I visit the AI portfolio reports list') do
  visit ai_portfolio_reports_path
end

Then('the list shows the report for {string}') do |company|
  expect(page).to have_css("table tbody td", text: company)
end

Then('the list does not show the report for {string}') do |company|
  expect(page).to have_no_css("table tbody td", text: company)
end

Then('the {string} section of my report is stored without img or script and keeps {string}') do |section_type, text|
  html = c3_section(@report, section_type).content_html
  fragment = Nokogiri::HTML5.fragment(html)
  c3_expect_no_active_content(fragment)
  expect(fragment.text).to include(text)
  # Script source is dropped with the script, not left behind as text
  expect(fragment.text).not_to include("alert")
end

Then('the returned content has no img or script and keeps {string}') do |text|
  fragment = Nokogiri::HTML5.fragment(JSON.parse(@c3_response.body).fetch("content"))
  c3_expect_no_active_content(fragment)
  expect(fragment.text).to include(text)
end

Then('the section editor shows {string} without img, script or event handlers') do |text|
  editor = c3_html(@c3_response.body, "#report-content")
  expect(editor).to be_present
  c3_expect_no_active_content(editor)
  expect(editor.text).to include(text)
end

Then('the export succeeds as a Word document') do
  expect(@c3_response.status).to eq(200)
  expect(@c3_response.content_type).to include("wordprocessingml")
end

Then('pandoc was called with an argument list and its input has no img') do
  expect(@c3_pandoc_calls.size).to eq(1)
  call = @c3_pandoc_calls.first
  # An argv array - program, input, -o, output - never one shell string
  expect(call[:args].size).to eq(4)
  expect(call[:args].values_at(0, 2)).to eq(["pandoc", "-o"])
  input = Nokogiri::HTML5(call[:input])
  c3_expect_no_active_content(input.at_css("body"))
  expect(call[:input]).not_to include("file:///etc/passwd")
  expect(input.text).to include("Collated summary")
end

Then("pandoc's input keeps the web link") do
  expect(Nokogiri::HTML5(@c3_pandoc_calls.last[:input]).at_css("a[href='https://news.example.com/robotics']")).to be_present
end

Then('the PDF export succeeds and keeps the web link and the chart box') do
  expect(@c3_response.status).to eq(200)
  expect(@c3_response.content_type).to include("pdf")
  html = Nokogiri::HTML5(@c3_pdf_html)
  expect(html.at_css("a[href='https://news.example.com/robotics']")).to be_present
  # export_pdf turns each chart placeholder into a "Chart visualization" box
  expect(html.text).to include("Chart visualization")
end

Then('no AI portfolio report was created for {string}') do |company|
  expect(AiPortfolioReport.where(portfolio_company: Investor.find_by!(name: company))).to be_none
end

Then('no evaluation folder was created for {string}') do |company|
  root = Investor.find_by!(name: company).document_folder
  expect(root.nil? || root.children.where(name: SecurityC3H3Helpers::EVALUATION_FOLDER).none?).to be(true)
end

Then('an AI portfolio report is created for {string} reading its evaluation folder') do |company|
  pc = Investor.find_by!(name: company)
  @report = AiPortfolioReport.find_by!(portfolio_company: pc)
  expect(URI(@c3_response.location).path).to eq(ai_portfolio_report_path(@report))
  expect(@report.analyst).to eq(@user)
  expect(@report.folder.name).to eq(SecurityC3H3Helpers::EVALUATION_FOLDER)
  expect(@report.folder.entity_id).to eq(@entity.id)
  expect(@report.folder.documents.pluck(:name)).to include("pitch_deck.pdf")
end

Then('the {string} section of my report keeps the chart, the web link, the table and the inline style') do |section_type|
  c3_expect_rich_content(Nokogiri::HTML5.fragment(c3_section(@report, section_type).content_html))
end

Then('the section editor shows the chart and the web link') do
  editor = c3_html(@c3_response.body, "#report-content")
  c3_expect_rich_content(editor)
end

Then('the portfolio company list offers {string}') do |company|
  expect(all("#ai_portfolio_report_portfolio_company_id option").map(&:text)).to include(company)
end

Then('the portfolio company list does not offer {string}') do |company|
  expect(all("#ai_portfolio_report_portfolio_company_id option").map(&:text)).not_to include(company)
end

# ---- H3 ------------------------------------------------------------------------------------------

Given('the chat agent must not be called') do
  # Neither the model nor the report's documents may be reached for a refused target
  expect(GenericChatAgent).not_to receive(:call)
  expect(FolderDocumentExtractor).not_to receive(:extract)
end

When("Priya opens the window about Zeta's report") do
  h3_window(:get, "AiPortfolioReport", @c3_zeta_report.id)
end

When("Priya asks the window {string} about Zeta's report") do |question|
  h3_window(:post, "AiPortfolioReport", @c3_zeta_report.id, message: question)
end

When('Priya asks the window {string} about her report') do |question|
  h3_window(:post, "AiPortfolioReport", @report.id, message: question)
end

When('Priya opens the window with target type {string}') do |chattable_type|
  # Any id: the type alone must never be resolved to a constant outside the models
  h3_window(:get, chattable_type, @agent.id)
end

When('Kavya opens an LP chat about the other investor') do
  # Still signed in as Kavya (from "Kavya opens her LP chat"); the other investor's user is that chat's record
  h3_window(:get, "User", @other_session.chattable_id, agent: @lp_agent)
end

Then('the window is refused') do
  expect(c3_refused?(@c3_response)).to be(true), "expected a refusal, got #{@c3_response.status} #{@c3_response.location}"
  expect(@c3_response.body).not_to include("Zeta Labs")
end

Then('the window opens about the agent') do
  expect(@window_status).to eq(200)
  composer = @stream.at_css("##{window_frame_id}-composer")
  expect(composer.at_css("input[name='chattable_type']")["value"]).to eq("SupportAgent")
  expect(composer.at_css("input[name='chattable_id']")["value"]).to eq(@agent.id.to_s)
end
