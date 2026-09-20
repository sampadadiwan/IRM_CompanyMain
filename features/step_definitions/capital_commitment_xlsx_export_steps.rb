# Covers the capital_commitments/index.xlsx.axlsx export: a folio that came in through a
# feeder fund must name it, and the column is left out entirely when no exported folio has one.
#
# No Capybara/browser involved - the download is fetched via a plain HTTP session so the raw
# xlsx bytes can be read back with Roo, the same way investor_kyc_xlsx_export_steps.rb does.

require "tempfile"

When('I download the commitments xlsx export for the fund') do
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }

  session.get "/capital_commitments.xlsx", params: { fund_id: @fund.id, all: true }
  expect(session.response.status).to eq(200)

  tempfile = Tempfile.new(["capital_commitments_export", ".xlsx"], binmode: true)
  tempfile.write(session.response.body)
  tempfile.rewind

  @export_sheet = Roo::Spreadsheet.open(tempfile.path)
  puts "\n########### Commitments xlsx export ############"
  puts @export_sheet.row(1).inspect
end

# An empty expected value means the cell must be blank - the folio is a direct commitment.
Then('the commitments xlsx export must show feeder fund {string} for folio {string}') do |feeder_fund_name, folio_id|
  headers = @export_sheet.row(1)
  feeder_fund_column = headers.index("Feeder Fund")
  expect(feeder_fund_column).not_to be_nil, "Expected a Feeder Fund column, got #{headers.inspect}"

  row = exported_commitment_row(folio_id)
  expect(row[feeder_fund_column].to_s).to eq(feeder_fund_name)
end

Then('the commitments xlsx export must not have a feeder fund column') do
  expect(@export_sheet.row(1)).not_to include("Feeder Fund")
end

def exported_commitment_row(folio_id)
  headers = @export_sheet.row(1)
  folio_column = headers.index("Folio No")
  row = (2..@export_sheet.last_row).map { |r| @export_sheet.row(r) }.find { |r| r[folio_column].to_s == folio_id }
  expect(row).not_to be_nil, "No exported row for folio #{folio_id}"
  row
end
