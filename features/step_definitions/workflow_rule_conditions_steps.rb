# Steps for the auto-assignment rule condition builder (workflow_rule_conditions*.feature): custom
# fields on the KYC forms, rules created with conditions, records created from a table, and what
# each record was given.
# Worked examples in openspec/changes/workflow-rule-condition-builder/design.md#worked-examples

# ── Setup ─────────────────────────────────────────────────────────────────────

# Adds the fields to every form type from "the entity has the KYC form types" whose label starts
# with the given kind ("Individual" → "Individual — Default", "Individual — Fund IV")
Given("the {string} KYC forms have the custom fields:") do |kind, table|
  forms = @kyc_form_types.select { |label, _| label.split("—").first.strip == kind }.values
  forms.each do |form_type|
    table.hashes.each do |row|
      FormCustomField.create!(form_type:, name: row["name"], label: row["label"], field_type: row["field_type"],
                              meta_data: row["meta_data"].presence, required: false)
    end
  end
end

Given("the template {string} is duplicated as {string}") do |name, copy_name|
  WorkflowTemplate.find_by!(entity: @entity, name:).duplicate!.update!(name: copy_name)
end

# Creates the rule through the model, so its conditions pass the same save checks as the form.
# "<form type: Individual — Fund IV>" in the JSON becomes that form type's id.
Given("a rule on {string} at priority {int} with conditions:") do |template_name, priority, json|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  conditions = JSON.parse(json.gsub(/<form type: ([^>]+)>/) { @kyc_form_types.fetch(Regexp.last_match(1).strip).id.to_s })
  @rule = WorkflowAutoAssignmentRule.create!(entity: @entity, workflow_template: template, created_by: @user,
                                             workflowable_type: template.workflowable_type, priority:,
                                             auto_launch: false, conditions:)
end

# ── Records ───────────────────────────────────────────────────────────────────

# Columns: kyc | form type | then any custom field names (blank cells are left out of json_fields)
When("these KYCs are created:") do |table|
  @records_by_name = table.hashes.to_h do |row|
    form_type = @kyc_form_types.fetch(row["form type"])
    custom = row.except("kyc", "form type").compact_blank
    attrs = FactoryBot.attributes_for(:investor_kyc, verified: false, completed_by_investor: false)
                      .except(:submission_status, :verified, :completed_by_investor)
    kyc_type = form_type.name == "IndividualKyc" ? "individual" : "non_individual"
    kyc = form_type.name.constantize.new(attrs.merge(entity: @entity, investor: @investor, kyc_type:, form_type:,
                                                     submission_status: "not_sent", json_fields: custom))
    kyc.save!(validate: false)
    [row["kyc"], kyc]
  end
end

# Columns: commitment | amount (in the fund's currency units)
When("these commitments are created:") do |table|
  @records_by_name = table.hashes.to_h do |row|
    commitment = FactoryBot.build(:capital_commitment, fund: @fund, investor: @investor,
                                                       orig_folio_committed_amount_cents: row["amount"].to_d * 100)
    expect(CapitalCommitmentCreate.call(capital_commitment: commitment)).to be_success
    [row["commitment"], commitment]
  end
end

# Columns: <record> | template ("none" = no template assigned)
Then("they should get the templates:") do |table|
  table.hashes.each do |row|
    name = row.values.first
    record = @records_by_name.fetch(name).reload
    actual = record.workflow_assignment&.workflow_template&.name || "none"
    expect(actual).to eq(row["template"]), "#{name}: got #{actual.inspect}"
  end
end

# ── Field list and search surface ─────────────────────────────────────────────

# What a KYC list filter request from another company leaves behind on the (process-wide) class
Given("another company's KYC list has registered the filter field {string} labelled {string}") do |name, label|
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  field = FormCustomField.new(name:, label:, field_type: "TextField")
  InvestorKyc.register_cf_ransackers(other_entity.id, [field])
end

Then("the rule fields for {string} should include {string}") do |type, labels|
  offered = WorkflowRuleFields.for(type, @entity).fields.map(&:label)
  labels.split(",").map(&:strip).each { |label| expect(offered).to include(label) }
end

Then("the rule fields for {string} should not include {string}") do |type, labels|
  offered = WorkflowRuleFields.for(type, @entity).fields.map(&:label)
  labels.split(",").map(&:strip).each { |label| expect(offered).not_to include(label) }
end

# List pages search without the :workflow_rule auth object, so a rule-only field is ignored there
Then("searching the KYC list with {string} for {string} should return every KYC") do |predicate, label|
  ids = InvestorKyc.where(entity: @entity).ransack(predicate => @kyc_form_types.fetch(label).id).result.pluck(:id)
  expect(ids).to match_array(InvestorKyc.where(entity: @entity).pluck(:id))
end

# ── Fail-closed guard ─────────────────────────────────────────────────────────

# Simulates Ransack dropping a condition (as it silently does for anything outside the allowlist):
# the matcher's query gets one key renamed to an attribute the model does not expose
Given("Ransack drops the rule's {string} condition") do |attribute|
  allow_any_instance_of(WorkflowRuleMatcher).to receive(:ransack_query).and_wrap_original do |original, *args|
    original.call(*args).transform_keys { |key| key.start_with?("#{attribute}_") ? key.sub(attribute, "#{attribute}_typo") : key }
  end
end

# Captures warn/error log lines written from here on (the test logger is not a broadcast logger)
Given("the log is being captured") do
  @captured_log = []
  %i[warn error].each do |level|
    allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
      @captured_log << args.first.to_s
      original.call(*args, &block)
    end
  end
end

Then("the log should mention {string}") do |text|
  expect(@captured_log.join("\n")).to include(text)
end

# ── Rule form (builder) ───────────────────────────────────────────────────────

When("I open a new rule for {string}") do |template_name|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  visit new_workflow_template_workflow_auto_assignment_rule_path(template)
  expect(page).to have_css("#add_rule_condition")
end

When("I edit the rule on {string}") do |template_name|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  rule = WorkflowAutoAssignmentRule.where(entity: @entity, workflow_template: template).order(:id).last
  visit edit_workflow_template_workflow_auto_assignment_rule_path(template, rule)
end

# Adds a row and fills it: field and operator by their labels; the value is picked from a dropdown
# when the value input is one, otherwise typed (comma-separated for "is one of")
When("I add the condition {string} {string} {string}") do |field, operator, value|
  find("#add_rule_condition").click
  row = all(".rule-condition").last
  row.find(".rule-field").select(field)
  row.find(".rule-operator").select(operator)
  next if value.blank?

  if row.has_css?("select.rule-value", wait: 0)
    value.split(",").map(&:strip).each { |v| row.find("select.rule-value").select(v) }
  elsif row.has_css?(".rule-date-display", wait: 0)
    row.find(".rule-date-display").fill_in(with: value)
  else
    row.find(".rule-value").fill_in(with: value)
  end
end

When("I set the rule priority to {int}") do |priority|
  fill_in "workflow_auto_assignment_rule_priority", with: priority
end

When("I toggle View as JSON") do
  find("#toggle_rule_conditions_json").click
end

When("I replace the conditions JSON with:") do |json|
  find("#toggle_rule_conditions_json").click if page.has_no_css?("#workflow_auto_assignment_rule_conditions_json", visible: true, wait: 0)
  fill_in "workflow_auto_assignment_rule_conditions_json", with: json.gsub(/<form type: ([^>]+)>/) { @kyc_form_types.fetch(Regexp.last_match(1).strip).id.to_s }
end

When("I change {string} to {string} in the conditions JSON") do |from, to|
  field = find("#workflow_auto_assignment_rule_conditions_json")
  field.fill_in(with: field.value.gsub(from, to))
end

When("I save the rule") do
  click_on "Save"
end

Then("the rule should be saved") do
  expect(page).to have_text(/Auto-assignment rule (created|updated)/)
end

Then("the rule should not be saved and the form should show {string}") do |message|
  expect(page).to have_css(".alert-danger", text: message)
  expect(page).to have_no_text(/Auto-assignment rule (created|updated)/)
end

Then("the field list on the rule form should include {string}") do |labels|
  find("#add_rule_condition").click
  offered = all(".rule-condition").last.all(".rule-field option").map(&:text)
  labels.split(",").map(&:strip).each { |label| expect(offered).to include(label) }
end

Then("the field list on the rule form should not include {string}") do |labels|
  offered = all(".rule-condition").last.all(".rule-field option").map(&:text)
  labels.split(",").map(&:strip).each { |label| expect(offered).not_to include(label) }
end

# Columns: field | operator | value — the rows as shown, in order
Then("the rule form should show the conditions:") do |table|
  rows = all(".rule-condition")
  expect(rows.size).to eq(table.hashes.size)
  table.hashes.each_with_index do |expected, i|
    row = rows[i]
    selected_text = ->(select) { select.all("option").select(&:selected?).map(&:text).join(", ") }
    expect(selected_text.call(row.find(".rule-field"))).to eq(expected["field"])
    expect(selected_text.call(row.find(".rule-operator"))).to eq(expected["operator"])
    value = if row.has_css?("select.rule-value", wait: 0) then selected_text.call(row.find("select.rule-value"))
            elsif row.has_css?(".rule-date-display", wait: 0) then row.find(".rule-date-display").value
            else row.find(".rule-value").value
            end
    expect(value).to eq(expected["value"])
  end
end

Then("the rule form should show the unknown field {string}") do |name|
  expect(page).to have_css(".rule-condition-unknown", text: "Unknown field: #{name}")
end

When("I remove the unknown condition") do
  find(".rule-condition-unknown .rule-remove").click
end

Then("the rule for {string} should have the stored conditions:") do |template_name, json|
  template = WorkflowTemplate.find_by!(entity: @entity, name: template_name)
  rule = WorkflowAutoAssignmentRule.where(entity: @entity, workflow_template: template).order(:id).last
  expected = JSON.parse(json.gsub(/<form type: ([^>]+)>/) { @kyc_form_types.fetch(Regexp.last_match(1).strip).id.to_s })
  expect(rule.conditions).to eq(expected)
end

Then("the rules table on {string} should read {string}") do |template_name, text|
  visit workflow_template_path(WorkflowTemplate.find_by!(entity: @entity, name: template_name))
  expect(page).to have_css(".rule-conditions-text", text:)
end

Given("the custom field {string} is deleted from the KYC forms") do |name|
  FormCustomField.where(form_type: @kyc_form_types.values, name:).destroy_all
end

Then("the KYC form type list on the rule form should be exactly {string}") do |labels|
  find("#add_rule_condition").click
  row = all(".rule-condition").last
  row.find(".rule-field").select("Form type")
  options = row.all("select.rule-value option").map(&:text).reject { |t| t == "Choose…" }
  expect(options.sort).to eq(labels.split(",").map(&:strip).sort)
end
