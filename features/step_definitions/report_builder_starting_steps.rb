# frozen_string_literal: true

# Report Builder starting points — the New report menu, starter templates,
# the template check and Duplicate, over HTTP (no browser) on the Acme fixture
# from report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-starting-points/business-rules.md

After("@report_builder") do
  # X1, X5 swap in a broken template; put the file back
  ReportBuilderTemplates.reset!
end

module ReportBuilderStartingWorld
  # A new, unsaved builder report of Acme for the applier
  def new_acme_report(name)
    Report.new(entity: @entity, user: @user, name: name, report_builder: true, url: "/report_builder")
  end

  def acme_fund(name)
    Fund.find_by!(entity_id: @entity.id, name: name)
  end

  # Applies a template as the template page would, with Growth Fund II where a fund is asked for
  def apply_template_for_check(template)
    fund = template["fund"] == "none" ? nil : acme_fund("Growth Fund II")
    ReportSpecApplier.apply!(report: new_acme_report(template["name"]), spec: template["spec"], fund: fund)
  end
end

World(ReportBuilderStartingWorld)

module ReportBuilderStartingRequests
  # A request that may end in Not found: tests run with show_exceptions off,
  # so record / route not-found errors raise instead of answering 404
  def rb_request_or_not_found(verb, path, params = {})
    @not_found = false
    rb_session.public_send(verb, path, params: params)
    @last_rb_response = rb_session.response
  rescue ActiveRecord::RecordNotFound, ActionController::RoutingError
    @not_found = true
  end

  def follow_rb_redirect
    return unless @last_rb_response&.redirect?

    rb_session.follow_redirect!
    @last_rb_response = rb_session.response
  end

  def rb_page_text
    Nokogiri::HTML(@last_rb_response.body).text.gsub(/[[:space:]]+/, " ")
  end

  def template_modal(key)
    page_doc.at_css("#templateModal_#{key}")
  end
end

World(ReportBuilderStartingRequests)

# ─────────────────────────────────────────────────────────────────────────────
# New report menu and naming (H1, H11, E7)
# ─────────────────────────────────────────────────────────────────────────────

When("I open the Reports page") do
  rb_session.get "/reports"
  @last_rb_response = rb_session.response
end

Then("the New report menu offers {string}") do |items|
  menu = page_doc.at_css(".rb-new-report")
  expect(menu).not_to be_nil, "no New report menu"
  expect(menu.at_css("button").text.strip).to eq("New report")
  expect(menu.css(".dropdown-item").map { |a| a.text.strip }).to eq(items.split(",").map(&:strip))
end

Then("the page has no {string}") do |text|
  expect(rb_page_text).not_to include(text)
end

Then("the card menu of {string} offers {string}") do |name, items|
  card = page_doc.css(".single-note-item, .card").find { |c| c.text.include?(name) && c.at_css(".category-menu") }
  expect(card).not_to be_nil, "no card for #{name}"
  menu_text = card.at_css(".category-menu").text.gsub(/[[:space:]]+/, " ")
  items.split(",").map(&:strip).each { |item| expect(menu_text).to include(item) }
end

When("I open {string} of the report") do |what|
  path = { "guided setup" => "/report_builder/#{@report.id}/wizard/show",
           "the builder" => "/report_builder/#{@report.id}/edit" }.fetch(what)
  rb_session.get path
  @last_rb_response = rb_session.response
end

Then("the report builder page reads {string}") do |text|
  expect(rb_page_text).to include(text)
end

Then("the builder has no Templates button") do
  expect(page_doc.css("button, a").map { |b| b.text.strip }).not_to include("Templates")
  expect(page_doc.at_css("[data-bs-target='#templateModal']")).to be_nil
end

When("I request the old apply-template address") do
  @columns_before = @report.grid_view_preferences.count
  rb_request_or_not_found(:post, "/report_builder/#{@report.id}/apply_template", template_key: "kyc_audit")
end

Then("the answer is Not found") do
  expect(@not_found || @last_rb_response&.status == 404).to be(true)
end

Then("the report is unchanged") do
  expect(@report.reload.grid_view_preferences.count).to eq(@columns_before)
end

# ─────────────────────────────────────────────────────────────────────────────
# Template page and create (H2–H8, E1–E3, E6, E8, X2, X3, X5)
# ─────────────────────────────────────────────────────────────────────────────

When("I open the template page") do
  rb_session.get "/report_builder/templates"
  @last_rb_response = rb_session.response
end

Then("the template page lists the areas {string}") do |areas|
  expect(page_doc.css(".rb-template-area").map { |a| a.text.strip }).to eq(areas.split(",").map(&:strip))
end

Then("the template page lists {int} templates") do |count|
  expect(page_doc.css(".rb-template-card").size).to eq(count)
end

Then("the template page lists only {string}") do |names|
  expect(page_doc.css(".rb-template-card .fw-semibold").map { |n| n.text.strip }).to eq(names.split(",").map(&:strip))
end

Then("the {string} card reads {string}") do |key, text|
  card = page_doc.at_css(".rb-template-card[data-template='#{key}']")
  expect(card).not_to be_nil, "no card #{key}"
  expect(card.text.gsub(/[[:space:]]+/, " ")).to include(text)
end

Then("the {string} popup has no Fund field") do |key|
  expect(template_modal(key).at_css("select[name='fund_id']")).to be_nil
end

Then("the {string} popup's funds are {string}") do |key, names|
  options = template_modal(key).css("select[name='fund_id'] option").map { |o| o.text.strip }
  expect(options).to eq(names.split(",").map(&:strip))
end

When("I create {string} from its template with the fund {string}") do |key, fund|
  @reports_before = Report.count
  name = ReportBuilderTemplates.all.dig(key, "name")
  fund_id = fund == "All funds" || fund.blank? ? "" : acme_fund(fund).id
  rb_request_or_not_found(:post, "/report_builder/templates/#{key}", name: name, fund_id: fund_id)
  @created = Report.order(:id).last if Report.count > @reports_before
  @report = @created if @created
end

When("I create {string} from its template named {string} with the fund {string}") do |key, name, fund|
  @reports_before = Report.count
  rb_request_or_not_found(:post, "/report_builder/templates/#{key}", name: name, fund_id: acme_fund(fund).id)
  @report = Report.order(:id).last if Report.count > @reports_before
end

When("I create {string} from its template with another company's fund") do |key|
  @reports_before = Report.count
  other = build_fund_entity(name: "Beta Partners")
  beta_fund = FactoryBot.create(:fund, entity: other, name: "Beta Fund", currency: "USD")
  rb_request_or_not_found(:post, "/report_builder/templates/#{key}", fund_id: beta_fund.id)
end

Given("Beta Partners has the fund {string}") do |name|
  other = build_fund_entity(name: "Beta Partners")
  FactoryBot.create(:fund, entity: other, name: name, currency: "USD")
end

Then("the builder opens for {string} saying {string}") do |name, message|
  expect(@last_rb_response).to be_redirect
  expect(@last_rb_response.location).to end_with("/report_builder/#{@report.id}/edit")
  expect(@report.name).to eq(name)
  follow_rb_redirect
  expect(rb_page_text).to include(message)
end

Then("the created report is named {string}") do |name|
  expect(@report.reload.name).to eq(name)
end

Then("no report is created from the template") do
  expect(Report.count).to eq(@reports_before)
end

Then("the template page says {string}") do |message|
  follow_rb_redirect
  expect(rb_page_text).to include(message)
end

Then("the report's columns are {string}") do |labels|
  actual = @report.reload.grid_view_preferences.reorder(:sequence, :id).map { |g| g.label.presence || g.name }
  expect(actual).to eq(labels.split(",").map(&:strip))
end

Then("the report's own rows are filtered by {string}") do |filters|
  expect(@report.reload.template["root_filters"]).to eq(JSON.parse(filters))
end

Then("the report's {string} are limited to {string}") do |relation, fund|
  join = ReportBuilderConfig.new(@report.reload.template).join_for(relation)
  expect((join[:child_filters] || {}).stringify_keys["fund_id_eq"]).to eq(acme_fund(fund).id.to_s)
end

Then("the report's own rows are limited to {string}") do |fund|
  expect(@report.reload.template.dig("root_filters", "fund_id_eq")).to eq(acme_fund(fund).id.to_s)
end

Then("the report has no fund filter at all") do
  template = @report.reload.template
  filters = [template.dig("root_filters", "fund_id_eq")] + (template["joins"] || []).map { |j| (j["child_filters"] || {})["fund_id_eq"] }
  expect(filters.compact).to be_empty
end

Then("the created report is sorted by {string} {string}") do |label, dir|
  template = @report.reload.template
  key = template.dig("sort", "key")
  formula = (template["formulas"] || []).find { |f| f["key"] == key }
  expect(formula ? formula["label"] : key).to eq(label)
  expect(template.dig("sort", "dir")).to eq(dir)
end

Then("the report check says {string} for the report") do |text|
  check = ReportBuilderHealthCheck.new(report: @report.reload, entity: @entity, user: @report.user)
  summary = check.warnings_count.zero? ? "All good" : "#{check.warnings_count} warning#{'s' unless check.warnings_count == 1}"
  expect(summary).to eq(text), check.items.inspect
end

Then("the report check warns {string} for the report") do |message|
  items = ReportBuilderHealthCheck.new(report: @report.reload, entity: @entity, user: @report.user).items
  expect(items.select { |i| i[:level] == :warning }.pluck(:message)).to include(message)
end

Then("the report check notes {string} for the report, with no warning") do |message|
  items = ReportBuilderHealthCheck.new(report: @report.reload, entity: @entity, user: @report.user).items
  expect(items.select { |i| i[:level] == :info }.pluck(:message)).to include(message)
  expect(items.select { |i| i[:level] == :warning }).to be_empty
end

# "Aditi Rao: Unpaid=20,00,000.00 | Called %=40.00; …" against the report's displayed rows
Then("the created report's rows show {string}") do |expected|
  run_report(@report)
  config = ReportBuilderConfig.new(@report.template)
  formatter = ReportBuilderValueFormatter.new(config: config, entity: @entity)
  columns = @engine.columns
  expected.split(";").map(&:strip).each do |row_spec|
    name, cells = row_spec.split(":", 2).map(&:strip)
    row = @rows.find { |r| r.values.map(&:to_s).include?(name) }
    expect(row).not_to be_nil, "no row #{name}"
    cells.split("|").map(&:strip).each do |cell|
      label, value = cell.split("=", 2).map(&:strip)
      column = columns.find { |c| c.label == label }
      expect(column).not_to be_nil, "no column #{label}: #{columns.map(&:label)}"
      expect(formatter.display(row[column.key], column)).to eq(value)
    end
  end
end

# The rest tie on the sort (Unpaid 0.00 each), so their order isn't fixed
Then("the created report lists {string} first, then {string}") do |first_name, rest|
  run_report(@report)
  first = @engine.columns.first
  names = @rows.map { |r| r[first.key].to_s }
  expect(names.first).to eq(first_name)
  expect(names.drop(1)).to match_array(rest.split(",").map(&:strip))
end

Then("the created report's rows are {string}") do |names|
  run_report(@report)
  first = @engine.columns.first
  expect(@rows.map { |r| r[first.key].to_s }).to eq(names.split(",").map(&:strip))
end

Then("the report has a pivot on {string}") do |relation|
  join = ReportBuilderConfig.new(@report.reload.template).join_for(relation)
  expect(join[:pivot]).to be_present
  expect(@report.grid_view_preferences.pluck(:key)).to include("pivot:#{relation}")
end

Given("Acme has the Funds and Deals features") do
  @entity.permissions.set(:enable_funds)
  @entity.permissions.set(:enable_deals)
  @entity.save!
end

Given("Acme has the Deals feature but not Funds") do
  @entity.permissions.set(:enable_deals)
  @entity.permissions.unset(:enable_funds)
  @entity.save!
end

Given("K2 also has Aditi's Global Fund commitment") do
  acme[:c4].update_columns(investor_kyc_id: acme[:k2].id)
end

# E1 — the template page again (422) with the template's popup saying what's missing
Then("the template popup says {string}") do |message|
  expect(@last_rb_response.status).to eq(422)
  expect(rb_page_text).to include(message)
end

Given("the template {string} breaks after the template check") do |key|
  template = ReportBuilderTemplates.all[key].deep_dup
  template["spec"]["columns"].first["key"] = "no_such_column"
  ReportBuilderTemplates.override!(key, template)
end

# ─────────────────────────────────────────────────────────────────────────────
# Template check (H12, X1)
# ─────────────────────────────────────────────────────────────────────────────

Then("every starter template passes the template check") do
  problems = ReportBuilderTemplates.all.values.flat_map do |template|
    errors = ReportSpecValidator.errors_for(template["spec"], entity: @entity, name: template["name"])
    next errors if errors.any?

    # Valid — it must also create and run
    report = apply_template_for_check(template)
    ReportBuilderQueryEngine.new(report: report, entity: @entity, user: report.user).run(limit: 5)
    []
  rescue StandardError => e
    ["#{template['name']}: #{e.class} #{e.message}"]
  end
  expect(problems).to be_empty, problems.join("\n")
end

Given("the template {string} uses the column {string} instead of {string}") do |key, bad, good|
  template = ReportBuilderTemplates.all[key].deep_dup
  template["spec"]["columns"].each { |col| col["key"] = bad if col["key"] == good }
  template["spec"]["formulas"]&.each { |f| f["expression"] = f["expression"].gsub("[#{good}]", "[#{bad}]") }
  ReportBuilderTemplates.override!(key, template)
end

When("I run the template check on {string}") do |key|
  template = ReportBuilderTemplates.all[key]
  @check_errors = ReportSpecValidator.errors_for(template["spec"], entity: @entity, name: template["name"])
end

Then("the template check fails with {string}") do |message|
  expect(@check_errors).to include(message)
end

# ─────────────────────────────────────────────────────────────────────────────
# Duplicate (H9, H10, E4, E5, X4)
# ─────────────────────────────────────────────────────────────────────────────

Given("the report groups rows in Excel by {string}") do |key|
  @report.update!(template: @report.reload.template.merge("group_rows_by" => key))
end

Given("the report is emailed weekly to {string}") do |emails|
  @report.create_report_schedule!(frequency: "weekly", recipients: emails.split(",").map(&:strip), enabled: true)
end

Given("Acme already has a report named {string}") do |name|
  build_report(entity: @entity, user: @user, root_model: "Investor").update!(name: name)
end

When("I duplicate the report") do
  @original = @report
  @reports_before = Report.count
  rb_request_or_not_found(:post, "/report_builder/#{@original.id}/duplicate")
  @copy = Report.order(:id).last if Report.count > @reports_before
end

Then("the builder opens for the copy {string} saying {string}") do |name, message|
  expect(@copy).not_to be_nil, "no copy created"
  expect(@copy.name).to eq(name)
  expect(@last_rb_response.location).to end_with("/report_builder/#{@copy.id}/edit")
  follow_rb_redirect
  expect(rb_page_text).to include(message)
end

Then("the copy is named {string}") do |name|
  expect(@copy.reload.name).to eq(name)
end

# Columns (keys, labels, order — formula positions included), totals, related data, filters, formulas, sort, grouping
Then("the copy has the same set-up as the original") do
  columns = ->(report) { report.reload.grid_view_preferences.reorder(:sequence, :id).map { |g| [g.key, g.label] } }
  expect(columns.call(@copy)).to eq(columns.call(@original))
  original = @original.template.deep_stringify_keys
  copy = @copy.template.deep_stringify_keys
  %w[root_model aggregates root_filters formulas sort group_rows_by currency].each do |part|
    expect(copy[part]).to eq(original[part]), "#{part} differs"
  end
  slim = ->(joins) { (joins || []).map { |j| j.slice("relation", "child_filters", "only_with_rows", "pivot") } }
  expect(slim.call(copy["joins"])).to eq(slim.call(original["joins"]))
end

When("I limit the copy's {string} to {string}") do |relation, fund|
  template = @copy.reload.template.deep_stringify_keys
  template["joins"].each do |join|
    join["child_filters"] = (join["child_filters"] || {}).merge("fund_id_eq" => acme_fund(fund).id.to_s) if join["relation"] == relation
  end
  @copy.update!(template: template)
end

def expect_related_fund(report, relation, fund)
  join = ReportBuilderConfig.new(report.reload.template).join_for(relation)
  expect((join[:child_filters] || {}).stringify_keys["fund_id_eq"]).to eq(acme_fund(fund).id.to_s)
end

Then("the copy's {string} are limited to {string}") do |relation, fund|
  expect_related_fund(@copy, relation, fund)
end

Then("the original's {string} are limited to {string}") do |relation, fund|
  expect_related_fund(@original, relation, fund)
end

Then("the copy has no schedule and no Undo") do
  expect(@copy.reload.report_schedule).to be_nil
  expect(@copy.template).not_to have_key("undo")
end

Then("the original still has its schedule and its Undo") do
  expect(@original.reload.report_schedule).to be_present
  expect(@original.template).to have_key("undo")
end

Then("no copy is created") do
  expect(Report.count).to eq(@reports_before)
end
