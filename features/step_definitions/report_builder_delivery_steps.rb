# frozen_string_literal: true

# Report Builder delivery — export progress, recent exports, the schedule,
# the report page's filters and headline totals, on the Acme fixture from
# report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-delivery/business-rules.md

# H1, H2, X1 — an export that takes a moment, so "Preparing…" can be seen
# before the job (inline in tests) replaces the button; and one that fails
module ReportBuilderSlowExport
  def perform(*args, **kwargs)
    sleep ReportBuilderSlowExport.delay if ReportBuilderSlowExport.delay
    super
  end

  class << self
    attr_accessor :delay
  end
end
ReportBuilderExportJob.prepend(ReportBuilderSlowExport)

module ReportBuilderFailingExport
  def generate
    raise ReportBuilderFailingExport.message if ReportBuilderFailingExport.message

    super
  end

  class << self
    attr_accessor :message
  end
end
ReportBuilderXlsxExporter.prepend(ReportBuilderFailingExport)

After("@report_builder") do
  ReportBuilderSlowExport.delay = nil
  ReportBuilderFailingExport.message = nil
end

module ReportBuilderDeliveryWorld
  def delivery_report_page_path
    "/report_builder/#{@report.id}/view"
  end

  # The report page over HTTP, as a browser asks for it
  def open_delivery_report_page(params = {})
    rb_session.get delivery_report_page_path, params: params, headers: { "Accept" => "text/html" }
    @last_rb_response = rb_session.response
    follow_rb_redirect
  end

  # The export job, run as the Export button would run it
  def export_report(report, user)
    ReportBuilderExportJob.perform_now(report.id, user.id)
    Document.where(owner: report, owner_tag: "Generated").order(:id).last
  end

  def export_button
    find(".rb-export")
  end
end

World(ReportBuilderDeliveryWorld)

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

# "LPs" with Committed and Called totals and Category is LP (shared setup)
Given("the Acme delivery report {string}") do |name|
  @report = build_lps_report
  @report.update!(name: name)
  { "capital_commitments.committed_amount" => "Committed", "capital_commitments.call_amount" => "Called" }.each do |key, label|
    add_report_column(@report, key).update!(label: label, name: label)
  end
  tmpl = @report.reload.template.deep_stringify_keys
  @report.update!(template: tmpl.merge(
    "root_filters" => { "category_eq" => "LP" },
    "aggregates" => { "capital_commitments.committed_amount" => "sum", "capital_commitments.call_amount" => "sum" }
  ))
end

Given("exports take a moment") do
  ReportBuilderSlowExport.delay = 2
end

Given("exports of the report fail with {string}") do |message|
  ReportBuilderFailingExport.message = message
end

Given("Meera is on the report page") do
  log_in(acme[:meera])
  visit delivery_report_page_path
  wait_for_page_to_settle
end

Given("the report has been exported {int} times, a minute apart from {string}") do |count, start|
  first = Time.zone.parse(start)
  count.times do |i|
    export_report(@report, acme[:meera]).update_columns(created_at: first + i.minutes)
  end
end

Given("another Acme report {string} has been exported") do |name|
  other = build_report(entity: @entity, user: @user, root_model: "Fund", columns: [{ key: "name" }])
  other.update!(name: name)
  expect(export_report(other, acme[:meera])).to be_present
end

# ─────────────────────────────────────────────────────────────────────────────
# Export button (H1, H2, X1)
# ─────────────────────────────────────────────────────────────────────────────

When("I click Export XLSX") do
  within(".rb-export") { click_on "Export XLSX" }
end

Then("the export button reads {string} and is disabled") do |text|
  expect(page).to have_css(".rb-export a.disabled[aria-disabled='true']", text: text, wait: 5)
end

Then("the export button offers Download and Export again") do
  expect(page).to have_css(".rb-export[data-state='ready'] a", text: "Download", wait: 20)
  expect(export_button).to have_link("Export again")
  # Download opens the document the export just saved
  document = Document.where(owner: @report, owner_tag: "Generated").order(:id).last
  expect(export_button).to have_link("Download", href: "/documents/#{document.id}")
end

Then("the export button reads {string} again") do |text|
  expect(page).to have_css(".rb-export[data-state='idle'] a:not(.disabled)", text: text, wait: 20)
  expect(page).to have_no_css(".rb-export a", text: "Preparing…")
end

Then("I see the alert {string}") do |text|
  expect(page).to have_css("#user_alert", text: text, wait: 20)
end

# ─────────────────────────────────────────────────────────────────────────────
# Recent exports (H1, H3, E1, E2)
# ─────────────────────────────────────────────────────────────────────────────

When("I open the report builder report page") do
  open_delivery_report_page
end

# The Recent exports rows of the report page fetched over HTTP
def recent_export_rows
  page_doc.css(".rb-recent-export").map { |li| li.text.gsub(/[[:space:]]+/, " ").strip }
end

Then("the first recent export reads {string}") do |text|
  expect(page).to have_css(".rb-recent-export", text: text, wait: 20)
  expect(first(".rb-recent-export").text).to include(text)
end

Then("Recent exports lists {int} files") do |count|
  expect(recent_export_rows.size).to eq(count)
end

Then("the recent exports read {string} at {string}") do |text, times|
  rows = recent_export_rows
  times.split(",").map(&:strip).each_with_index do |time, i|
    expect(rows[i]).to include(text), "row #{i + 1}: #{rows[i]}"
    expect(rows[i]).to include(time), "row #{i + 1}: #{rows[i]}"
  end
end

Then("the report page reads {string}") do |text|
  expect(rb_page_text).to include(text)
end
