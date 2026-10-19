# frozen_string_literal: true

# Steps for features/api/kpi_reports_api.feature — a KPI report created over the JSON API with the
# workbook as a multipart file (gap G30, .claude/skills/client-onboarding/api-gaps.md).

require "caxlsx"

# The shared "I have an API token" step also remembers fund ids; a KPI scenario has no fund
Given("I have an API token for KPI reports") do
  api_token_for!("me")
end

# Posts a new Month KPI report with the table as its KPIs workbook, the way an API client does:
# multipart form data, bearer token, JSON answer. kpi_test_cell (kpi_upload_validation_steps.rb)
# types the cells as Excel would.
When("I create a KPI report for {string} as of {string} over the API with the workbook:") do |portco_name, as_of, table|
  portco = Investor.find_by!(investor_name: portco_name)
  tmp = Tempfile.new(["api_kpis", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "MIS") do |ws|
      table.raw.each do |row|
        cells = row.map { |c| kpi_test_cell(c) }
        ws.add_row(cells, types: cells.map { |c| c.is_a?(String) ? :string : nil })
      end
    end
    p.serialize(tmp.path)
  end
  @api_kpi_workbook_tmp = tmp

  client = api_client("me")
  @last_api_client = client
  # Multipart, not JSON: Rack::Test sets the boundary when no Content-Type is forced
  client.header "Content-Type", nil
  client.header "Accept", "application/json"
  client.header "Authorization", "Bearer #{client.access_token}"
  file = Rack::Test::UploadedFile.new(tmp.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                      original_filename: "kpis.xlsx")
  client.post "/kpi_reports.json", {
    kpi_report: { portfolio_company_id: portco.id, entity_id: @entity.id, as_of: as_of, period: "Month",
                  tag_list: "Actual", documents_attributes: { "0" => { name: "KPIs", file: file } } }
  }
end

Then("the KPI report for {string} as of {string} has a KPIs document") do |portco_name, as_of|
  report = KpiReport.find_by!(portfolio_company: Investor.find_by!(investor_name: portco_name), as_of: Date.parse(as_of))
  expect(report.documents.where(name: "KPIs")).to exist
end

Then("no KPI report exists for {string} as of {string}") do |portco_name, as_of|
  expect(KpiReport.where(portfolio_company: Investor.find_by!(investor_name: portco_name), as_of: Date.parse(as_of))).not_to exist
end

Given("I remember the {string} KPI report for {string} as of {string} as {string}") do |period, portco_name, as_of, key|
  report = KpiReport.find_by!(portfolio_company: Investor.find_by!(investor_name: portco_name), as_of: Date.parse(as_of), period: period)
  api_ids[key.to_sym] = report.id
end

Then("the API list has a row where {string} is {string}") do |field, value|
  expect(Array(last_api_json).map { |row| row[field].to_s }).to include(value)
end

Given("I remember the portfolio company {string} as {string}") do |portco_name, key|
  api_ids[key.to_sym] = Investor.find_by!(investor_name: portco_name).id
end

Then("the API list has no row where {string} is {string}") do |field, value|
  expect(Array(last_api_json).map { |row| row[field].to_s }).not_to include(value)
end
