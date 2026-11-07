# Steps for changing a record type's custom fields from a record's page (the custom fields side panel).
# openspec/changes/grid-columns-inline-settings/business-rules.md#3-custom-fields-on-record-pages--phase-4
# Reuses: 'Im logged in as a user …', 'the user has role …', 'there is an investor named …', 'the investor {string}
# has {string} set to {string}', 'I am acting as an investor', 'I press Escape', 'a saved message should say …',
# 'I am signed in as a plain employee of my firm' (grid_columns_inline_settings_steps.rb).

module CustomFieldsPanelSteps
  def cfp_form_type(model_name = "Investor", tag: nil)
    scope = FormType.where(entity: @entity, name: model_name)
    scope = scope.where(tag:) if tag
    scope.order(:id).first
  end

  # Field names of a form type in form order (regulatory ones included when asked)
  def cfp_names(form_type, with_regulatory: false)
    scope = form_type.form_custom_fields.reload
    scope = scope.not_regulatory unless with_regulatory
    scope.order(:position).pluck(:name)
  end

  def cfp_field(name, form_type = cfp_form_type)
    form_type.form_custom_fields.reload.find_by!(name:)
  end

  def cfp_panel
    find(".form-type-fields-panel.show")
  end

  def cfp_row_xpath(name)
    "//li[@data-form-type-fields-row][@data-name='#{name}']"
  end

  def cfp_row(name)
    cfp_panel.find(:xpath, ".#{cfp_row_xpath(name)}")
  end

  def cfp_labels
    cfp_panel.all("[data-form-type-fields-row] [data-form-type-fields-label]").map(&:value)
  end

  def cfp_token_params(record)
    { record_type: record.class.name, record_id: record.id }
  end
end
World(CustomFieldsPanelSteps)

# --- Setup ------------------------------------------------------------------------------------------------------

Given("my firm's {string} form type has the fields:") do |model_name, table|
  form_type = cfp_form_type(model_name) || FormType.create!(entity: @entity, name: model_name)
  # Positions continue after the form type's last field
  start = form_type.form_custom_fields.maximum(:position).to_i + 1
  table.hashes.each.with_index(start) do |row, position|
    FormCustomField.create!(form_type:, name: row["name"], label: row["label"], field_type: row["type"], position:,
                            meta_data: row["meta"].to_s, required: row["flags"].to_s.include?("required"),
                            internal: row["flags"].to_s.include?("internal"), read_only: row["flags"].to_s.include?("read_only"),
                            reg_env: row["reg_env"].presence)
  end
end

Given("the investor {string} is on my firm's {string} form type") do |investor_name, model_name|
  investor = Investor.find_by!(investor_name:)
  investor.update_column(:form_type_id, cfp_form_type(model_name).id) # rubocop:disable Rails/SkipsModelValidations
end

Given("the investor {string} has no form type") do |investor_name|
  Investor.find_by!(investor_name:).update_column(:form_type_id, nil) # rubocop:disable Rails/SkipsModelValidations
end

Given("my firm has no {string} form type and a valuation with none") do |model_name|
  FormType.where(entity: @entity, name: model_name).destroy_all
  company = FactoryBot.create(:investor, entity: @entity, investor_entity: FactoryBot.create(:entity, entity_type: "Company"),
                                         investor_name: "Acme Robotics", category: "Portfolio Company")
  instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: company, name: "Series A")
  @cfp_valuation = FactoryBot.create(:valuation, entity: @entity, owner: company, investment_instrument: instrument)
  @cfp_valuation.update_column(:form_type_id, nil) # rubocop:disable Rails/SkipsModelValidations
end

Given("I am CapHive support") do
  @user.add_role(:support)
end

Given("a commitment of {string} on my firm's {string} form type tagged {string}") do |investor_name, model_name, tag|
  form_type = FormType.find_by!(entity: @entity, name: model_name, tag:)
  fund = FactoryBot.create(:fund, entity: @entity, name: "Growth Fund I")
  investor = Investor.find_by!(investor_name:)
  @cfp_commitment = FactoryBot.create(:capital_commitment, fund:, entity: @entity, investor:)
  @cfp_commitment.update_column(:form_type_id, form_type.id) # rubocop:disable Rails/SkipsModelValidations
end

Given("an investment instrument with reporting fields") do
  company = FactoryBot.create(:investor, entity: @entity, investor_entity: FactoryBot.create(:entity, entity_type: "Company"),
                                         investor_name: "Acme Robotics", category: "Portfolio Company")
  @cfp_instrument = FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: company, name: "Series A")
end

Given("another firm has an investor {string}") do |name|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital #{SecureRandom.hex(2)}")
  @cfp_other_investor = FactoryBot.create(:investor, entity: other, investor_entity: FactoryBot.create(:entity, entity_type: "Investor"),
                                                     investor_name: name)
  @cfp_other_form_type = FormType.create!(entity: other, name: "Investor")
  FormCustomField.create!(form_type: @cfp_other_form_type, name: "tier", label: "Tier", field_type: "TextField")
  @cfp_other_investor.update_column(:form_type_id, @cfp_other_form_type.id) # rubocop:disable Rails/SkipsModelValidations
end

# --- Pages and the panel ----------------------------------------------------------------------------------------

When("I open the page of the investor {string}") do |investor_name|
  visit investor_path(Investor.find_by!(investor_name:))
end

When("I open the page of the valuation") do
  visit valuation_path(@cfp_valuation)
end

When("I open the page of the commitment") do
  visit capital_commitment_path(@cfp_commitment)
end

When("I open the page of the investment instrument") do
  visit investment_instrument_path(@cfp_instrument)
end

# D13 — beside the card's minimize button, or in the breadcrumb bar
Then("the details card should have the custom fields icon") do
  expect(page).to have_css(".card-header .form-type-fields-btn, .breadcrumbs .form-type-fields-btn, .grid-columns-host > .form-type-fields-btn",
                           visible: :all, wait: 20)
end

Then("there should be no custom fields icon") do
  expect(page).to have_no_css(".form-type-fields-btn", visible: :all)
end

Then("the reporting fields card should have no custom fields icon") do
  card = find(:xpath, "//div[contains(@class,'card')][.//div[contains(@class,'show_reporting_fields')]]", visible: :all, match: :first)
  expect(card).to have_no_css(".form-type-fields-btn", visible: :all)
end

When("I open the custom fields panel") do
  find(".form-type-fields-btn", visible: :all, wait: 20).click
  expect(page).to have_css(".form-type-fields-panel.show [data-form-type-fields-form-target='list']", wait: 30)
end

Then("the fields panel should be titled {string}") do |title|
  expect(cfp_panel.find(".offcanvas-title").text.squish).to eq(title)
end

Then("the fields panel should list {string}") do |labels|
  expect(cfp_labels).to eq(labels.split(",").map(&:strip))
end

Then("the fields panel should not list {string}") do |label|
  expect(cfp_labels).not_to include(label)
end

Then("the field {string} should be locked for me") do |name|
  row = cfp_row(name)
  expect(row["data-locked"]).to eq("true")
  expect(row).to have_text("Support")
  expect(row).to have_no_css(".form-type-fields-flag, .grid-columns-remove")
end

When("I move the field {string} above {string}") do |name, other|
  cfp_row(name)
  page.driver.with_playwright_page do |pw|
    pw.locator("xpath=#{cfp_row_xpath(name)}").drag_to(pw.locator("xpath=#{cfp_row_xpath(other)}"), targetPosition: { x: 40, y: 3 })
  end
end

When("I rename the field {string} to {string}") do |name, label|
  cfp_row(name).find("[data-form-type-fields-label]").fill_in(with: label)
end

When("I switch {string} on for the field {string}") do |flag, name|
  key = { "Required" => "required", "Read only" => "read_only", "Internal" => "internal" }.fetch(flag)
  cfp_row(name).find(".form-type-fields-flag[data-flag='#{key}']").click
end

When("I set the help text of the field {string} to {string}") do |name, text|
  row = cfp_row(name)
  row.find("[data-action='form-type-fields-form#toggleDetails']").click
  row.find("[data-form-type-fields-help]").fill_in(with: text)
end

When("I add the field {string} of type {string}") do |label, type|
  step %(I add the field "#{label}" of type "#{type}" with options "")
end

When("I add the field {string} of type {string} with options {string}") do |label, type, options|
  cfp_panel.find("[data-form-type-fields-form-target='newLabel']").fill_in(with: label)
  cfp_panel.find("[data-form-type-fields-form-target='newType']").select(type)
  cfp_panel.find("[data-form-type-fields-form-target='newOptions']").fill_in(with: options) if options.present?
  cfp_panel.find("[data-form-type-fields-add]").click
end

When("I click Add with an empty label") do
  cfp_panel.find("[data-form-type-fields-form-target='newLabel']").fill_in(with: "")
  cfp_panel.find("[data-form-type-fields-add]").click
end

When("I remove the field {string}") do |name|
  cfp_row(name).find(".grid-columns-remove").click
end

Then("the panel should warn that removed fields keep their values") do
  expect(cfp_panel).to have_css("[data-form-type-fields-remove-note]:not(.d-none)",
                                text: "Removed fields disappear from forms and pages; values already entered stay stored.")
end

When("I save the fields") do
  cfp_panel.find("[data-form-type-fields-save]").click
end

When("I click Save twice quickly") do
  button = cfp_panel.find("[data-form-type-fields-save]")
  button.click
  button.click rescue nil # the button is disabled after the first click (E22)
end

Then("the fields panel should close") do
  expect(page).to have_no_css(".form-type-fields-panel.show", wait: 30)
end

Then("the fields panel should say {string}") do |message|
  expect(page).to have_css("[data-form-type-fields-errors]", text: message, wait: 20)
end

Then("the fields panel should still list {int} fields") do |count|
  expect(cfp_panel.all("[data-form-type-fields-row]").size).to eq(count)
end

# --- Saved state ------------------------------------------------------------------------------------------------

Then("my firm's {string} fields should be {string}") do |model_name, names|
  gcs_eventually { cfp_names(cfp_form_type(model_name)) == names.split(",").map(&:strip) }
end

Then("my firm's {string} fields including regulatory ones should be {string}") do |model_name, names|
  gcs_eventually { cfp_names(cfp_form_type(model_name), with_regulatory: true) == names.split(",").map(&:strip) }
end

Then("the field {string} should have label {string}") do |name, label|
  gcs_eventually { cfp_field(name).label == label }
end

Then("the field {string} should be required, read only {string}, internal {string}, help text {string}") do |name, read_only, internal, help|
  field = cfp_field(name)
  expect([field.required, field.read_only, field.internal, field.help_text.to_s])
    .to eq([true, read_only == "yes", internal == "yes", help])
end

Then("the field {string} should be a {string} with options {string}") do |name, type, options|
  gcs_eventually { (f = cfp_form_type.form_custom_fields.reload.find_by(name:)) && f.field_type == type && f.meta_data == options }
end

Then("the field {string} should keep type {string} and meta {string}") do |name, type, meta|
  field = cfp_field(name)
  expect([field.field_type, field.meta_data.to_s]).to eq([type, meta])
end

Then("the investor {string} should still have {string} = {string}") do |investor_name, field, value|
  expect(Investor.find_by!(investor_name:).reload.json_fields[field]).to eq(value)
end

Then("the investor {string} should be on my firm's {string} form type") do |investor_name, model_name|
  gcs_eventually { Investor.find_by!(investor_name:).reload.form_type_id == cfp_form_type(model_name).id }
end

Then("my firm should have a {string} form type with the field {string}, linked to the valuation") do |model_name, name|
  gcs_eventually do
    (ft = cfp_form_type(model_name)) && ft.form_custom_fields.exists?(name:) && @cfp_valuation.reload.form_type_id == ft.id
  end
end

Then("the {string} form type tagged {string} should have the field {string}") do |model_name, tag, name|
  gcs_eventually { cfp_form_type(model_name, tag:).form_custom_fields.reload.exists?(name:) }
end

Then("the {string} form type tagged {string} should not have the field {string}") do |model_name, tag, name|
  expect(cfp_form_type(model_name, tag:).form_custom_fields.reload.exists?(name:)).to be false
end

Then("my firm's {string} form type should have exactly one field named {string}") do |model_name, name|
  gcs_eventually { cfp_form_type(model_name).form_custom_fields.reload.where(name:).count == 1 }
end

When("someone else removes the field {string}") do |name|
  cfp_field(name).destroy!
end

Then("the edit form of the investor {string} should offer {string}") do |investor_name, label|
  visit edit_investor_path(Investor.find_by!(investor_name:))
  expect(page).to have_text(label, wait: 20)
end

# --- Direct requests (rack_test) -------------------------------------------------------------------------------

When("I request the custom fields panel for the investor {string}") do |investor_name|
  gcs_request(:get, settings_form_type_fields_path(**cfp_token_params(Investor.find_by!(investor_name:))))
end

When("I request the custom fields panel for the other firm's investor") do
  gcs_request(:get, settings_form_type_fields_path(**cfp_token_params(@cfp_other_investor)))
end

When("I request the custom fields panel for the record type {string}") do |type|
  gcs_request(:get, settings_form_type_fields_path(record_type: type, record_id: 1))
end

When("I save the fields {string} directly for the investor {string}") do |json, investor_name|
  investor = Investor.find_by!(investor_name:)
  fields = json.gsub(/\{id:(\w+)\}/) { cfp_field(Regexp.last_match(1)).id.to_s }
  gcs_request(:patch, save_form_type_fields_path, cfp_token_params(investor).merge(fields:))
end

When("I save a new field directly for the other firm's investor") do
  gcs_request(:patch, save_form_type_fields_path, cfp_token_params(@cfp_other_investor).merge(fields: [{ label: "Planted", field_type: "TextField" }].to_json))
end

When("I save the fields of the investor {string} directly with extra fields") do |investor_name|
  investor = Investor.find_by!(investor_name:)
  risk = cfp_field("risk_rating")
  fields = [{ id: risk.id, label: "Risk", condition_on: "kyc_due", meta_data: "Low", name: "planted", field_type: "Calculation" }].to_json
  gcs_request(:patch, save_form_type_fields_path, cfp_token_params(investor).merge(fields:, entity_id: 999, name: "Planted"))
end

Then("the fields request should be refused") do
  expect(page).to have_no_css(".grid-columns-editor")
  expect(page).to have_no_css("[data-form-type-fields-saved]", visible: :all)
end

Then("the other firm's form type should be unchanged") do
  expect(@cfp_other_form_type.form_custom_fields.reload.pluck(:name)).to eq(["tier"])
end

Then("the field {string} should be unchanged with label {string}") do |name, label|
  field = cfp_field(name)
  expect(field.label).to eq(label)
end

Then("only the label of {string} should have changed, to {string}") do |name, label|
  field = cfp_field(name)
  form_type = cfp_form_type
  expect([field.label, field.name, field.field_type, field.condition_on.to_s, field.meta_data.to_s])
    .to eq([label, name, "Select", "", "Low,Medium,High"])
  expect(form_type.reload.name).to eq("Investor")
  expect(form_type.entity_id).to eq(@entity.id)
end

# --- The form level (H21) ---------------------------------------------------------------------------------------

When("I open the edit form of the investor {string}") do |investor_name|
  visit edit_investor_path(Investor.find_by!(investor_name:))
end

Then("the form header should have the custom fields icon") do
  expect(page).to have_css(".form_card > .card-header .form-type-fields-btn", wait: 20)
end

Then("the fields panel should warn that saving refreshes the page") do
  expect(cfp_panel).to have_css("[data-form-type-fields-form-note]",
                                text: "Saving refreshes this page — anything typed in the form and not yet saved is lost.")
end
