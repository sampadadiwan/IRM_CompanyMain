
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
  @fund = FactoryBot.build(:fund, entity: @entity)
  key_values(@fund, args)
  @fund.save!
end

Given('there is an existing capital commitment {string} for {string} and {string}') do |args, fund_name, investor_name|
  fund     = @entity.funds.find_by!(name: fund_name)
  investor = @entity.investors.find_by!(name: investor_name)
  cc       = CapitalCommitment.new(entity: @entity, fund: fund, investor: investor, folio_id: SecureRandom.hex(4), unit_type: fund.unit_types.split(",").first&.strip || "Units", folio_currency: fund.currency)

  attrs = {}
  json_fields = {}
  args.split(";").each do |pair|
    k, v = pair.split(":", 2)
    next unless k && v
    if k.strip == "json_fields"
      # format: json_fields=key:value (only one k:v pair supported per arg; additional k:v pairs use separate json_fields= segments)
      jk, jv = v.split(":", 2)
      json_fields[jk.strip] = jv&.strip
    else
      attrs[k.strip] = v.strip
    end
  end

  # Map committed_amount (dollars) to folio_committed_amount_cents
  if attrs["committed_amount"]
    cc.folio_committed_amount_cents = (attrs["committed_amount"].to_d * 100).to_i
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

When('I filter capital commitments by {string} contains {string}') do |field_name, value|
  visit(capital_commitments_path(filter: true))
  fill_in("q[json_fields.#{field_name}_cont]", with: value)
  find(".search-button").click
end

When('I filter capital commitments by {string} equals {string}') do |field_name, value|
  visit(capital_commitments_path(filter: true))
  select(value, from: "q[json_fields.#{field_name}_eq]")
  find(".search-button").click
end

When('I filter capital commitments by {string} from {string} to {string}') do |field_name, from_val, to_val|
  visit(capital_commitments_path(filter: true))
  fill_in("q[json_fields.#{field_name}_gteq]", with: from_val) if from_val.present?
  fill_in("q[json_fields.#{field_name}_lteq]", with: to_val) if to_val.present?
  find(".search-button").click
end

# ── Assertion steps ───────────────────────────────────────────────────────────

Then('I should see a filter row labelled {string}') do |label|
  expect(page).to have_css(".fcf-filter-row input[value='#{label}']", visible: true)
end

Then('I should not see a filter row labelled {string}') do |label|
  expect(page).not_to have_css(".fcf-filter-row input[value='#{label}']", visible: true)
end

Then('I should see exactly {string} filter row labelled {string}') do |count, label|
  expect(page).to have_css(".fcf-filter-row input[value='#{label}']", count: count.to_i)
end

Then('I should see {string} capital commitment in the results') do |count|
  # Count visible rows in the results table, excluding header
  expect(page).to have_css("table tbody tr", count: count.to_i)
end

Then('the result should contain committed amount {string}') do |amount|
  expect(page).to have_content(amount)
end

Then('the result should not contain committed amount {string}') do |amount|
  expect(page).not_to have_content(amount)
end
