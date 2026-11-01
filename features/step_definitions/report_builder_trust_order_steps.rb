# frozen_string_literal: true

# Report Builder you can trust — formulas on plain numbers and column order steps.
# Uses the Acme fixture and helpers from report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

module ReportBuilderTrustOrderWorld
  def formula_key(label)
    "formula_#{label.parameterize(separator: '_')}"
  end

  def report_formula(label)
    ReportBuilderConfig.new(@report.reload.template).formulas.find { |f| f[:label] == label }
  end

  # Column labels in the order the preview, report page and export use
  def column_labels
    ReportBuilderQueryEngine.new(report: @report.reload, entity: @report.entity, user: @report.user).tap(&:run).columns.map { |c| c.label.presence || c.name }
  end
end

World(ReportBuilderTrustOrderWorld)

# A formula saved straight into the template (as older reports have them: no position row)
Given("the report has formula {string} = {string}") do |label, expression|
  tmpl = @report.template.deep_stringify_keys
  tmpl["formulas"] = (tmpl["formulas"] || []) + [{ "key" => formula_key(label), "label" => label, "expression" => expression }]
  @report.update!(template: tmpl)
end

Then("the row where {string} is {string} shows {string} in formula {string}") do |key_col, key_val, expected, label|
  expect_cell(row_where(key_col, key_val)[formula_key(label)], expected)
end

Then("the row where {string} is {string} is blank in formula {string}") do |key_col, key_val, label|
  expect(row_where(key_col, key_val)[formula_key(label)]).to be_nil
end

When("I add the formula {string} = {string} over HTTP") do |label, expression|
  rb_session.post "/report_builder/#{@report.id}/formulas", params: { label: label, expression: expression }
  @last_rb_response = rb_session.response
end

When("I remove the formula {string} over HTTP") do |label|
  rb_session.delete "/report_builder/#{@report.id}/formulas/#{report_formula(label)[:key]}"
  @last_rb_response = rb_session.response
end

When("I apply a pivot on {string} by {string} on {string} with {string} over HTTP") do |relation, group_by, value_col, agg|
  rb_session.patch "/report_builder/#{@report.id}/pivot",
                   params: { relation: relation, group_bys: [group_by], value_col: value_col, aggregate: agg }
  @last_rb_response = rb_session.response
end

When("I clear the pivot on {string} over HTTP") do |relation|
  rb_session.patch "/report_builder/#{@report.id}/pivot", params: { relation: relation, clear: "1" }
  @last_rb_response = rb_session.response
end

When("I remove the related data {string} over HTTP") do |relation|
  rb_session.delete "/report_builder/#{@report.id}/join", params: { relation: relation }
  @last_rb_response = rb_session.response
end

# Moves a column (or a formula / pivot position) the way drag-to-reorder does (acts_as_list insert_at, 1-based)
When("I move column {string} to position {int}") do |label, position|
  gvp = @report.reload.grid_view_preferences.find { |g| (g.label.presence || g.name) == label }
  expect(gvp).not_to be_nil, "no column labelled #{label}: #{@report.grid_view_preferences.map(&:label).inspect}"
  gvp.insert_at(position)
end

Then("the report columns are {string}") do |labels|
  expect(column_labels).to eq(labels.split(",").map(&:strip))
end

Then("the report has no position row for formula {string}") do |label|
  expect(@report.reload.grid_view_preferences.where("`key` LIKE ?", "formula:%").pluck(:name)).not_to include(label)
end

Then("the report has a position row for formula {string}") do |label|
  expect(@report.reload.grid_view_preferences.where(key: "formula:#{report_formula(label)[:key]}")).to exist
end

Then("the report has no pivot position row for {string}") do |relation|
  expect(@report.reload.grid_view_preferences.where(key: "pivot:#{relation}")).not_to exist
end

Then("the report has a pivot position row for {string}") do |relation|
  expect(@report.reload.grid_view_preferences.where(key: "pivot:#{relation}")).to exist
end
