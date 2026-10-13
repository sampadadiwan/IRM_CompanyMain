
# ── Setup steps ──────────────────────────────────────────────────────────────

Given('the form type has a filterable text field {string} labelled {string}') do |name, label|
  fcf = @form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  fcf.assign_attributes(field_type: "TextField", label: label, filter_in_search: true, position: (fcf.position || @form_type.form_custom_fields.count + 1))
  fcf.save!
end

Given('the form type has a filterable select field {string} labelled {string} with options {string}') do |name, label, options|
  fcf = @form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  fcf.assign_attributes(field_type: "Select", label: label, meta_data: options, filter_in_search: true, position: (fcf.position || @form_type.form_custom_fields.count + 1))
  fcf.save!
end

Given('the form type has a filterable date field {string} labelled {string}') do |name, label|
  fcf = @form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  fcf.assign_attributes(field_type: "DateField", label: label, filter_in_search: true, position: (fcf.position || @form_type.form_custom_fields.count + 1))
  fcf.save!
end

Given('the form type has a non-filterable {string} field {string} labelled {string}') do |field_type, name, label|
  # force filter_in_search true to verify the filterable scope excludes it anyway
  fcf = @form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  fcf.assign_attributes(field_type: field_type, label: label, filter_in_search: true, position: (fcf.position || @form_type.form_custom_fields.count + 1))
  # skip_cf_before_save needed for Calculation which requires meta_data kosher check
  fcf.meta_data = "x" if field_type == "Calculation"
  fcf.save(validate: false)
end

Given('there is a second FormType {string}') do |args|
  form_type = FormType.new(entity_id: @entity.id)
  key_values(form_type, args)
  @second_form_type = @entity.form_types.where(name: form_type.name, tag: form_type.tag).first_or_initialize
  key_values(@second_form_type, args)
  @second_form_type.save!
end

Given('the second form type has a filterable text field {string} labelled {string}') do |name, label|
  fcf = @second_form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  fcf.assign_attributes(field_type: "TextField", label: label, filter_in_search: true, position: (fcf.position || @second_form_type.form_custom_fields.count + 1))
  fcf.save!
end

Given('there is an existing fund {string}') do |args|
  # Use USD so committed amounts format as "100,000" rather than INR lakh style "1,00,000"
  @fund = FactoryBot.build(:fund, entity: @entity, currency: "USD")
  key_values(@fund, args)
  @fund.save!
end

Given('there is an existing capital commitment {string} for {string} and {string}') do |args, fund_name, _investor_name|
  fund     = @entity.funds.find_by!(name: fund_name)
  investor = @investor  # set by "there is an existing investor" step
  cc       = FactoryBot.build(:capital_commitment, entity: @entity, fund: fund, investor: investor, folio_id: SecureRandom.hex(4), unit_type: fund.unit_types.split(",").first&.strip, folio_currency: fund.currency)

  attrs = {}
  json_fields = {}
  args.split(";").each do |pair|
    # Pairs use "=" as separator (e.g. "committed_amount=100000").
    # json_fields pairs carry an inner ":" separator for the field value
    # (e.g. "json_fields=source_of_funds:Savings").
    k, v = pair.split("=", 2)
    next unless k && v
    if k.strip == "json_fields"
      jk, jv = v.split(":", 2)
      json_fields[jk.strip] = jv&.strip
    else
      attrs[k.strip] = v.strip
    end
  end

  if attrs["committed_amount"]
    amount_cents = (attrs["committed_amount"].to_d * 100).to_i
    cc.folio_committed_amount_cents = amount_cents
    # committed_amount_cents is normally set by the CapitalCommitmentCreate service pipeline
    # (set_orig_amounts → set_committed_amount). Since tests bypass that pipeline via
    # FactoryBot, set it directly here so the "Committed" column displays correctly.
    cc.committed_amount_cents = amount_cents
  end

  cc.skip_cf_before_save = true
  cc.json_fields = json_fields if json_fields.any?
  cc.save!
  @capital_commitment = cc
end

# ── Navigation steps ──────────────────────────────────────────────────────────

When('I visit the capital commitments index with filter open') do
  visit(capital_commitments_path(filter: true))
end

# ── Filter action steps ───────────────────────────────────────────────────────

# Filterable custom fields are registered as Ransack named ransackers, per company, by
# WithCustomFieldFilter#load_filterable_custom_fields; the filter params use the field
# name directly (e.g. q[source_of_funds_cont]).

When('I filter capital commitments by {string} contains {string}') do |field_name, value|
  # Use named ransacker params — the before_action registers the named ransacker,
  # then Ransack uses it directly.
  visit(capital_commitments_path(q: {"#{field_name}_cont" => value}))
end

When('I filter capital commitments by {string} equals {string}') do |field_name, value|
  visit(capital_commitments_path(q: {"#{field_name}_eq" => value}))
end

When('I filter capital commitments by {string} from {string} to {string}') do |field_name, from_val, to_val|
  q_params = {}
  q_params["#{field_name}_gteq"] = from_val if from_val.present?
  q_params["#{field_name}_lteq"] = to_val if to_val.present?
  visit(capital_commitments_path(q: q_params))
end

# ── Assertion steps ───────────────────────────────────────────────────────────

# Filterable custom fields appear as options in the Ransack attribute select
# dropdown (name contains "[a][0][name]"). visible: false is required because
# select options are not visually rendered when their parent select is closed.

Then('I should see a filter row labelled {string}') do |label|
  # Ransack renders the option VALUE as the ransacker name (underscored field name),
  # not the FCF label text — check the value attribute instead of display text.
  field_name = label.parameterize(separator: '_')
  expect(page).to have_css("select[name*='a][0][name]'] option[value='#{field_name}']", visible: false)
end

Then('I should not see a filter row labelled {string}') do |label|
  field_name = label.parameterize(separator: '_')
  expect(page).not_to have_css("select[name*='a][0][name]'] option[value='#{field_name}']", visible: false)
end

Then('I should see exactly {string} filter row labelled {string}') do |count, label|
  field_name = label.parameterize(separator: '_')
  expect(page).to have_css("select[name*='a][0][name]'] option[value='#{field_name}']", count: count.to_i, visible: false)
end

Then('I should see {string} capital commitment in the results') do |count|
  expect(page).to have_css("table tbody tr", count: count.to_i, wait: 5)
end

Then('the result should contain committed amount {string}') do |amount|
  expect(page).to have_content(amount)
end

Then('the result should not contain committed amount {string}') do |amount|
  expect(page).not_to have_content(amount)
end

# ── Number fields and cross-company isolation (fix-custom-field-filter-scoping) ──────────────────
# Worked examples H1, E1–E3, X1 in openspec/changes/fix-custom-field-filter-scoping/report.md

Given('the form type has a filterable number field {string} labelled {string}') do |name, label|
  fcf = @form_type.form_custom_fields.find_or_initialize_by(name: FormCustomField.to_name(name))
  position = fcf.position || (@form_type.form_custom_fields.count + 1)
  fcf.assign_attributes(field_type: "NumberField", label:, filter_in_search: true, position:)
  fcf.save!
end

# A second company with its own filterable field on its commitment form, whose user then opens the
# capital commitments filter in a separate browser session — as another tenant's request would, on
# the same server process. @user / @entity are restored afterwards.
Given('another company has a filterable {string} field {string} labelled {string} and its user has opened the commitments filter') do |field_type, name, label|
  me = @user
  my_entity = @entity
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  other_entity.permissions.set(:enable_funds)
  other_entity.save!(validate: false)
  form_type = FormType.find_or_create_by!(entity: other_entity, name: "CapitalCommitment", tag: "Default")
  FormCustomField.create!(form_type:, name: FormCustomField.to_name(name), label:, field_type:, filter_in_search: true, position: 1)
  @user = FactoryBot.create(:user, entity: other_entity)
  @user.add_role(:company_admin)
  Capybara.using_session(:other_company) do
    steps %(
      And I am signed in as the current user
    )
    visit capital_commitments_path(filter: true)
    expect(page).to have_css("select[name*='a][0][name]'] option[value='#{FormCustomField.to_name(name)}']", visible: false)
  end
ensure
  @user = me
  @entity = my_entity
end

When('I filter capital commitments by {string} greater than {string}') do |field_name, value|
  visit(capital_commitments_path(q: { "#{field_name}_gt" => value }))
end

When('the field {string} is no longer shown in filters') do |name|
  @form_type.form_custom_fields.find_by!(name: FormCustomField.to_name(name)).update!(filter_in_search: false)
end

# Background work (jobs, MCP, console) has no signed-in user: no custom-field filter names apply
Then('without a signed-in user the commitment search fields should not include {string}') do |name|
  Current.set(user: nil) do
    expect(CapitalCommitment.ransackable_attributes).not_to include(FormCustomField.to_name(name))
  end
end
