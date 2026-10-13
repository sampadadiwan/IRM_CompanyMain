# Steps for features/fund/capital_commitment_list_columns.feature

Given('the entity has saved commitment columns {string}') do |keys|
  # The entity's own commitment column choice (a FormType with grid view preferences)
  # The entity is set up with a default CapitalCommitment form type already (tag "Default" is unique per
  # entity), so reuse it and replace its columns rather than creating a second one
  form_type = FormType.find_or_create_by!(entity: @entity, name: "CapitalCommitment", tag: "Default")
  form_type.grid_view_preferences.destroy_all
  keys.split(",").each_with_index do |key, i|
    label = GridViewPreference.get_column_name(CapitalCommitment, key)
    form_type.grid_view_preferences.create!(key:, name: label, label:, sequence: i + 1, entity_id: @entity.id)
  end
end

When('the commitment columns are resolved for the {string}') do |page_name|
  # Same arguments the capital commitments _index partial passes for each page
  context = {
    "investor tab" => { investor_id: 1, fund_id: nil },
    "cross-fund index" => { investor_id: nil, fund_id: nil },
    "fund page" => { investor_id: nil, fund_id: 1 }
  }.fetch(page_name)
  rules = CapitalCommitment.list_column_rules(**context, investor_user: false)
  @header = RansackTableHeader.new(CapitalCommitment, q: nil, turbo_frame: "capital_commitments_frame", entity: @entity, current_user: @user, referrer: page_name, **rules)
end

Then('the commitment columns should be {string}') do |keys|
  expected = keys.split(",")
  # Table view
  expect(@header.columns.values.map { |v| v.split(";").first.strip }).to eq(expected)
  # AG Grid view
  expect(@header.ag_selected_columns.map { |c| c.with_indifferent_access[:key] }).to eq(expected)
end
