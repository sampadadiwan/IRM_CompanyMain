# frozen_string_literal: true

# Guided wizard — steps over HTTP (no browser), on the Acme fixture from
# report_builder_trust_steps.rb. The wizard's pages are plain HTML forms, so
# requests use plain form params and follow the redirect back to the step.
# Worked examples: openspec/changes/report-builder-live-builder/business-rules.md

module ReportBuilderWizardWorld
  def wizard_get(path)
    rb_session.get path
    @last_rb_response = rb_session.response
  end

  # A form post from a wizard step, then the step it returns to
  def wizard_submit(verb, path, params = {})
    rb_session.public_send(verb, path, params: params)
    @last_rb_response = rb_session.response
    @wizard_redirect = @last_rb_response.location if @last_rb_response.redirect?
    rb_session.follow_redirect! if @last_rb_response.redirect?
    @last_rb_response = rb_session.response
  end

  def wizard_step_path(step)
    "/report_builder/#{@report.id}/wizard/#{step}"
  end

  def wizard_text
    page_doc.text.gsub(/[[:space:]]+/, " ")
  end
end

World(ReportBuilderWizardWorld)

When("I open the wizard") do
  wizard_get "/report_builder/wizard"
end

Then("the wizard offers a card with an example question for every reportable table") do
  cards = page_doc.css("button.rb-wizard-table")
  expect(cards.size).to eq(ReportBuilderModelDiscovery.roots.size)
  cards.each do |card|
    expect(card.at_css(".ti")).not_to be_nil
    expect(card.at_css(".text-muted").text.strip).to be_present, "no example on #{card.text.strip}"
  end
end

When("I start a wizard report on {string}") do |root_model|
  @reports_before = Report.count
  wizard_submit(:post, "/report_builder/wizard", root_model: root_model)
  @report = Report.order(:id).last if Report.count > @reports_before
end

Given("a wizard {string} report") do |root_model|
  step %(I start a wizard report on "#{root_model}")
end

Then("the wizard report is named {string}") do |name|
  expect(@report.reload.name).to eq(name)
end

Then("I am on wizard step {string}") do |step|
  expect(rb_session.path).to eq(wizard_step_path(step))
end

Then("I am back on the wizard start with {string}") do |message|
  expect(rb_session.path).to eq("/report_builder/wizard")
  expect(wizard_text).to include(message)
end

Then("no report is created") do
  expect(Report.count).to eq(@reports_before)
end

When("I open wizard step {string}") do |step|
  wizard_get wizard_step_path(step)
end

When("I add {string} in the wizard") do |keys|
  wizard_submit(:post, "/report_builder/#{@report.id}/columns", keys: keys.split(",").map(&:strip), wizard_step: "show")
end

Then("the report includes related data {string}") do |relation|
  expect(ReportBuilderConfig.new(@report.reload.template).joins.map { |j| j[:relation].to_s }).to include(relation)
end

Then("the report has {int} columns in all") do |count|
  expect(@report.reload.grid_view_preferences.count).to eq(count)
end

Then("the wizard step shows the total {string} for {string}") do |label, key|
  wizard_get wizard_step_path("show")
  select = page_doc.at_css("table.rb-wizard-columns tr[data-key='#{key}'] select[name='aggregate']")
  expect(select).not_to be_nil, "no total for #{key}"
  expect(select.at_css("option[selected]").text.strip).to eq(label)
end

When("I set the total for {string} to {string} in the wizard") do |key, agg|
  wizard_submit(:patch, "/report_builder/#{@report.id}/aggregate", key: key, aggregate: agg, wizard_step: "show")
end

Then("the step has the 5-row sample") do
  frame = page_doc.at_css("turbo-frame#report_builder_preview")
  expect(frame).not_to be_nil, "no sample frame"
  expect(frame["src"]).to include("limit=5")
end

When("I pick the fund {string} in the wizard") do |name|
  fund_id = name == "All funds" ? "" : Fund.find_by!(entity_id: @entity.id, name: name).id
  wizard_submit(:post, "/report_builder/#{@report.id}/wizard_fund", fund_id: fund_id)
end

Then("the related data {string} is limited to the fund {string}") do |relation, name|
  join = ReportBuilderConfig.new(@report.reload.template).join_for(relation)
  expect((join[:child_filters] || {}).stringify_keys["fund_id_eq"]).to eq(Fund.find_by!(entity_id: @entity.id, name: name).id.to_s)
end

Then("the report has no fund filter") do
  config = ReportBuilderConfig.new(@report.reload.template)
  fund_filters = [config.root_filters["fund_id_eq"]] + config.joins.map { |j| (j[:child_filters] || {}).stringify_keys["fund_id_eq"] }
  expect(fund_filters.compact).to be_empty
end

Then("the step reads {string}") do |text|
  expect(wizard_text).to include(text)
end

Then("the step has no fund picker") do
  expect(page_doc.at_css("form.rb-wizard-fund")).to be_nil
end

When("I add the wizard filter {string} {string} {string}") do |field, op, value|
  wizard_submit(:post, "/report_builder/#{@report.id}/wizard_filter", field: field, op: op, value: value)
end

Then("the wizard picker opens only {string}") do |title|
  open = page_doc.css(".rb-column-groups details[open] summary").map { |s| s.text.strip }
  expect(open).to eq([title])
end

Then("the wizard picker lists {string} closed") do |titles|
  closed = page_doc.css(".rb-column-groups details:not([open]) summary").map { |s| s.text.strip }
  expect(closed).to eq(titles.split(",").map(&:strip))
end

Then("the wizard suggests {string}") do |names|
  expect(page_doc.css(".rb-wizard-suggestions li").pluck("data-name")).to eq(names.split(",").map(&:strip))
end

When("I add the suggestion {string}") do |name|
  form = page_doc.at_css(".rb-wizard-suggestions li[data-name='#{name}'] form")
  params = form.css("input[type='hidden']").to_h { |i| [i["name"], i["value"]] }.except("authenticity_token")
  wizard_submit(:post, form["action"], params)
end

Then("the suggestion {string} shows Added") do |name|
  expect(page_doc.at_css(".rb-wizard-suggestions li[data-name='#{name}']").text).to include("Added")
end

Then("the report has the formula {string}") do |label|
  expect((@report.reload.template["formulas"] || []).pluck("label")).to include(label)
end

Then("the summary has the cards {string}") do |titles|
  expect(page_doc.css(".rb-wizard-summary [data-card]").pluck("data-card")).to eq(titles.split(",").map(&:strip))
end

Then("the name box suggests {string}") do |name|
  expect(page_doc.at_css("#wizard_report_name")["value"]).to eq(name)
end

When("I follow the {string} card") do |title|
  link = page_doc.at_css(".rb-wizard-summary [data-card='#{title}'] a")
  wizard_get link["href"]
end

When("I save and open the wizard report with the suggested name") do
  name = page_doc.at_css("#wizard_report_name")["value"]
  wizard_submit(:patch, "/report_builder/#{@report.id}/wizard_save", name: name)
end

When("I save and open the wizard report with a blank name") do
  wizard_submit(:patch, "/report_builder/#{@report.id}/wizard_save", name: "")
end

Then("I am on the report's page") do
  expect(rb_session.path).to eq("/report_builder/#{@report.id}/view")
end

When("I choose Fine-tune in builder") do
  link = page_doc.css("a").find { |a| a.text.strip == "Fine-tune in builder" }
  wizard_get link["href"]
end

Then("the builder opens") do
  expect(rb_session.path).to eq("/report_builder/#{@report.id}/edit")
  expect(@last_rb_response.status).to eq(200)
end

# E26 — "columns → show, joins → show, …"
Then("the old wizard steps redirect as {string}") do |pairs|
  pairs.split(",").map { |p| p.split("→").map(&:strip) }.each do |old, new_step|
    rb_session.get wizard_step_path(old)
    expect(rb_session.response.location).to end_with(wizard_step_path(new_step)), "#{old} went to #{rb_session.response.location}"
  end
end
