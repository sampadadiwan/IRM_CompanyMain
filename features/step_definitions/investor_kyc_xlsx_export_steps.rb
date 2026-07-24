# Covers the investor_kycs/index.xlsx.axlsx export: custom fields must be cast to the
# right Excel cell type per field_type (DateField -> date, NumberField/Money -> numeric,
# MultiSelect -> joined text) instead of every value exporting as plain text.
#
# No Capybara/browser involved - the download is fetched via a plain HTTP session so the
# raw xlsx bytes can be read back with Roo and the cell types/values asserted directly.

require "tempfile"

Given('there is an IndividualKyc for the investor with custom field values {string}') do |args|
  form_type = @entity.form_types.find_by!(name: "IndividualKyc", tag: "Default")

  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor: @investor, kyc_type: "individual", form_type: form_type)

  args.split("|").each do |pair|
    label, value = pair.split(":", 2)
    fcf = form_type.form_custom_fields.find_by!(name: FormCustomField.to_name(label))
    @investor_kyc.properties[fcf.name] = fcf.field_type == "MultiSelect" ? value.split(",").map(&:strip) : value
  end

  @investor_kyc.save!
  puts "\n########### KYC for xlsx export test ############"
  puts @investor_kyc.to_json
end

When('I download the {string} xlsx export') do |form_type_name|
  form_type = @entity.form_types.find_by!(name: form_type_name, tag: "Default")

  @xlsx_session = ActionDispatch::Integration::Session.new(Rails.application)
  @xlsx_session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }

  @xlsx_session.get "/investor_kycs.xlsx", params: { form_type_name: form_type_name, form_type_id: form_type.id }
  expect(@xlsx_session.response.status).to eq(200)

  tempfile = Tempfile.new(["investor_kycs_export", ".xlsx"], binmode: true)
  tempfile.write(@xlsx_session.response.body)
  tempfile.rewind

  @export_sheet = Roo::Spreadsheet.open(tempfile.path)
end

Then('the exported xlsx custom field {string} should be a date cell with value {string}') do |header, expected|
  value = exported_custom_field_value(header)
  expect(value).to be_a(Date) # DateTime < Date, so this also covers a time-of-day component if Roo returns one
  expect(value.to_date).to eq(Date.parse(expected))
end

Then('the exported xlsx custom field {string} should be a numeric cell with value {string}') do |header, expected|
  value = exported_custom_field_value(header)
  expect(value).to be_a(Numeric)
  expect(value.to_f).to eq(expected.to_f)
end

Then('the exported xlsx custom field {string} should be the text {string}') do |header, expected|
  value = exported_custom_field_value(header)
  expect(value.to_s).to eq(expected)
end

def exported_custom_field_column(header)
  headers = @export_sheet.row(1)
  col = headers.index(header)
  raise "Column '#{header}' not found among exported headers: #{headers.inspect}" unless col

  col
end

def exported_custom_field_value(header)
  @export_sheet.row(2)[exported_custom_field_column(header)]
end
