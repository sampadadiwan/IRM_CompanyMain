# frozen_string_literal: true

# Report Builder — server-side Cucumber step definitions.
# No Capybara / browser usage. Two test surfaces:
#   1. Direct Ruby calls (QueryEngine, Aggregators, FormulaService, Scheduler)
#   2. ActionDispatch::Integration::Session for HTTP-level controller tests.

require "json"
require "bigdecimal"

# ─────────────────────────────────────────────────────────────────────────────
# World helpers
# ─────────────────────────────────────────────────────────────────────────────

module ReportBuilderWorld
  # HTTP helpers (no browser)
  def rb_session
    @rb_session ||= ActionDispatch::Integration::Session.new(Rails.application)
  end

  def rb_sign_in(user)
    rb_session.post "/users/sign_in",
                    params: { user: { email: user.email, password: "password" } }
    rb_session.follow_redirect! if rb_session.response.redirect?
  end

  def rb_get(path, params: {})
    rb_session.get path, params: params, headers: { "Accept" => "application/json" }
    @last_rb_response = rb_session.response
  end

  def rb_post(path, params: {})
    rb_session.post path, params: params.to_json,
                    headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    @last_rb_response = rb_session.response
  end

  def rb_patch(path, params: {})
    rb_session.patch path, params: params.to_json,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    @last_rb_response = rb_session.response
  end

  def rb_delete(path, params: {})
    rb_session.delete path, params: params
    @last_rb_response = rb_session.response
  end

  def last_rb_json
    JSON.parse(@last_rb_response.body)
  end

  # Factory helpers that avoid relying on `.sample` with an empty DB

  def build_fund_entity(name: "Test Fund Entity")
    entity = FactoryBot.create(:entity,
      entity_type: "Investment Fund",
      currency: "INR",
      name: name)
    ExchangeRate.create([
      { from: "USD", to: "INR", rate: 81.72, entity: entity, as_of: 10.years.ago },
      { from: "INR", to: "USD", rate: 0.012, entity: entity, as_of: 10.years.ago }
    ])
    entity
  end

  def build_investor(entity:, name: "Test Investor")
    investor_entity = FactoryBot.create(:entity, entity_type: "Startup", name: "#{name} Entity")
    Investor.create!(
      entity: entity,
      investor_entity: investor_entity,
      investor_name: name,
      category: "Lead Investor",
      primary_email: "#{name.parameterize}@example.com",
      city: "Mumbai"
    )
  end

  def build_report(entity:, user:, root_model:, columns: [], joins: [], aggregates: {},
                   root_filters: {}, sort: {}, formulas: [])
    report = Report.create!(
      entity: entity,
      user: user,
      name: "Test Report",
      report_builder: true,
      url: "/report_builder",
      template: {
        version: 1,
        root_model: root_model,
        joins: joins,
        aggregates: aggregates,
        root_filters: root_filters,
        sort: sort,
        formulas: formulas
      }
    )
    columns.each_with_index do |col, idx|
      report.grid_view_preferences.create!(
        key:       col[:key],
        name:      col[:name]  || col[:key].split(".").last.humanize,
        label:     col[:label] || col[:name] || col[:key].split(".").last.humanize,
        entity_id: entity.id,
        sequence:  idx + 1
      )
    end
    report
  end

  def build_commitment(entity:, investor:, amount_cents: 1_000_000)
    fund = Fund.where(entity: entity).first ||
           Fund.create!(entity: entity, name: "Test Fund", currency: "INR",
                        details: "Test", unit_types: "Series A")
    CapitalCommitment.create!(
      fund: fund,
      entity: entity,
      investor: investor,
      folio_committed_amount_cents: amount_cents,
      folio_currency: "INR",
      fund_close: "First Close",
      folio_id: rand(999_999),
      commitment_date: Date.today
    )
  end
end

World(ReportBuilderWorld)

Before("@report_builder") do
  ReportBuilderModelDiscovery.reset_cache!
end

After("@report_builder") do
  ReportBuilderModelDiscovery.reset_cache!
end

# ─────────────────────────────────────────────────────────────────────────────
# Shared data-setup steps
# ─────────────────────────────────────────────────────────────────────────────

Given("a report builder entity and user") do
  @entity = build_fund_entity
  @user   = FactoryBot.create(:user, entity: @entity, permissions: User.permissions.keys)
end

Given("that entity has an investor {string}") do |name|
  @investor = build_investor(entity: @entity, name: name)
end

Given("that investor has a capital commitment of {int} paise") do |paise|
  @commitment = build_commitment(entity: @entity, investor: @investor, amount_cents: paise)
end

Given("that investor has {int} capital commitments of {int} paise each") do |count, paise|
  @commitments = count.times.map { build_commitment(entity: @entity, investor: @investor, amount_cents: paise) }
end

Given("that investor has a KYC record") do
  @kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor: @investor, residency: "domestic")
end

Given("another investor {string} with no commitments") do |name|
  @investor2 = build_investor(entity: @entity, name: name)
end

# ─────────────────────────────────────────────────────────────────────────────
# ReportBuilderConfig steps
# ─────────────────────────────────────────────────────────────────────────────

Given("a report builder config with root model {string}") do |model|
  if @entity && @user
    @report = build_report(entity: @entity, user: @user, root_model: model, columns: [])
    @config = ReportBuilderConfig.new(@report.template)
  else
    @config = ReportBuilderConfig.new("root_model" => model)
  end
end

Given("a report builder config with template:") do |json_string|
  @config = ReportBuilderConfig.new(JSON.parse(json_string))
end

When("I check if the config is valid") do
  @config_valid = @config.valid?
end

Then("the config should be valid") do
  expect(@config_valid).to be true
end

Then("the config should not be valid") do
  expect(@config_valid).to be false
end

Then("the root class should be {string}") do |class_name|
  expect(@config.root_class.name).to eq(class_name)
end

Then("the config should have {int} join(s)") do |count|
  expect(@config.joins.size).to eq(count)
end

Then("the aggregate for {string} should be {string}") do |key, agg|
  expect(@config.aggregate_for(key)).to eq(agg)
end

Then("the aggregate for {string} should be nil") do |key|
  expect(@config.aggregate_for(key)).to be_nil
end

Then("join_for {string} should not be nil") do |rel|
  expect(@config.join_for(rel)).not_to be_nil
end

# ─────────────────────────────────────────────────────────────────────────────
# ReportBuilderModelDiscovery steps
# ─────────────────────────────────────────────────────────────────────────────

When("I request the list of report builder root models") do
  @discovered_roots = ReportBuilderModelDiscovery.roots
end

When("I request associations for {string}") do |model_name|
  klass = model_name.constantize
  @discovered_associations = ReportBuilderModelDiscovery.associations_for(klass)
end

Then("the roots list should include {string}") do |model_name|
  names = @discovered_roots.map(&:name)
  expect(names).to include(model_name)
end

Then("every root should be in the ROOT_MODELS whitelist") do
  whitelist = ReportBuilderModelDiscovery::ROOT_MODELS
  @discovered_roots.each do |klass|
    expect(whitelist).to(include(klass.name), "#{klass.name} is in roots but not in ROOT_MODELS")
  end
end

Then("every root should have an entity_id column") do
  @discovered_roots.each do |klass|
    expect(klass.column_names).to(include("entity_id"), "#{klass.name} is in roots but lacks entity_id")
  end
end

Then("the associations list should not be empty") do
  expect(@discovered_associations).not_to be_empty
end

Then("each association should have keys {string}") do |keys_str|
  keys = keys_str.split(",").map(&:strip)
  @discovered_associations.each do |assoc|
    keys.each do |k|
      expect(assoc).to have_key(k.to_sym)
    end
  end
end

Then("reset_cache! should clear the memoized roots") do
  first_call  = ReportBuilderModelDiscovery.roots.object_id
  ReportBuilderModelDiscovery.reset_cache!
  second_call = ReportBuilderModelDiscovery.roots.object_id
  expect(first_call).not_to eq(second_call)
end

# ─────────────────────────────────────────────────────────────────────────────
# QueryEngine steps
# ─────────────────────────────────────────────────────────────────────────────

Given("a report on {string} selecting column {string}") do |root_model, col_key|
  @report = build_report(
    entity: @entity,
    user:   @user,
    root_model: root_model,
    columns: [{ key: col_key }]
  )
end

Given("the report joins {string} with {string} aggregate on {string}") do |relation, agg, col_key|
  child_model = relation.classify

  tmpl = @report.template.deep_stringify_keys
  tmpl["joins"] ||= []
  tmpl["joins"] << {
    "relation"         => relation,
    "model"            => child_model,
    "include_zero_rows" => true
  }
  tmpl["aggregates"] ||= {}
  tmpl["aggregates"]["#{relation}.#{col_key}"] = agg
  @report.update!(template: tmpl)
  @report.grid_view_preferences.create!(
    key:       "#{relation}.#{col_key}",
    name:      col_key.humanize,
    label:     col_key.humanize,
    entity_id: @entity.id,
    sequence:  @report.grid_view_preferences.count + 1
  )
end

Given("the report has root filter {string} = {string}") do |field, value|
  tmpl = @report.template.deep_stringify_keys
  (tmpl["root_filters"] ||= {})[field] = value
  @report.update!(template: tmpl)
end

Given("the report is sorted by {string} {string}") do |col, dir|
  tmpl = @report.template.deep_stringify_keys
  tmpl["sort"] = { "key" => col, "dir" => dir }
  @report.update!(template: tmpl)
end

When("I run the report engine") do
  @engine = ReportBuilderQueryEngine.new(report: @report, entity: @entity)
  @rows   = @engine.run
end

When("I run the report engine with a limit of {int}") do |limit|
  @engine = ReportBuilderQueryEngine.new(report: @report, entity: @entity)
  @rows   = @engine.run(limit: limit)
end

When("I count rows via the report engine") do
  @engine    = ReportBuilderQueryEngine.new(report: @report, entity: @entity)
  @row_count = @engine.count
end

Then("the engine should return {int} row(s)") do |count|
  expect(@rows.size).to eq(count)
end

Then("the engine row count should be {int}") do |count|
  expect(@row_count).to eq(count)
end

Then("every row should have a key {string}") do |key|
  @rows.each do |row|
    expect(row).to have_key(key)
  end
end

Then("the first row's {string} should equal {string}") do |key, value|
  expect(@rows.first[key].to_s).to eq(value)
end

Then("the rows should be ordered by {string} ascending") do |col|
  values = @rows.map { |r| r[col] }.compact
  expect(values).to eq(values.sort)
end

Then("the rows should be ordered by {string} descending") do |col|
  values = @rows.map { |r| r[col] }.compact
  expect(values).to eq(values.sort.reverse)
end

Then("the engine columns should include a column with key {string}") do |key|
  keys = @engine.columns.map(&:key)
  expect(keys).to include(key)
end

# ─────────────────────────────────────────────────────────────────────────────
# Aggregation steps (ChildAggregator)
# ─────────────────────────────────────────────────────────────────────────────

When("I aggregate {string} on capital commitments for that investor using {string}") do |col, agg|
  @agg_col   = col
  @agg_type  = agg
  fk         = "investor_id"
  gvp_key    = "capital_commitments.#{col}"

  join_config = {
    relation:      "capital_commitments",
    base_class:    "CapitalCommitment",
    fk:            fk,
    child_filters: {}
  }
  aggregates = { gvp_key => agg }

  aggregator  = ReportBuilderChildAggregator.new(
    join_config: join_config,
    root_ids:    [@investor.id],
    aggregates:  aggregates,
    gvp_keys:    [gvp_key]
  )
  @agg_result = aggregator.call
end

When("I aggregate {string} on capital commitments with empty root ids") do |col|
  gvp_key    = "capital_commitments.#{col}"
  join_config = { relation: "capital_commitments", base_class: "CapitalCommitment",
                  fk: "investor_id", child_filters: {} }
  @agg_result = ReportBuilderChildAggregator.new(
    join_config: join_config,
    root_ids:    [],
    aggregates:  { gvp_key => "count" },
    gvp_keys:    [gvp_key]
  ).call
end

Then("the aggregation result should be empty") do
  expect(@agg_result).to eq({})
end

When("I aggregate {string} on investor KYCs for that investor using {string}") do |col, agg|
  @agg_col   = col
  @agg_type  = agg
  fk         = "investor_id"
  gvp_key    = "investor_kycs.#{col}"

  join_config = {
    relation:      "investor_kycs",
    base_class:    "InvestorKyc",
    fk:            fk,
    child_filters: {}
  }
  aggregates = { gvp_key => agg }

  aggregator  = ReportBuilderChildAggregator.new(
    join_config: join_config,
    root_ids:    [@investor.id],
    aggregates:  aggregates,
    gvp_keys:    [gvp_key]
  )
  @agg_result = aggregator.call
end

When("I aggregate {string} on capital commitments for both investors using {string}") do |col, agg|
  @agg_col   = col
  @agg_type  = agg
  fk         = "investor_id"
  gvp_key    = "capital_commitments.#{col}"

  join_config = {
    relation:      "capital_commitments",
    base_class:    "CapitalCommitment",
    fk:            fk,
    child_filters: {}
  }
  aggregates = { gvp_key => agg }

  aggregator  = ReportBuilderChildAggregator.new(
    join_config: join_config,
    root_ids:    [@investor.id, @investor2.id],
    aggregates:  aggregates,
    gvp_keys:    [gvp_key]
  )
  @agg_result = aggregator.call
end

Then("the aggregation result for the investor and column {string} should be {string}") do |col, expected|
  gvp_key = "capital_commitments.#{col}"
  actual  = @agg_result[@investor.id][gvp_key]
  expect(actual.to_s).to eq(expected)
end

Then("the aggregation result for the investor and KYC column {string} should be {string}") do |col, expected|
  gvp_key = "investor_kycs.#{col}"
  actual  = @agg_result[@investor.id][gvp_key]
  expect(actual.to_s).to eq(expected)
end

Then("the investor with no commitments should not appear in the aggregation result") do
  investor = @investor2 || @investor
  expect(@agg_result).not_to have_key(investor.id)
end

Then("the investor with no commitments should have {string} as {string} for {string}") do |expected, col, relation|
  gvp_key = "#{relation}.#{col}"
  actual  = @agg_result.fetch(@investor2.id, {}).fetch(gvp_key, nil)
  expect(actual.to_s).to eq(expected)
end

# ─────────────────────────────────────────────────────────────────────────────
# Filter steps
# ─────────────────────────────────────────────────────────────────────────────

When("I aggregate capital commitments with child filter {string} = {string} using {string}") do |field, value, agg|
  gvp_key     = "capital_commitments.folio_committed_amount"
  join_config = {
    relation:      "capital_commitments",
    base_class:    "CapitalCommitment",
    fk:            "investor_id",
    child_filters: { "#{field}_eq" => value }
  }
  aggregator  = ReportBuilderChildAggregator.new(
    join_config: join_config,
    root_ids:    [@investor.id],
    aggregates:  { gvp_key => agg },
    gvp_keys:    [gvp_key]
  )
  @agg_result = aggregator.call
end

Then("the investor should appear in the result with {int} commitment(s)") do |count|
  gvp_key = "capital_commitments.id"
  actual  = @agg_result[@investor.id]&.fetch(gvp_key, nil)
  expect(actual.to_i).to eq(count)
end

# ─────────────────────────────────────────────────────────────────────────────
# Formula steps
# ─────────────────────────────────────────────────────────────────────────────

Given("a formula {string} with expression {string}") do |key, expr|
  @formula_key  = key
  @formula_expr = expr
end

Given("a row with {string} = {float}") do |col_key, value|
  @sample_row ||= {}
  @sample_row[col_key] = BigDecimal(value.to_s)
end

When("I evaluate the formula against that row") do
  service = ReportBuilderFormulaService.new([
    { "key" => @formula_key, "label" => "Test", "expression" => @formula_expr }
  ])
  @evaluated_row = service.evaluate(@sample_row.dup)
end

When("I validate the formula expression {string}") do |expr|
  @validation_result = ReportBuilderFormulaService.validate(expr, @sample_row || {})
end

Then("the evaluated row should have {string} equal to {float}") do |key, expected|
  expect(@evaluated_row[key].to_f).to be_within(0.001).of(expected)
end

Then("the evaluated row should have {string} equal to nil") do |key|
  expect(@evaluated_row[key]).to be_nil
end

Then("the formula validation should pass") do
  expect(@validation_result).to eq(true)
end

Then("the formula validation should fail with an error") do
  expect(@validation_result).to be_a(String)
  expect(@validation_result).not_to be_empty
end

# ─────────────────────────────────────────────────────────────────────────────
# Scheduling steps
# ─────────────────────────────────────────────────────────────────────────────

Given("a report builder report exists for the entity") do
  @report = build_report(entity: @entity, user: @user, root_model: "Investor")
end

Given("a {string} schedule with last_run_at {string}") do |frequency, time_desc|
  last_run_at = case time_desc
                when "nil"       then nil
                when "2 days ago" then 2.days.ago
                when "yesterday" then 1.day.ago
                when "today before 9am" then Time.current.beginning_of_day + 8.hours
                when "today after 9am"  then Time.current.beginning_of_day + 10.hours
                when "this Monday after 9am" then Time.current.beginning_of_week(:monday) + 10.hours
                when "last Monday"      then 1.week.ago.beginning_of_week(:monday) + 10.hours
                when "this 1st after 9am" then Time.current.beginning_of_month + 10.hours
                when "last month 1st"   then 1.month.ago.beginning_of_month + 10.hours
                else raise "Unknown time_desc: #{time_desc}"
                end

  @schedule = ReportSchedule.create!(
    report:      @report,
    frequency:   frequency,
    recipients:  ["test@example.com"],
    active:      true,
    last_run_at: last_run_at
  )
end

When("I check if the schedule is due") do
  job = ReportBuilderSchedulerJob.new
  @schedule_due = job.send(:due?, @schedule)
end

Then("the schedule should be due") do
  expect(@schedule_due).to be true
end

Then("the schedule should not be due") do
  expect(@schedule_due).to be false
end

# ─────────────────────────────────────────────────────────────────────────────
# Controller / API steps (via Integration::Session — no browser)
# ─────────────────────────────────────────────────────────────────────────────

Given("I am signed in as the report builder user") do
  rb_sign_in(@user)
end

When("I request the models endpoint") do
  rb_get "/report_builder/models"
end

When("I request the associations endpoint for {string}") do |model_name|
  rb_get "/report_builder/associations", params: { model: model_name }
end

When("I create a new report for root model {string}") do |root_model|
  rb_post "/report_builder", params: { root_model: root_model }
  @last_rb_response = rb_session.response
  # Follow redirect to edit page
  rb_session.follow_redirect! if @last_rb_response.redirect?
  @created_report = Report.order(:created_at).last
end

When("I add the column {string} to the report") do |col_key|
  rb_session.post "/report_builder/#{@created_report.id}/columns",
                  params: { key: col_key, name: col_key.humanize }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

When("I update the aggregate for {string} to {string}") do |col_key, agg|
  rb_patch "/report_builder/#{@created_report.id}/aggregate",
           params: { key: col_key, aggregate: agg }
end

When("I update the report name to {string}") do |name|
  rb_patch "/report_builder/#{@created_report.id}/name", params: { name: name }
end

When("I add the join {string} with model {string} to the report") do |relation, model|
  rb_session.post "/report_builder/#{@created_report.id}/join",
                  params: { relation: relation, model: model, fk: "investor_id" }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

When("I remove the join {string} from the report") do |relation|
  rb_session.delete "/report_builder/#{@created_report.id}/join",
                    params: { relation: relation }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

When("I validate the formula {string} via the API") do |expr|
  rb_post "/report_builder/#{@created_report.id}/validate_formula",
          params: { expression: expr }
end

When("I add the formula with expression {string} and label {string}") do |expr, label|
  rb_session.post "/report_builder/#{@created_report.id}/formulas",
                  params: { expression: expr, label: label }
  rb_session.follow_redirect! if rb_session.response.redirect?
end

When("I configure the schedule with frequency {string} and recipient {string}") do |freq, email|
  rb_patch "/report_builder/#{@created_report.id}/schedule",
           params: { frequency: freq, recipients: email, active: "true" }
end

When("I request the preview for the report") do
  rb_get "/report_builder/#{@created_report.id}/preview"
end

Then("the API response should be {int}") do |status|
  expect(@last_rb_response.status).to eq(status)
end

Then("the report builder API response should be successful") do
  expect(@last_rb_response.status).to be_between(200, 299)
end

Then("the API JSON should have key {string}") do |key|
  expect(last_rb_json).to have_key(key)
end

Then("the API JSON {string} should be {string}") do |key, value|
  expect(last_rb_json[key].to_s).to eq(value)
end

Then("a report should be created with root model {string}") do |root_model|
  report = Report.order(:created_at).last
  expect(report).not_to be_nil
  expect(report.template["root_model"]).to eq(root_model)
  expect(report.report_builder).to be true
end

Then("the report should have column {string}") do |col_key|
  @created_report.reload
  expect(@created_report.grid_view_preferences.pluck(:key)).to include(col_key)
end

Then("the report should not have column {string}") do |col_key|
  @created_report.reload
  expect(@created_report.grid_view_preferences.pluck(:key)).not_to include(col_key)
end

Then("the report template aggregate for {string} should be {string}") do |col, agg|
  @created_report.reload
  expect(@created_report.template.dig("aggregates", col)).to eq(agg)
end

Then("the report name should be {string}") do |name|
  @created_report.reload
  expect(@created_report.name).to eq(name)
end

Then("the report template should include join {string}") do |relation|
  @created_report.reload
  relations = (@created_report.template["joins"] || []).map { |j| j["relation"] }
  expect(relations).to include(relation)
end

Then("the report template should not include join {string}") do |relation|
  @created_report.reload
  relations = (@created_report.template["joins"] || []).map { |j| j["relation"] }
  expect(relations).not_to include(relation)
end

Then("a ReportSchedule should exist for the report") do
  @created_report.reload
  expect(@created_report.report_schedule).not_to be_nil
end

Then("the ReportSchedule frequency should be {string}") do |freq|
  expect(@created_report.report_schedule.frequency).to eq(freq)
end

Then("the models list should include {string}") do |model_name|
  models = last_rb_json
  names  = models.map { |m| m["name"] }
  expect(names).to include(model_name)
end

Then("the associations list should not be empty in the response") do
  expect(last_rb_json).not_to be_empty
end

# ─────────────────────────────────────────────────────────────────────────────
# Security steps
# ─────────────────────────────────────────────────────────────────────────────

Given("the report has selected column {string}") do |col_key|
  @created_report ||= @report
  (@created_report || @report).grid_view_preferences.find_or_create_by!(
    key:       col_key,
    entity_id: @entity.id
  ) do |gvp|
    gvp.name     = col_key.humanize
    gvp.label    = col_key.humanize
    gvp.sequence = (@created_report || @report).grid_view_preferences.count + 1
  end
end

Then("the formula validation API response should indicate success") do
  expect(last_rb_json["ok"]).to be true
end

Then("the formula validation API response should indicate failure") do
  expect(last_rb_json["ok"]).to be false
  expect(last_rb_json["error"]).to be_present
end

Then("the formula validation error should mention {string}") do |text|
  expect(last_rb_json["error"]).to include(text)
end

# ─────────────────────────────────────────────────────────────────────────────
# Mailer steps
# ─────────────────────────────────────────────────────────────────────────────

Given("the email queue is empty") do
  ActionMailer::Base.deliveries.clear
end

When("the scheduled report mailer is sent for the report") do
  @report ||= @created_report
  Dir::Tmpname.create(["report_builder_test", ".xlsx"]) do |path|
    File.binwrite(path, "FAKE_XLSX_CONTENT")
    ReportMailer.scheduled_report(@report, ["recipient@example.com"], path).deliver_now
  end
end

Then("an email should be delivered") do
  expect(ActionMailer::Base.deliveries).not_to be_empty
end

Then("the delivered email subject should include {string}") do |text|
  mail = ActionMailer::Base.deliveries.last
  expect(mail.subject).to include(text)
end

Then("the delivered email should have an attachment") do
  mail = ActionMailer::Base.deliveries.last
  expect(mail.attachments).not_to be_empty
end

Then("the delivered email HTML body should include {string}") do |text|
  mail = ActionMailer::Base.deliveries.last
  html_part = mail.html_part&.body&.to_s || mail.body.to_s
  expect(html_part).to include(text)
end

Then("the delivered email text body should include {string}") do |text|
  mail = ActionMailer::Base.deliveries.last
  text_part = mail.text_part&.body&.to_s || mail.body.to_s
  expect(text_part).to include(text)
end
