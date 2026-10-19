# frozen_string_literal: true

# Steps for features/startup/kpi_upload_validation.feature — server-side KPI workbook validation
# (KpiUploadValidate → KpiWorkbookReader#validate). Workbooks are generated in memory with caxlsx so
# each scenario states its cells explicitly; the reader sees exactly what Roo would read from Excel.

require "caxlsx"
require "base64"

# Restores CURRENT_SITE after any scenario that stubbed it via "the deployment is the ... site"
# below, so the geo-default fiscal-year test doesn't leak into later scenarios.
After('@kpi_validation') do
  if instance_variable_defined?(:@kpi_upload_original_current_site)
    if @kpi_upload_original_current_site.nil?
      ENV.delete("CURRENT_SITE")
    else
      ENV["CURRENT_SITE"] = @kpi_upload_original_current_site
    end
  end
end

# ── Setup ────────────────────────────────────────────────────────────────────

# Like the Quarter-only shell step in portco_kpi_workflow_steps.rb, but with an explicit period so
# requested-period scenarios can ask for a Month / Year.
Given('a KPI report shell exists for {string} as of {string} with status {string} and period {string}') do |portco_name, as_of, status, period|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report = KpiReport.create!(
    entity: @entity, portfolio_company: portco, user: @user,
    as_of: Date.parse(as_of), period: period, tag_list: 'Actual',
    enable_portco_upload: true, status: status
  )
end

Given('the KPI mapping {string} exists with data type {string}') do |name, data_type|
  @portfolio_company.investor_kpi_mappings.create!(
    entity_id: @portfolio_company.entity_id, reported_kpi_name: name, standard_kpi_name: name, data_type: data_type
  )
  @portfolio_company.reload
end

# Cells that look like plain numbers become numeric cells (as Excel would store them); everything
# else is text; blank is an empty cell.
def kpi_test_cell(text)
  return nil if text.nil? || text.strip.empty?
  # A leading apostrophe forces text, as in Excel ("'1.000" stays the string "1.000")
  return text[1..] if text.start_with?("'")
  # A literal \n is a line break inside the cell (a heading with a note on its second line)
  return text.gsub('\\n', "\n") if text.include?('\\n')
  return text.include?('.') ? text.to_f : text.to_i if text.strip.match?(/\A-?\d+(\.\d+)?\z/)

  text
end

# Table rows → sheet definition. Rebuilds @kpi_workbook_sheets so a scenario can define a second
# workbook mid-way ("Given a KPI workbook …" again replaces the previous one).
Given('a KPI workbook with sheet {string}:') do |sheet_name, table|
  @kpi_workbook_sheets = [{ name: sheet_name, rows: table.raw, hidden: false }]
end

Given('the workbook also has a hidden sheet {string}:') do |sheet_name, table|
  @kpi_workbook_sheets << { name: sheet_name, rows: table.raw, hidden: true }
end

# Writes @kpi_workbook_sheets to a temp .xlsx and returns the path.
def build_kpi_test_workbook
  tmp = Tempfile.new(["kpi_validation_test", ".xlsx"])
  Axlsx::Package.new do |p|
    @kpi_workbook_sheets.each do |sheet|
      p.workbook.add_worksheet(name: sheet[:name]) do |ws|
        ws.state = :hidden if sheet[:hidden]
        sheet[:rows].each do |row|
          cells = row.map { |c| kpi_test_cell(c) }
          # caxlsx auto-types numeric-looking strings as numbers; force text cells to stay text
          ws.add_row(cells, types: cells.map { |c| c.is_a?(String) ? :string : nil })
        end
      end
    end
    p.serialize(tmp.path)
  end
  @kpi_workbook_tmp = tmp
  tmp.path
end

Given('an approved KPI {string} of {float} exists for {string} as of {string} period {string}') do |name, value, portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  mapping = portco.investor_kpi_mappings.find_by!(reported_kpi_name: name)
  report = KpiReport.find_or_create_by!(entity: @entity, portfolio_company: portco, as_of: Date.parse(as_of), period: period, tag_list: 'Actual') do |r|
    r.user = @user
  end
  Kpi.create!(kpi_report: report, entity: @entity, portfolio_company: portco, name: mapping.standard_kpi_name,
              value: value, status: :approved, investor_kpi_mapping_id: mapping.id)
end

Given("the fund's financial year starts in January") do
  setting = @entity.entity_setting || @entity.create_entity_setting!
  setting.update!(month_offset_for_fy: 0)
end

# Simulates which deployment (India/US server) is handling this request, without an explicit
# month_offset_for_fy override — exercises EntitySetting.geo_default_month_offset_for_fy.
Given('the deployment is the {string} site with no fiscal-year override') do |current_site|
  @kpi_upload_original_current_site = ENV["CURRENT_SITE"]
  ENV["CURRENT_SITE"] = current_site
end

# ── Actions ──────────────────────────────────────────────────────────────────

When('the workbook is validated for the KPI report') do
  path = build_kpi_test_workbook
  upload = ActionDispatch::Http::UploadedFile.new(
    tempfile: File.open(path), filename: "test_kpis.xlsx",
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  )
  result = KpiUploadValidate.call(kpi_report: @kpi_report, user: @user, file: upload)
  @verdict = result[:verdict]
  expect(@verdict).to be_present, "KpiUploadValidate returned no verdict: #{result[:errors]}"
end

# Simulates a tampered Uppy payload pointing at a non-cache Shrine storage.
When('a workbook reference with storage {string} is validated for the KPI report') do |storage|
  result = KpiUploadValidate.call(kpi_report: @kpi_report, user: @user,
                                  file_data: { "id" => "somebody-elses-key.xlsx", "storage" => storage, "metadata" => { "filename" => "x.xlsx" } }.to_json)
  @verdict = result[:verdict]
end

# Attaches the workbook as the report's KPIs document and runs the real import job (persists the
# verdict, sends the legacy report email when warranted, drives the submit lifecycle).
When('the workbook is imported for the KPI report') do
  path = build_kpi_test_workbook
  @kpi_report.documents.where(name: "KPIs").destroy_all
  document = @kpi_report.documents.build(entity_id: @entity.id, name: "KPIs", user_id: @user.id, file: File.open(path), owner: @kpi_report)
  document.save!
  ImportKpiWorkbookJob.perform_now(@kpi_report.id, @user.id)
  @kpi_report.reload
end

# Goes through the real Uppy picker (→ /upload → hidden field → upload:complete with the cached-file
# JSON), so the server validates the cached object and Save Draft actually attaches the document.
When('I pick a KPI workbook file with a formatted revenue value for June 2026 in the file picker') do
  tmp = Tempfile.new(["kpi_formatted_pick", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "MIS") do |ws|
      ws.add_row ["KPI", "May 2026", "Jun 2026"]
      ws.add_row ["Revenue", "1,000", "₹ 12,50,000"]
    end
    p.serialize(tmp.path)
  end
  @picked_workbook_tmp = tmp
  advance_kpi_wizard_to(:upload) # the file input lives on the wizard's "Upload & Validate KPIs" step
  attach_file('files[]', File.absolute_path(tmp.path), make_visible: true)
end

# Dispatches an upload:complete event with a workbook whose June revenue is text-formatted, so the
# panel's "How we read your file" table shows the interpreted value (1,250,000).
When('I upload a KPI XLSX with a formatted revenue value for June 2026') do
  tmp = Tempfile.new(["kpi_formatted", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "MIS") do |ws|
      ws.add_row ["KPI", "May 2026", "Jun 2026"]
      ws.add_row ["Revenue", "1,000", "₹ 12,50,000"]
    end
    p.serialize(tmp.path)
  end
  b64 = Base64.strict_encode64(File.binread(tmp.path))
  tmp.close!
  dispatch_kpi_upload(b64, "formatted_kpi.xlsx")
end

# ── Assertions on the verdict ────────────────────────────────────────────────

def verdict_issue_codes(severity)
  Array(@verdict[severity]).map { |i| i['code'].to_s }
end

Then('the validation has no errors') do
  expect(@verdict['ok']).to be(true), "expected no errors, got: #{Array(@verdict['errors']).pluck('message').inspect}"
end

Then('the validation has error {string}') do |code|
  expect(verdict_issue_codes('errors')).to include(code), "errors were: #{Array(@verdict['errors']).map { |e| "#{e['code']}: #{e['message']}" }.inspect}"
end

Then('the validation has warning {string}') do |code|
  expect(verdict_issue_codes('warnings')).to include(code), "warnings were: #{Array(@verdict['warnings']).map { |e| "#{e['code']}: #{e['message']}" }.inspect}"
end

Then('the validation error {string} mentions {string}') do |code, text|
  issue = Array(@verdict['errors']).find { |e| e['code'].to_s == code }
  expect(issue).to be_present
  expect(issue['message']).to include(text)
end

Then('the validation warning {string} mentions {string}') do |code, text|
  issue = Array(@verdict['warnings']).find { |e| e['code'].to_s == code }
  expect(issue).to be_present
  expect(issue['message']).to include(text)
end

def verdict_cell(ref)
  cell = Array(@verdict['cells']).find { |c| c['ref'] == ref }
  expect(cell).to be_present, "no validated cell #{ref}; cells: #{Array(@verdict['cells']).pluck('ref').inspect}"
  cell
end

Then('the cell {string} is stored as {string}') do |ref, expected|
  cell = verdict_cell(ref)
  expect(cell['status']).to eq('ok'), "cell #{ref} status #{cell['status']} (#{cell['code']})"
  expect(BigDecimal(cell['stored'])).to eq(BigDecimal(expected))
end

Then('the cell {string} has status {string}') do |ref, status|
  expect(verdict_cell(ref)['status']).to eq(status)
end

Then('the cell {string} is marked changed from {string} to {string}') do |ref, old_value, new_value|
  cell = verdict_cell(ref)
  expect(cell['changed']).to be(true)
  expect(BigDecimal(cell['old_value'])).to eq(BigDecimal(old_value))
  expect(BigDecimal(cell['stored'])).to eq(BigDecimal(new_value))
end

Then('there is no validated cell in sheet {string}') do |sheet|
  expect(Array(@verdict['cells']).none? { |c| c['sheet'] == sheet }).to be(true)
end

Then('the requested period is present with {string} KPIs filled') do |count|
  req = @verdict.dig('summary', 'requested_period')
  expect(req).to be_present
  expect(req['present']).to be(true)
  expect(req['kpis_filled']).to eq(count.to_i)
end

Then('no KPI rows were written') do
  expect(Kpi.unapproved.where(portfolio_company_id: @portfolio_company.id).count).to eq(0)
end

Then('the approved KPI {string} as of {string} still has value {float}') do |name, as_of, value|
  kpi = Kpi.approved.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { as_of: Date.parse(as_of) }).first
  expect(kpi).to be_present
  expect(kpi.value.to_f).to eq(value)
end

Then('an unapproved KPI {string} as of {string} exists with value {float}') do |name, as_of, value|
  kpi = Kpi.unapproved.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { as_of: Date.parse(as_of) }).first
  expect(kpi).to be_present, "no unapproved #{name} as of #{as_of}"
  expect(kpi.value.to_f).to eq(value)
end

# Checks the KpiReport's period type too (Month/Quarter/Half Year/Year/YTD) — used to confirm a
# header was bucketed under the right period type, not just the right date (e.g. a "Q1 FY 25"
# header that KpiDateUtils.detect_period_type mistakes for a Month would still parse to the
# correct date, so the date-only assertion above wouldn't catch that kind of mislabeling).
Then('an unapproved KPI {string} as of {string} period {string} exists with value {float}') do |name, as_of, period, value|
  kpi = Kpi.unapproved.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { as_of: Date.parse(as_of), period: period }).first
  expect(kpi).to be_present, "no unapproved #{name} as of #{as_of} with period #{period}"
  expect(kpi.value.to_f).to eq(value)
end

Then('the KPI report has a stored validation result with {string} errors') do |count|
  eventually do
    @kpi_report.reload
    expect(@kpi_report.validation_result).to be_present
    expect(Array(@kpi_report.validation_result['errors']).size).to eq(count.to_i)
  end
end

# ── Extended coverage (kpi_upload_validation_extended.feature) ───────────────

Given('the KPI mapping {string} exists with lower threshold {int} and upper threshold {int}') do |name, lower, upper|
  @portfolio_company.investor_kpi_mappings.create!(
    entity_id: @portfolio_company.entity_id, reported_kpi_name: name, standard_kpi_name: name,
    lower_threshold: lower, upper_threshold: upper
  )
  @portfolio_company.reload
end

# comparator_tag: pass "none" for a flat threshold (judges the value directly, no comparator KPI
# or approved Budget needed).
Given('the KPI mapping {string} exists with RAG comparator {string}, direction {string}, red threshold {float}, green threshold {float}') do |name, comparator_tag, direction, red, green|
  @portfolio_company.investor_kpi_mappings.create!(
    entity_id: @portfolio_company.entity_id, reported_kpi_name: name, standard_kpi_name: name,
    rag_comparator_tag: comparator_tag == 'none' ? nil : comparator_tag,
    rag_direction: direction,
    rag_red_threshold: red,
    rag_green_threshold: green
  )
  @portfolio_company.reload
end

Given('an approved {string} KPI {string} of {float} exists for {string} as of {string} period {string}') do |tag, name, value, portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  mapping = portco.investor_kpi_mappings.find_by!(reported_kpi_name: name)
  report = KpiReport.find_or_create_by!(entity: @entity, portfolio_company: portco, as_of: Date.parse(as_of), period: period, tag_list: tag) do |r|
    r.user = @user
  end
  Kpi.create!(kpi_report: report, entity: @entity, portfolio_company: portco, name: mapping.standard_kpi_name,
              value: value, status: :approved, investor_kpi_mapping_id: mapping.id)
end

# A second, visible sheet. An all-blank table produces a sheet with no cells (Roo last_row nil).
Given('the workbook also has a sheet {string}:') do |sheet_name, table|
  rows = table.raw.reject { |r| r.all? { |c| c.to_s.strip.empty? } }
  @kpi_workbook_sheets << { name: sheet_name, rows: rows, hidden: false }
end

Given('a fund-created KPI report exists for {string} as of {string} period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report = KpiReport.create!(entity: @entity, portfolio_company: portco, user: @user, as_of: Date.parse(as_of), period: period, tag_list: 'Actual')
end

Then('the validation has no warning {string}') do |code|
  expect(verdict_issue_codes('warnings')).not_to include(code)
end

# Runs a validate_upload POST from the browser with the given query string, recording the HTTP status.
def post_validate_upload_from_page(path, form_fields = {})
  page.execute_script(<<~JS)
    (async function () {
      const body = new FormData();
      #{form_fields.map { |k, v| "body.append(#{k.to_json}, #{v.to_s.to_json});" }.join("\n")}
      try {
        const r = await fetch(#{path.to_json}, {
          method: 'POST', headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '', 'Accept': 'text/vnd.turbo-stream.html' },
          body: body, credentials: 'same-origin', redirect: 'manual'
        });
        window.__vuStatus = r.status;
      } catch (e) { window.__vuStatus = -1; }
    })();
  JS
  eventually { expect(page.evaluate_script('typeof window.__vuStatus === "number"')).to be(true) }
  page.evaluate_script('window.__vuStatus')
end

When('I call validate_upload with an expired signed link') do
  verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
  expired = verifier.generate({ record_id: @kpi_report.id, email: @portco_user.email, model: 'KpiReport' }, expires_in: -1.second, purpose: :shared_access)
  @vu_status = post_validate_upload_from_page(validate_upload_kpi_report_path(@kpi_report, signed_id: expired))
end

When('I call the New-page validate_upload for {string}') do |portco_name|
  target = Investor.find_by!(investor_name: portco_name)
  # The New page is always opened with the fund's own portco pre-selected (as the app links to it)
  visit(new_kpi_report_path(kpi_report: { portfolio_company_id: @portfolio_company.id }))
  @vu_status = post_validate_upload_from_page(validate_upload_kpi_reports_path, 'kpi_report[portfolio_company_id]' => target.id)
end

Then('the validate_upload response status is {int}') do |status|
  expect(@vu_status).to eq(status)
end

Then('the validate_upload response status is not 200') do
  expect(@vu_status).not_to eq(200)
end

When('I reload the page') do
  visit(current_url)
end

Then('the KPI report has a stored validation result for its attached document') do
  eventually do
    report = KpiReport.find(@kpi_report.id)
    doc = report.documents.where(name: "KPIs").first
    expect(doc).to be_present
    expect(report.validation_result&.dig('document_id')).to eq(doc.id)
  end
end

Then('the KPIs upload field accepts only {string}') do |types|
  attr = page.find('#custom_file_kp_is', visible: :all)['data-single-upload-types-value']
  expect(JSON.parse(attr)).to eq(types.split(',').map(&:strip))
end

Then('the fund admin receives no email with subject containing {string}') do |text|
  mail = ActionMailer::Base.deliveries.find { |m| m.to.include?(@user.email) && m.subject.to_s.include?(text) }
  expect(mail).to be_nil, "unexpected email: #{mail&.subject}"
end

Given('the KPI report has that workbook attached') do
  path = build_kpi_test_workbook
  doc = @kpi_report.documents.build(entity_id: @entity.id, name: "KPIs", user_id: @user.id, file: File.open(path), owner: @kpi_report)
  doc.save!
end

Then('the submitted email to the fund admin mentions {string}') do |text|
  eventually do
    mail = ActionMailer::Base.deliveries.find { |m| m.to.include?(@user.email) && m.subject.to_s.downcase.include?('submitted') }
    expect(mail).to be_present
    body = mail.html_part&.body&.decoded || mail.body.decoded
    expect(body).to include(text)
  end
end

Then('the generated KPI template lists unit {string} for {string}') do |unit, name|
  result = KpiTemplateGenerate.call(kpi_report: @kpi_report)
  tmp = Tempfile.new(["kpi_template_units", ".xlsx"], binmode: true)
  tmp.write(result[:xlsx])
  tmp.flush
  wb = Roo::Spreadsheet.open(tmp.path)
  row = (2..wb.last_row).map { |i| wb.row(i) }.find { |r| r.first.to_s == name }
  expect(row).to be_present
  expect(row[1].to_s).to eq(unit)
end

When('a KPI report shell is created through the service for {string} as of {string} period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  result = KpiReportCreateShell.call(entity: @entity, portco: portco, as_of: Date.parse(as_of), period: period)
  expect(result.success?).to be(true), "shell creation failed: #{result[:errors]}"
  @created_shell = result[:model]
end

Then('the created shell has as_of {string}') do |as_of|
  expect(@created_shell.reload.as_of).to eq(Date.parse(as_of))
end

# Makes the job blow up mid-way (portfolio_company is nil → NoMethodError) to exercise the rescue path.
Given('the KPI report is detached from its portfolio company') do
  # portfolio_company_id is read-only (a KPI report never moves company), so the bad data is written directly
  KpiReport.where(id: @kpi_report.id).update_all(portfolio_company_id: nil)
  @kpi_report.reload
end

When('the KPI import job runs for the report and raises') do
  expect { ImportKpiWorkbookJob.perform_now(@kpi_report.id, @user.id) }.to raise_error(StandardError)
end

# ── Sample files (public/sample_uploads/kpi_portco_uploads) ─────────────────

SAMPLE_KPI_UPLOADS_DIR = Rails.public_path.join('sample_uploads/kpi_portco_uploads')

When('the sample KPI workbook {string} is validated for the KPI report') do |file|
  path = SAMPLE_KPI_UPLOADS_DIR.join(file)
  expect(File.exist?(path)).to be(true), "missing sample #{path}"
  upload = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(path), filename: file, type: "application/octet-stream")
  @verdict = KpiUploadValidate.call(kpi_report: @kpi_report, user: @user, file: upload)[:verdict]
end

Then('the validation outcome is {string}') do |outcome|
  expect(@verdict['ok']).to eq(outcome == 'ok'), "errors: #{Array(@verdict['errors']).pluck('code').inspect}"
end

# Every listed code must be present (as an error or a warning); history-based hints are not listed
# because the test DB has no approved history.
Then('the validation has these issue codes {string}') do |codes|
  present = verdict_issue_codes('errors') + verdict_issue_codes('warnings')
  codes.split(',').map(&:strip).reject(&:empty?).each do |code|
    expect(present).to include(code), "expected #{code}; got #{present.uniq.inspect}"
  end
end

Then('the cell {string} carries tag {string}') do |ref, tag|
  expect(verdict_cell(ref)['tag']).to eq(tag)
end

When('I pick the sample KPI workbook {string} in the file picker') do |file|
  advance_kpi_wizard_to(:upload) # the file input lives on the wizard's "Upload & Validate KPIs" step
  attach_file('files[]', SAMPLE_KPI_UPLOADS_DIR.join(file).to_s, make_visible: true)
end

# The Workbook check panel is replaced by turbo_stream after the server validates the upload;
# wait for the text to appear inside it (never elsewhere on the page).
Then('the workbook check panel shows {string}') do |text|
  within('#kpi_validation_panel') do
    expect(page).to have_content(text, wait: 20)
  end
end

Then('the workbook check panel does not show {string}') do |text|
  within('#kpi_validation_panel') do
    expect(page).not_to have_content(text)
  end
end

# kpi_validation_panel_controller.js gates the wizard's "final" buttons (Submit Report / Confirm)
# on every warning checkbox being ticked, not just on the error count — ticking "Acknowledge all"
# checks every individual warning to match (see toggleAll in that controller). Must run while the
# "Upload & Validate KPIs" step is still the visible wizard step, since that is where the panel
# (and its checkboxes) live; the wizard only ever hides steps via CSS, so the ticked state survives
# navigating to a later step afterwards.
When('I acknowledge all KPI warnings') do
  within('#kpi_validation_panel') do
    check('kpi_warnings_ack_all') if page.has_field?('kpi_warnings_ack_all', wait: 5)
  end
end

Given('the portfolio company has no KPI mappings') do
  @portfolio_company.investor_kpi_mappings.delete_all
  @portfolio_company.reload
end

Then('the validated cell for KPI {string} in {string} is stored as {string}') do |standard_kpi, period, expected|
  cell = Array(@verdict['cells']).find { |c| c['standard_kpi'] == standard_kpi && c['period'] == period }
  expect(cell).to be_present, "no cell for #{standard_kpi} / #{period}; have: #{Array(@verdict['cells']).map { |c| [c['standard_kpi'], c['period']] }.uniq.inspect}"
  expect(cell['status']).to eq('ok')
  expect(BigDecimal(cell['stored'])).to eq(BigDecimal(expected))
end

Then('there is no validated cell for KPI {string}') do |standard_kpi|
  expect(Array(@verdict['cells']).none? { |c| c['standard_kpi'] == standard_kpi }).to be(true)
end

When('I open the New KPI report page for {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(new_kpi_report_path(kpi_report: { portfolio_company_id: portco.id }))
end

# Bypasses the disabled Save button (what a tampered browser could do) — the server must refuse.
When('I force a save of the KPI report form') do
  page.execute_script("document.getElementById('kpi-report-form').requestSubmit();")
  sleep(1)
end

Then('no KPI report exists for {string} other than the shell') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  expect(KpiReport.where(portfolio_company: portco).count).to eq(1)
end

# ── Onboarding gaps G25–G27 (kpi_workbook_onboarding_gaps.feature) ──────────

# G27: a mapping read only from one sheet
Given('the KPI mapping {string} reported as {string} reads only sheet {string}') do |standard_name, reported_name, sheet|
  @portfolio_company.investor_kpi_mappings.create!(
    entity_id: @portfolio_company.entity_id, reported_kpi_name: reported_name, standard_kpi_name: standard_name, source_sheet: sheet
  )
  @portfolio_company.reload
end

Then('the cell {string} is read as a {string} ending {string}') do |ref, period_type, as_of|
  cell = verdict_cell(ref)
  expect(cell['period_type']).to eq(period_type)
  expect(cell['parsed_period']).to eq(as_of)
end

Then('the cell {string} is stored as {string} for KPI {string}') do |ref, expected, standard_name|
  cell = verdict_cell(ref)
  expect(cell['status']).to eq('ok'), "cell #{ref} status #{cell['status']} (#{cell['code']})"
  expect(cell['standard_kpi']).to eq(standard_name)
  expect(BigDecimal(cell['stored'])).to eq(BigDecimal(expected))
end

Then('there is no validated cell {string}') do |ref|
  expect(Array(@verdict['cells']).pluck('ref')).not_to include(ref)
end

# ── G29b, G33 (kpi_workbook_onboarding_gaps.feature) ─────────────────────────

Then('the imported KPI {string} as of {string} has a note mentioning {string}') do |name, as_of, text|
  kpi = Kpi.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { as_of: Date.parse(as_of) }).first
  expect(kpi).to be_present, "no KPI #{name} as of #{as_of}"
  expect(kpi.notes).to include(text)
end

# Runs the computation the way KpiCumulateJob does, keeping the errors it would email
When('the computed KPI {string} is computed') do |name|
  mapping = @portfolio_company.investor_kpi_mappings.find_by!(standard_kpi_name: name)
  kpi = Kpi.new(portfolio_company_id: @portfolio_company.id, entity_id: mapping.entity_id, name: name, investor_kpi_mapping: mapping)
  kpi.autofill
  @autofill_errors = kpi.autofill_errors
end

Then('the computation reports no errors') do
  expect(@autofill_errors).to be_empty, "errors: #{@autofill_errors.inspect}"
end

Then('the computation reports one error mentioning {string}') do |text|
  expect(@autofill_errors.size).to eq(1), "errors: #{@autofill_errors.inspect}"
  expect(@autofill_errors.first[:message]).to include(text)
end

Then('the KPI {string} as of {string} period {string} has value {float}') do |name, as_of, period, value|
  kpi = Kpi.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id,
                                     kpi_reports: { as_of: Date.parse(as_of), period: period }).first
  expect(kpi).to be_present, "no #{name} as of #{as_of} (#{period})"
  expect(kpi.value.to_f).to eq(value)
end
