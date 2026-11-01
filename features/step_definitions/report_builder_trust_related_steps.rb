# frozen_string_literal: true

# Report Builder you can trust — related data, pivots and only-with-rows steps.
# Uses the Acme fixture and helpers from report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

# U1 Aditi unit A qty 1,000 amount ₹1,000 · U2 Kiran unit A qty 500 amount ₹500
Given("the Acme fund units exist") do
  { u1: [:c1, :aditi, 1000, 1000], u2: [:c2, :kiran, 500, 500] }.each do |sym, (c, inv, qty, rupees)|
    unit = FactoryBot.create(:fund_unit, fund: acme[:gf2], entity: @entity, capital_commitment: acme[c], investor: acme[inv],
                                         unit_type: "A", quantity: qty, issue_date: Date.new(2026, 2, 15))
    unit.update_columns(unit_type: "A", quantity: qty, amount_cents: rupees * 100)
    acme[sym] = unit
  end
end

# D1 owned by C1 · D2 owned by a CapitalRemittance whose id equals C1's id · D3 owned by the fund (no commitment)
Given("the Acme documents exist") do
  folder = Folder.where(entity_id: @entity.id).first || FactoryBot.create(:folder, entity: @entity, name: "Docs")
  acme[:d1] = FactoryBot.create(:document, entity: @entity, user: @user, folder: folder, owner: acme[:c1], name: "D1")
  acme[:d2] = FactoryBot.create(:document, entity: @entity, user: @user, folder: folder, owner: acme[:r1], name: "D2")
  acme[:d3] = FactoryBot.create(:document, entity: @entity, user: @user, folder: folder, owner: acme[:gf2], name: "D3")
  # Pin the owners: document callbacks may re-home a document to its folder's owner
  acme[:d1].update_columns(owner_type: "CapitalCommitment", owner_id: acme[:c1].id)
  acme[:d2].update_columns(owner_type: "CapitalRemittance", owner_id: acme[:c1].id)
  acme[:d3].update_columns(owner_type: "Fund", owner_id: acme[:gf2].id)
end

# X1 — a saved join whose association no longer exists
Given("the report has broken related data {string}") do |relation|
  tmpl = @report.template.deep_stringify_keys
  tmpl["joins"] = (tmpl["joins"] || []) + [{ "relation" => relation, "model" => "Fund" }]
  @report.update!(template: tmpl)
end

# A "list" total: compared as a set, since the database decides the order and separator
Then("the row where {string} is {string} lists {string} in {string}") do |key_col, key_val, expected, column|
  actual = row_where(key_col, key_val)[column].to_s.split(/,\s*/).sort
  expect(actual).to eq(expected.split(/,\s*/).sort)
end

Given("the related data {string} is filtered to {string} = {string}") do |relation, field, value|
  # Reload: earlier steps may have changed the report over HTTP
  tmpl = @report.reload.template.deep_stringify_keys
  tmpl["joins"].each do |j|
    j["child_filters"] = (j["child_filters"] || {}).merge("#{field}_eq" => value) if j["relation"] == relation
  end
  @report.update!(template: tmpl)
end

Given("the report pivots {string} by {string} on {string} with {string}") do |relation, group_by, value_col, agg|
  tmpl = @report.template.deep_stringify_keys
  tmpl["joins"].each do |j|
    j["pivot"] = { "group_bys" => [group_by], "value_col" => value_col, "aggregate" => agg } if j["relation"] == relation
  end
  @report.update!(template: tmpl)
end

Given("the report keeps only rows that have {string}") do |relation|
  tmpl = @report.template.deep_stringify_keys
  tmpl["joins"].each { |j| j["only_with_rows"] = true if j["relation"] == relation }
  @report.update!(template: tmpl)
end

Then("the report headers include {string}") do |label|
  labels = @engine.columns.map { |c| c.label.presence || c.name }
  expect(labels).to include(label), "headers were #{labels.inspect}"
end

Then("the report has {int} row(s) and counts {int}") do |rows, count|
  expect(@rows.size).to eq(rows)
  expect(@engine.count).to eq(count)
end

Then("no row has {string} = {string}") do |column, value|
  expect(@rows.map { |r| r[column].to_s }).not_to include(value)
end

Then("the only row has {string} = {string}") do |column, value|
  expect(@rows.map { |r| r[column].to_s }).to eq([value])
end

When("I turn on only-with-rows for {string} over HTTP") do |relation|
  rb_patch "/report_builder/#{@report.id}/join_settings", params: { relation: relation, only_with_rows: "true" }
end

Then("only-with-rows is on for {string}") do |relation|
  expect(ReportBuilderConfig.new(@report.reload.template).only_with_rows?(relation)).to be true
end

Then("only-with-rows is off for {string}") do |relation|
  expect(ReportBuilderConfig.new(@report.reload.template).only_with_rows?(relation)).to be false
end

Given("I am signed in as Omar from another entity") do
  other = build_fund_entity(name: "Beta Partners")
  omar  = FactoryBot.create(:user, entity: other, first_name: "Omar", permissions: User.permissions.keys)
  # A fresh session: Devise ignores a sign-in while someone is already signed in
  @rb_session = nil
  rb_sign_in(omar)
end

Then("the change is refused") do
  expect(@last_rb_response.status).not_to be_between(200, 299)
end
