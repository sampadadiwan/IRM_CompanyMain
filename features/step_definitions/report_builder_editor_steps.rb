# frozen_string_literal: true

# Report Builder with live preview — builder page steps over HTTP (no browser).
# Uses the Acme fixture from report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-live-builder/business-rules.md

# E19 — makes the preview's engine fail on demand; switched off after each scenario
module ReportBuilderFailingEngine
  def run(*, **)
    raise "Simulated engine failure" if ReportBuilderFailingEngine.enabled

    super
  end

  class << self
    attr_accessor :enabled
  end
end
ReportBuilderQueryEngine.prepend(ReportBuilderFailingEngine)

After("@report_builder") do
  ReportBuilderFailingEngine.enabled = false
end

module ReportBuilderEditorWorld
  # A request made the way the builder page makes it: from a form inside the
  # settings panel, so the answer is the three Turbo Streams (H2)
  def builder_request(verb, path, params = {})
    rb_session.public_send(verb, path, params: params,
                                       headers: { "Accept" => "text/vnd.turbo-stream.html, text/html",
                                                  "Turbo-Frame" => "report_builder_settings" })
    @last_rb_response = rb_session.response
  end

  def page_doc
    Nokogiri::HTML(@last_rb_response.body)
  end

  # The <template> content of one turbo-stream action, parsed
  def stream_target(target)
    stream = page_doc.css("turbo-stream").find { |s| s["target"] == target }
    expect(stream).not_to be_nil, "no stream for #{target}; got #{page_doc.css('turbo-stream').pluck('target').inspect}"
    Nokogiri::HTML(stream.at_css("template").inner_html)
  end
end

World(ReportBuilderEditorWorld)

Given("the preview engine fails") do
  ReportBuilderFailingEngine.enabled = true
end

When("I open the builder") do
  rb_session.get "/report_builder/#{@report.id}/edit"
  @last_rb_response = rb_session.response
end

When("I open the builder preview") do
  rb_session.get "/report_builder/#{@report.id}/preview", params: { builder: 1 }
  @last_rb_response = rb_session.response
end

Then("the builder page loads") do
  expect(@last_rb_response.status).to eq(200), "status #{@last_rb_response.status}: #{@last_rb_response.body[0, 300]}"
end

# H17 — every icon-only button or link on the builder has an accessible label
Then("every icon-only control on the builder has an accessible label") do
  container = page_doc.at_css(".report-builder-container")
  unlabelled = container.css("button, a").select do |el|
    el.text.gsub(/[[:space:]]/, "").empty? && el["aria-label"].to_s.strip.empty?
  end
  expect(unlabelled.map(&:to_html)).to be_empty
end

Then("the builder links to the Report Builder guide") do
  expect(page_doc.css("a").pluck("href")).to include("/user_guides/report_builder_user_guide")
end

Then("the builder has a command search button") do
  expect(page_doc.at_css("button[data-bs-target='#commandPaletteModal']")).not_to be_nil
end

Then("the preview shows the error {string}") do |text|
  alert = page_doc.at_css("turbo-frame#report_builder_preview .alert-danger")
  expect(alert).not_to be_nil, "no error card in the preview frame"
  expect(alert.text).to include(text)
end

Then("the preview says {string}") do |text|
  expect(page_doc.at_css("turbo-frame#report_builder_preview").text.gsub(/[[:space:]]+/, " ")).to include(text)
end

# ─────────────────────────────────────────────────────────────────────────────
# Column picker, bulk add and header menus
# ─────────────────────────────────────────────────────────────────────────────

def report_gvp(key)
  gvp = @report.reload.grid_view_preferences.find { |g| g.key.split(";").first.strip == key }
  expect(gvp).not_to be_nil, "no column #{key}"
  gvp
end

When("I add the columns {string} from the builder") do |keys|
  builder_request(:post, "/report_builder/#{@report.id}/columns", keys: keys.split(",").map(&:strip))
end

When("I set the total for {string} to {string} from the builder") do |key, agg|
  builder_request(:patch, "/report_builder/#{@report.id}/aggregate", key: key, aggregate: agg)
end

When("I move {string} {string} from the builder") do |key, direction|
  builder_request(:patch, "/report_builder/#{@report.id}/columns/#{report_gvp(key).id}/move", direction: direction)
end

When("I rename {string} to {string} from the builder") do |key, label|
  builder_request(:patch, "/report_builder/#{@report.id}/columns/#{report_gvp(key).id}", label: label)
end

Then("the builder answer replaces the settings, the preview and the health") do
  expect(@last_rb_response.media_type).to eq("text/vnd.turbo-stream.html")
  targets = page_doc.css("turbo-stream").pluck("target")
  expect(targets).to include("report_builder_settings", "report_builder_preview", "report_builder_health", "report_builder_toasts")
end

Then("the builder answer is refused with status {int}") do |status|
  expect(@last_rb_response.status).to eq(status)
end

Then("the builder message says {string}") do |text|
  expect(stream_target("report_builder_toasts").text.gsub(/[[:space:]]+/, " ")).to include(text)
end

Then("the settings show the total {string} for {string}") do |agg, key|
  select = stream_target("report_builder_settings").at_css("select[data-key='#{key}']")
  expect(select.at_css("option[selected]")&.[]("value")).to eq(agg)
end

Then("the streamed preview shows {string} under {string} in the row with {string}") do |value, header, row_text|
  table   = stream_target("report_builder_preview").at_css("table")
  headers = table.css("thead th").map { |th| th.at_css("button")&.text.to_s.strip.presence || th.text.strip }
  idx     = headers.index(header)
  expect(idx).not_to be_nil, "no column #{header}: #{headers.inspect}"
  row = table.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.gsub(/[[:space:]]+/, " ").strip } }.find { |r| r.include?(row_text) }
  expect(row[idx]).to eq(value)
end

Then("the report has the columns {string}") do |keys|
  present = @report.reload.grid_view_preferences.map { |g| g.key.split(";").first.strip }
  keys.split(",").map(&:strip).each { |k| expect(present).to include(k) }
end

Then("the report has {string} only once") do |key|
  expect(@report.reload.grid_view_preferences.count { |g| g.key.split(";").first.strip == key }).to eq(1)
end

Then("the column {string} is labelled {string}") do |key, label|
  expect(report_gvp(key).label).to eq(label)
end

# H3 — sources, kinds, and no internal fields
Then("the column picker has the sources {string}") do |titles|
  summaries = page_doc.css(".rb-column-groups details summary").map { |s| s.text.strip }
  expect(summaries).to eq(titles.split(",").map(&:strip))
end

Then("the column picker groups columns as {string}") do |kinds|
  labels = page_doc.css(".rb-column-groups details").first.css(".text-muted.small").map { |d| d.text.strip }
  expect(labels).to eq(kinds.split(",").map(&:strip))
end

Then("no column in the picker is an internal id or cents field") do
  values = page_doc.css(".rb-column-groups input[name='keys[]']").map { |i| i["value"].split(";").first.strip }
  expect(values).not_to be_empty
  expect(values.select { |v| v.end_with?("_id", "_cents") }).to be_empty
end

Then("Add selected is disabled") do
  button = page_doc.at_css(".rb-column-groups button[data-report-builder-select-target='submit']")
  expect(button["disabled"]).not_to be_nil
end

Then("the {string} column picker shows {string} with the hints {string}") do |model, label, hints|
  config = ReportBuilderConfig.new("root_model" => model)
  cols = ReportBuilderColumnCatalog.grouped_for(config).flat_map { |g| g[:columns] }.select { |c| c[:label].casecmp?(label) }
  expect(cols.pluck(:hint).sort).to eq(hints.split(",").map(&:strip).sort)
end

# The menu of one preview header (builder mode)
def header_menu(label)
  menu = page_doc.css("turbo-frame#report_builder_preview .dropdown").find { |d| d.at_css("button[aria-label='#{label} column menu']") }
  expect(menu).not_to be_nil, "no menu for #{label}"
  menu
end

Then("the {string} header menu has no Total") do |label|
  expect(header_menu(label).at_css("select[name='aggregate']")).to be_nil
end

Then("the {string} header menu can't move {string}") do |label, direction|
  button = header_menu(label).css("button").find { |b| b["aria-label"] == "Move #{label} #{direction}" }
  expect(button["disabled"]).not_to be_nil
end

# ─────────────────────────────────────────────────────────────────────────────
# Filters
# ─────────────────────────────────────────────────────────────────────────────

When("I open the filter row for {string}") do |field|
  rb_session.get "/report_builder/#{@report.id}/filter_row", params: { field: field }
  @last_rb_response = rb_session.response
end

When("I open the filter row for {string} on {string}") do |field, relation|
  rb_session.get "/report_builder/#{@report.id}/filter_row", params: { field: field, relation: relation }
  @last_rb_response = rb_session.response
end

Then("the filter row offers the choices {string}") do |choices|
  row = page_doc.at_css(".filter-row")
  options = row.css("select.filter-val option").map { |o| o.text.strip }.reject { |t| t.start_with?("—") }
  expect(options).to eq(choices.split(",").map(&:strip))
end

Then("the filter row is a text box") do
  row = page_doc.at_css(".filter-row")
  expect(row["data-kind"]).to eq("text")
  expect(row.at_css("input.filter-val[type='text']")).not_to be_nil
  expect(row.at_css("select.filter-val")).to be_nil
end

Then("the filter row operators are {string}") do |labels|
  expect(page_doc.css(".filter-row select.filter-op option").map { |o| o.text.strip }).to eq(labels.split(",").map(&:strip))
end

Given("{int} investors with different cities exist") do |count|
  count.times { |i| build_investor(entity: @entity, name: "City Investor #{i + 1}").update_columns(city: "City #{i + 1}") }
end

# ─────────────────────────────────────────────────────────────────────────────
# Formula editor and pivot preview
# ─────────────────────────────────────────────────────────────────────────────

When("I check the formula {string}") do |expression|
  rb_post "/report_builder/#{@report.id}/validate_formula", params: { expression: expression }
end

# "Aditi Rao=40.00; Nova LP=" — row name = shown result, in row order
Then("the formula works with the samples {string}") do |pairs|
  json = last_rb_json
  expect(json["ok"]).to be(true), "formula refused: #{json['error']}"
  expected = pairs.split(";").map { |p| p.split("=", 2).map(&:strip) }
  expect(json["samples"].map { |s| [s["row"], s["value"]] }).to eq(expected.map { |r, v| [r, v.to_s] })
end

Then("the formula is refused") do
  json = last_rb_json
  expect(json["ok"]).to be(false)
  expect(json["error"]).to be_present
  expect(json["samples"]).to be_nil
end

When("I preview a pivot on {string} by {string} on {string}") do |relation, group_by, value_col|
  rb_session.get "/report_builder/#{@report.id}/pivot_preview",
                 params: { relation: relation, group_bys: [group_by], value_col: value_col },
                 headers: { "Accept" => "application/json" }
  @last_rb_response = rb_session.response
end

Then("the pivot preview says {int} columns: {string}") do |count, headers|
  json = last_rb_json
  expect(json["count"]).to eq(count)
  expect(json["headers"]).to eq(headers.split(",").map(&:strip))
end

Then("the pivot preview is refused with {string}") do |message|
  expect(@last_rb_response.status).to eq(422)
  expect(last_rb_json["error"]).to eq(message)
end

# ─────────────────────────────────────────────────────────────────────────────
# Undo
# ─────────────────────────────────────────────────────────────────────────────

# The token carried by the Undo button of the last builder message
def remember_undo_token
  @undo_token = stream_target("report_builder_toasts").at_css("form input[name='token']")&.[]("value")
end

After("@report_builder") do
  travel_back
end

When("I remove the column {string} from the builder") do |key|
  builder_request(:delete, "/report_builder/#{@report.id}/columns/#{report_gvp(key).id}")
  remember_undo_token
end

When("I remove the related data {string} from the builder") do |relation|
  builder_request(:delete, "/report_builder/#{@report.id}/join", relation: relation)
  remember_undo_token
end

When("I undo from the builder") do
  builder_request(:post, "/report_builder/#{@report.id}/undo", token: @undo_token)
end

When("I sort by {string} {string} from the builder") do |key, dir|
  builder_request(:patch, "/report_builder/#{@report.id}/sort", sort_key: key, sort_dir: dir)
end

Then("the builder message offers Undo") do
  expect(@undo_token).to be_present, "no Undo button in the message"
end

Then("the column {string} is at position {int}") do |key, position|
  keys = @report.reload.grid_view_preferences.reorder(:sequence, :id).map { |g| g.key.split(";").first.strip }
  expect(keys.index(key)).to eq(position - 1), "columns: #{keys.inspect}"
end

Then("the report has the related data {string} filtered to {string} = {string}") do |relation, field, value|
  join = ReportBuilderConfig.new(@report.reload.template).joins.find { |j| j[:relation].to_s == relation }
  expect(join).not_to be_nil, "no related data #{relation}"
  expect((join[:child_filters] || {}).stringify_keys["#{field}_eq"]).to eq(value)
end

Then("the report has no related data {string}") do |relation|
  expect(ReportBuilderConfig.new(@report.reload.template).joins.map { |j| j[:relation].to_s }).not_to include(relation)
end

Then("the Remove button of {string} names the columns {string}") do |relation, labels|
  button = page_doc.css("button").find { |b| b["aria-label"] == "Remove #{relation.humanize}" }
  expect(button).not_to be_nil, "no Remove button for #{relation}"
  message = Nokogiri::HTML(button["data-msg"]).text
  expect(message).to include("Immediate Actions")
  labels.split(",").map(&:strip).each { |label| expect(message).to include(label) }
end

# ─────────────────────────────────────────────────────────────────────────────
# Health check
# ─────────────────────────────────────────────────────────────────────────────

After("@report_builder") do
  ReportBuilderHealthCheck.export_info_rows = ReportBuilderHealthCheck::EXPORT_INFO_ROWS
end

def health_items
  ReportBuilderHealthCheck.new(report: @report.reload, entity: @entity, user: @report.user).items
end

Given("the export threshold is {int} rows") do |rows|
  ReportBuilderHealthCheck.export_info_rows = rows
end

Given("the report also shows {string} labelled {string}") do |key, label|
  add_report_column(@report, key).update!(label: label)
end

Given("the report's own rows are filtered to {string} = {string}") do |field, value|
  tmpl = @report.reload.template.deep_stringify_keys
  @report.update!(template: tmpl.merge("root_filters" => { "#{field}_eq" => value }))
end

When("I add the formula {string} as {string} from the builder") do |expression, label|
  builder_request(:post, "/report_builder/#{@report.id}/formulas", expression: expression, label: label)
end

# E17 — copies of a Growth Fund II commitment, one per extra unit type (no callbacks: only the unit type matters)
Given("Growth Fund II has {int} more unit types") do |count|
  generated = CapitalCommitment.columns.select(&:virtual?).map(&:name)
  base = acme[:c1].attributes.except("id", "created_at", "updated_at", "slug", *generated)
  rows = (1..count).map { |i| base.merge("folio_id" => "U-#{i}", "slug" => "u-#{i}", "unit_type" => format("U%02d", i)) }
  CapitalCommitment.insert_all(rows)
end

Given("the report pivots {string} by {string} on {string}") do |relation, group_by, value_col|
  tmpl = @report.reload.template.deep_stringify_keys
  tmpl["joins"].each do |j|
    j["pivot"] = { "group_bys" => [group_by], "value_col" => value_col, "aggregate" => "sum" } if j["relation"] == relation
  end
  @report.update!(template: tmpl)
end

When("I open the builder's report check") do
  step "I open the builder"
end

Then("the report check says {string}") do |text|
  badge = page_doc.at_css("turbo-frame#report_builder_health .rb-health-badge")
  expect(badge).not_to be_nil, "no health badge"
  expect(badge.text.gsub(/[[:space:]]+/, " ").strip).to eq(text)
end

Then("the report check warns {string} with a Fix for {string}") do |message, tab|
  item = page_doc.css("turbo-frame#report_builder_health .rb-health-item").find do |el|
    el.at_css(".rb-health-message").text.strip == message
  end
  expect(item).not_to be_nil, "no item #{message}; got #{page_doc.css('.rb-health-message').map { |m| m.text.strip }.inspect}"
  expect(item["data-level"]).to eq("warning")
  expect(item.at_css("button[data-tab]")["data-tab"]).to eq(tab)
end

Then("the report check notes {string}") do |message|
  expect(health_items.select { |i| i[:level] == :info }.pluck(:message)).to include(message)
end

Then("the report check has no notes") do
  expect(health_items).to be_empty
end

Given("a(n) {string} report with no columns") do |root_model|
  @report = build_report(entity: @entity, user: @user, root_model: root_model, columns: [])
end
