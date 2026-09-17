# frozen_string_literal: true

# Guided wizard — HTTP-level (ActionDispatch::Integration::Session, no
# browser) step definitions. Reuses the `rb_session`/`rb_sign_in` helpers
# from ReportBuilderWorld (features/step_definitions/report_builder_steps.rb),
# already mixed into every scenario via `World(ReportBuilderWorld)`.
#
# Deliberately uses rb_session.{get,post,patch,delete} directly (plain form
# params) rather than the rb_get/rb_post/rb_patch helpers, which force JSON
# Accept/Content-Type headers — the wizard's own pages are plain HTML forms,
# and update_aggregate/update_sort branch on that (JSON for the advanced
# builder's JS, HTML redirect for the wizard).

When("I visit the wizard start page") do
  rb_session.get "/report_builder/wizard"
  @last_rb_response = rb_session.response
end

Then("the wizard page should be successful") do
  expect(@last_rb_response.status).to be_between(200, 299), "expected 2xx, got #{@last_rb_response.status}: #{@last_rb_response.body[0, 500]}"
end

Then("the wizard page should mention {string}") do |text|
  expect(rb_session.response.body).to include(text)
end

When("I create a report via the wizard with name {string} and root model {string}") do |name, root_model|
  rb_session.post "/report_builder/wizard", params: { name: name, root_model: root_model }
  @last_rb_response = rb_session.response
  rb_session.follow_redirect! if @last_rb_response.redirect?
  @wizard_report = Report.where(name: name, report_builder: true).order(:created_at).last
end

Then("the wizard-created report should have root model {string}") do |root_model|
  expect(ReportBuilderConfig.new(@wizard_report.template).root_model).to eq(root_model)
end

Then("I should be on the wizard {string} step") do |step|
  expect(rb_session.path).to include("/wizard/#{step}")
end

When("I visit the wizard {string} step for the report") do |step|
  rb_session.get "/report_builder/#{@wizard_report.id}/wizard/#{step}"
  @last_rb_response = rb_session.response
  rb_session.follow_redirect! if @last_rb_response.redirect?
end

When("I add the column {string} to the wizard report") do |col_key|
  rb_session.post "/report_builder/#{@wizard_report.id}/columns", params: { key: col_key, name: col_key.humanize }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report should have column {string}") do |col_key|
  @wizard_report.reload
  expect(@wizard_report.grid_view_preferences.map { |g| g.key.split(";").first.strip }).to include(col_key)
end

When("I rename the wizard column {string} to {string}") do |col_key, new_label|
  gvp = @wizard_report.grid_view_preferences.find { |g| g.key.split(";").first.strip == col_key }
  rb_session.patch "/report_builder/#{@wizard_report.id}/columns/#{gvp.id}", params: { label: new_label }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard column {string} should have label {string}") do |col_key, expected_label|
  @wizard_report.reload
  gvp = @wizard_report.grid_view_preferences.find { |g| g.key.split(";").first.strip == col_key }
  expect(gvp.label).to eq(expected_label)
end

Then("the wizard report should not have column {string}") do |col_key|
  @wizard_report.reload
  expect(@wizard_report.grid_view_preferences.map { |g| g.key.split(";").first.strip }).not_to include(col_key)
end

When("I apply a wizard pivot on join {string} grouping by {string} valued by {string} aggregate {string}") do |relation, group_by, value_col, aggregate|
  rb_session.patch "/report_builder/#{@wizard_report.id}/pivot",
                   params: { relation: relation, "group_bys[]" => [group_by], value_col: value_col, aggregate: aggregate }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

When("I clear the wizard pivot on join {string}") do |relation|
  rb_session.patch "/report_builder/#{@wizard_report.id}/pivot", params: { relation: relation, clear: "1" }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template join {string} should have a pivot config") do |relation|
  @wizard_report.reload
  join = @wizard_report.template["joins"].find { |j| j["relation"] == relation }
  expect(join["pivot"]).to be_present
end

Then("the wizard report template join {string} should not have a pivot config") do |relation|
  @wizard_report.reload
  join = @wizard_report.template["joins"].find { |j| j["relation"] == relation }
  expect(join["pivot"]).to be_nil
end

When("I add the join {string} with model {string} to the wizard report") do |relation, model|
  rb_session.post "/report_builder/#{@wizard_report.id}/join", params: { relation: relation, model: model, fk: "investor_id" }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template should include join {string}") do |relation|
  @wizard_report.reload
  joins = @wizard_report.template["joins"] || []
  expect(joins.pluck("relation")).to include(relation)
end

When("I set the aggregate for {string} to {string} via the wizard") do |key, agg|
  rb_session.patch "/report_builder/#{@wizard_report.id}/aggregate", params: { key: key, aggregate: agg }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template aggregate for {string} should be {string}") do |key, agg|
  @wizard_report.reload
  expect(ReportBuilderConfig.new(@wizard_report.template).aggregate_for(key)).to eq(agg)
end

When("I add a wizard root filter on field {string} operator {string} value {string}") do |field, op, value|
  rb_session.post "/report_builder/#{@wizard_report.id}/wizard_filter", params: { field: field, op: op, value: value }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template root filter {string} should be {string}") do |pred_key, value|
  @wizard_report.reload
  expect(@wizard_report.template["root_filters"][pred_key].to_s).to eq(value)
end

When("I remove the wizard root filter {string}") do |pred_key|
  rb_session.delete "/report_builder/#{@wizard_report.id}/wizard_filter", params: { pred_key: pred_key }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template should not have root filter {string}") do |pred_key|
  @wizard_report.reload
  expect(@wizard_report.template["root_filters"]).not_to have_key(pred_key)
end

When("I set the wizard sort to {string} direction {string}") do |key, dir|
  rb_session.patch "/report_builder/#{@wizard_report.id}/sort", params: { sort_key: key, sort_dir: dir }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

Then("the wizard report template sort key should be {string}") do |key|
  @wizard_report.reload
  expect(@wizard_report.template["sort"]["key"]).to eq(key)
end
