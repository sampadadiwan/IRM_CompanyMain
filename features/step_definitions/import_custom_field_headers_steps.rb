# Blank/nil labels are written with update_column: the model now fills in a blank label on create,
# but existing rows (created before that fix) still hold "" or nil, and the importer must handle them.
STORED_LABEL_PLACEHOLDERS = { "<blank>" => "", "<nil>" => nil }.freeze

Given('the form type has custom fields with stored labels') do |table|
  table.hashes.each do |row|
    fcf = @form_type.form_custom_fields.create!(name: row["name"], label: "placeholder", field_type: "TextField")
    stored = STORED_LABEL_PLACEHOLDERS.fetch(row["label"], row["label"])
    fcf.update_column(:label, stored)
  end
  @form_type.reload
end

Then('the import columns resolve to these custom fields') do |table|
  importer = ImportCapitalCommitment.new
  header_map = importer.send(:custom_field_header_map, @form_type)
  table.hashes.each do |row|
    header = importer.get_headers([row["column"].dup]).first
    resolved = header_map[importer.send(:custom_field_header_key, header)]
    expect(resolved&.name).to eq(row["field"]), "column #{row['column'].inspect} resolved to #{resolved&.name.inspect}"
  end
end

Then('the import column {string} does not resolve to a custom field') do |column|
  importer = ImportCapitalCommitment.new
  header = importer.get_headers([column.dup]).first
  expect(importer.send(:custom_field_header_map, @form_type)[importer.send(:custom_field_header_key, header)]).to be_nil
end

# pre_money_val is the discriminating case: the test-env fallback in setup_custom_fields would
# store "Pre-Money Valuation" under "pre_money_valuation" if the label lookup missed.
Then('importing the columns into a capital commitment stores them under the field names') do
  importer = ImportCapitalCommitment.new
  headers = importer.get_headers(["Carry From Kyc", "Udr 1", "Pre-Money Valuation", "Photo - Joint Holder"])
  user_data = headers.zip(%w[yes u1 100 photo]).to_h
  commitment = CapitalCommitment.new(entity_id: @entity.id)
  importer.send(:setup_custom_fields, user_data, commitment, headers.dup, form_type: @form_type)
  expect(commitment.json_fields).to include("carry_from_kyc" => "yes", "udr_1" => "u1", "pre_money_val" => "100", "joint_holder_photo" => "photo")
end

When('a custom field {string} is created with label {string}') do |name, label|
  @form_type.form_custom_fields.create!(name:, label:, field_type: "TextField")
end

When('a custom field {string} is created without a label') do |name|
  @form_type.form_custom_fields.create!(name:, field_type: "TextField")
end

Then('the custom field {string} has label {string}') do |name, label|
  expect(@form_type.form_custom_fields.find_by!(name:).label).to eq(label)
end
