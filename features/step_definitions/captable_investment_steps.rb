# Step definitions for the Investment subgroup / instrument changes to the cap table
# (openspec/changes/investment-subgroups-and-captable-actions):
#   - Investment#subgroup on the form, show page, Ransack filter and ImportInvestment
#   - GenerateCapTable / GenerateHorizontalCapTable splitting rows per instrument and category
#   - which upload/view/download buttons the cap table page shows for a portfolio company
#   - the investments.xlsx and shareholder_positions.xlsx sample upload files
#
# Rows for the generic investments / shareholder positions tables come from
# "there are the following investments for" (investment.rb) and
# "there are the following shareholder positions for" (shareholder_position_steps.rb).

# Compares a record's attributes against a vertical Cucumber table. Numeric-looking
# expectations are compared as floats (decimal columns round-trip as "15.0"), blank
# expectations mean the attribute must be blank, anything else is a plain string compare.
def expect_record_attributes(record, table)
  table.rows_hash.each do |field, expected|
    actual = record.public_send(field.to_sym)
    if expected.blank?
      expect(actual).to be_blank, "expected #{field} to be blank but was #{actual.inspect}"
    elsif expected.match?(/\A-?\d+(\.\d+)?\z/) && actual.is_a?(Numeric)
      expect(actual.to_f).to eq(expected.to_f), "expected #{field} to be #{expected} but was #{actual}"
    else
      expect(actual.to_s).to eq(expected), "expected #{field} to be #{expected.inspect} but was #{actual.to_s.inspect}"
    end
  end
end

# Matches a displayed cell against an expectation, comparing numbers (and percentages) as floats
# so "985" matches the "985.0" the cap table renders.
def cap_table_cell_matches?(actual, expected)
  numeric = /\A-?[\d,]+(\.\d+)?%?\z/
  return actual.delete(",").to_f == expected.delete(",").to_f && actual.end_with?("%") == expected.end_with?("%") if actual.match?(numeric) && expected.match?(numeric)

  actual == expected
end

def expect_cap_table_rows(actual_rows, table)
  expected_rows = table.hashes
  unmatched = actual_rows.dup
  expected_rows.each do |expected|
    match = unmatched.find { |row| expected.all? { |key, value| cap_table_cell_matches?(row[key].to_s, value.to_s) } }
    expect(match).not_to be_nil, "No row matching #{expected.inspect} in #{actual_rows.inspect}"
    unmatched.delete(match)
  end
  expect(unmatched).to be_empty, "Unexpected extra rows #{unmatched.inspect}"
end

# Walks the horizontal cap table (rows are collapsed, so visible: :all) and returns one hash per
# investor row with the category and subgroup header rows it sits under.
def horizontal_cap_table_investor_rows
  rows = []
  within(".show_horizontal_cap_table") do
    category = nil
    subgroup = nil
    all("tbody tr", visible: :all).each do |tr|
      classes = tr[:class].to_s.split
      cells = tr.all("td", visible: :all).map { |td| td.text(:all).strip }
      if classes.include?("parent-sub")
        subgroup = tr.find("strong", visible: :all).text(:all).strip
      elsif classes.include?("parent")
        category = tr.find("strong", visible: :all).text(:all).strip
        subgroup = nil
      elsif classes.include?("subchild") || classes.include?("child")
        rows << { "category" => category, "subgroup" => (classes.include?("subchild") ? subgroup : ""),
                  "investor" => cells[0], "instrument" => cells[1] }
      end
    end
  end
  rows
end

def funding_round_table_rows(round)
  col = page.all(".col").find { |c| c.has_css?("h1", text: "Funding Round: #{round}") }
  expect(col).not_to be_nil, "Funding Round: #{round} not found on the cap table page"
  col.all("tbody tr").map do |tr|
    cells = tr.all("td").map { |td| td.text.strip }
    { "investor" => cells[0], "instrument" => cells[1], "quantity" => cells[2], "percentage" => cells[3],
      "fully diluted" => cells[4], "fully diluted %" => cells[5] }
  end
end

# Fills in and submits the import upload form the current page is on (both the generic
# ImportUpload form and the ShareholderPositionUpload form use these field names), then runs
# the import synchronously.
def submit_upload_form(file_path)
  fill_in("import_upload_name", with: "Upload #{SecureRandom.hex(4)}")
  attach_file("files[]", file_path, make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  @import_upload = ImportUpload.last
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end

def select2_value(select_id, value)
  page.execute_script(<<~JS)
    var sel = document.getElementById(#{select_id.to_json});
    sel.value = #{value.to_json};
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    if (window.jQuery) { window.jQuery(sel).trigger('change'); }
  JS
end

# ── Setup ─────────────────────────────────────────────────────────────────────────────────────

# The investment form's Currency dropdown lists the entity's exchange rate "from" currencies.
Given('the entity has an exchange rate from {string} to {string}') do |from, to|
  ExchangeRate.create!(entity_id: @entity.id, from:, to:, rate: 1, as_of: Time.zone.today)
end

# ── Investment form ───────────────────────────────────────────────────────────────────────────

When('I open the new investment form for {string}') do |company_name|
  company = Investor.find_by(investor_name: company_name)
  visit(new_investment_path(portfolio_company_id: company.id))
  expect(page).to have_field("investment_investor_name")
end

When('I choose instrument type {string}') do |investment_type|
  select(investment_type, from: "investment_investment_type")
end

Then('I should see the instrument name and quantity fields') do
  expect(page).to have_field("investment_instrument_name", visible: true)
  expect(page).to have_field("investment_instrument_quantity", visible: true)
end

Then('I should not see the instrument name and quantity fields') do
  expect(page).to have_no_field("investment_instrument_name", visible: true)
  expect(page).to have_no_field("investment_instrument_quantity", visible: true)
end

# Vertical table of form fields: currency, category, investor_name, investment_type, subgroup,
# funding_round, quantity, instrument_name, instrument_quantity, price, investment_date.
When('I create an investment for {string} through the form with:') do |company_name, table|
  step %(I open the new investment form for "#{company_name}")
  attrs = table.rows_hash

  select(attrs["currency"], from: "investment_currency") if attrs["currency"]
  select2_value("investment_category", attrs["category"]) if attrs["category"]
  step %(I choose instrument type "#{attrs['investment_type']}") if attrs["investment_type"]
  %w[investor_name subgroup funding_round quantity instrument_name instrument_quantity price investment_date].each do |field|
    fill_in("investment_#{field}", with: attrs[field]) if attrs.key?(field)
  end

  find("input[type=submit]").click
end

Then('the investment for {string} should have:') do |investor_name, table|
  investment = Investment.where(investor_name: investor_name).order(:id).last
  expect(investment).not_to be_nil, "No investment found for #{investor_name}"
  expect_record_attributes(investment, table)
end

Then('no investment should exist for {string}') do |investor_name|
  expect(Investment.where(investor_name: investor_name)).not_to exist
end

When('I visit the investment for {string}') do |investor_name|
  visit(investment_path(Investment.where(investor_name: investor_name).order(:id).last))
end

# ── Cap table rendering ───────────────────────────────────────────────────────────────────────

Then('the horizontal cap table should have these investor rows:') do |table|
  expect(page).to have_css(".show_horizontal_cap_table")
  expect_cap_table_rows(horizontal_cap_table_investor_rows, table)
end

Then('the {string} round cap table should have these rows:') do |round, table|
  expect_cap_table_rows(funding_round_table_rows(round), table)
end

# Reads a single (non-rollup) row's own "% stake fully diluted" cell for one round from the
# horizontal cap table. Used to check the "Self" row, which several distinct Investment records
# can merge into (see GenerateHorizontalCapTable#process_rounds) - the row is looked up by its
# displayed Particulars text, and the round column by its header text, so this works for any
# category, not just "Self". "Self" is a sentinel for that row's displayed label, since it's the
# portfolio company's linked entity name (a factory-random value), not knowable when the
# scenario is written.
Then('the horizontal cap table should show {string} as the {string} percentage for {string}') do |expected_percentage, round, row_label|
  row_label = @portfolio_company.entity.name if row_label == "Self"

  expect(page).to have_css(".show_horizontal_cap_table")
  within(".show_horizontal_cap_table") do
    round_headers = all("thead tr")[1].all("th", visible: :all).map { |th| th.text.strip }
    round_index = round_headers.index(round)
    expect(round_index).not_to be_nil, "Round #{round.inspect} not found in header: #{round_headers.inspect}"

    row = all("tbody tr.child, tbody tr.subchild", visible: :all).find { |tr| tr.all("td", visible: :all).first.text(:all).strip == row_label }
    expect(row).not_to be_nil, "No row found for #{row_label.inspect}"

    cells = row.all("td", visible: :all).map { |td| td.text(:all).strip }
    expect(cells[2 + round_index]).to eq(expected_percentage)
  end
end

# ── Cap table page buttons ────────────────────────────────────────────────────────────────────

Then('I should see these cap table actions:') do |table|
  table.raw.flatten.each { |label| expect(page).to have_link(label) }
end

Then('I should not see these cap table actions:') do |table|
  table.raw.flatten.each { |label| expect(page).to have_no_link(label) }
end

# ── Uploads ───────────────────────────────────────────────────────────────────────────────────

# "I click the {string} button" comes from kyc_data.rb.
Then('the upload page should offer the sample file {string}') do |file_name|
  expect(page).to have_link("Sample upload format", href: "/sample_uploads/#{file_name}")
end

When('I upload the sample file {string}') do |file_name|
  submit_upload_form(File.absolute_path("./public/sample_uploads/#{file_name}"))
end

# Builds the xlsx from the table (headers are the table's column names, so header spellings
# such as "SubGroup" can be exercised) and uploads it through the current upload page.
When('I upload an investments file with:') do |table|
  file = build_shareholder_position_upload_file(table.hashes)
  submit_upload_form(file.path)
end

# An "Update Only" row for an existing investment: its current values, with the given columns
# overridden, so only the columns under test change.
When('I upload an update-only investments file for {string} with:') do |investor_name, table|
  investment = Investment.where(investor_name: investor_name).order(:id).last
  row = {
    "Id" => investment.id, "Portfolio Company" => investment.portfolio_company.investor_name,
    "Category" => investment.category, "Currency" => investment.currency,
    "Investor Name" => investment.investor_name, "Investment Type" => investment.investment_type,
    "Funding Round" => investment.funding_round, "Quantity" => investment.quantity,
    "Price" => investment.price.to_d, "Investment Date" => investment.investment_date.strftime("%d/%m/%Y"),
    "Notes" => investment.notes, "Update Only" => "Yes"
  }.merge(table.rows_hash)
  file = build_shareholder_position_upload_file([row])
  submit_upload_form(file.path)
end

Then('the upload should succeed with {int} row(s)') do |count|
  expect(@import_upload.failed_row_count.to_i).to eq(0), "Upload failed: #{@import_upload.status}"
  expect(@import_upload.processed_row_count.to_i).to eq(count)
end

Then('the imported investments should not have custom fields named:') do |table|
  keys = table.raw.flatten.map { |header| header.parameterize.underscore }
  Investment.where(import_upload_id: @import_upload.id).find_each do |investment|
    expect(investment.properties.to_h.keys & keys).to be_empty,
                                                      "#{investment.investor_name} stored #{investment.properties.to_h.keys & keys} as custom fields"
  end
  created = @import_upload.custom_fields_created.to_s.split(";").map { |name| name.parameterize.underscore }
  expect(created & keys).to be_empty, "Custom fields created for #{created & keys}"
end

# "As Of" is either a position date (e.g. 2025-12-31) or a round name (e.g. Series A), mirroring
# how ImportShareholderPosition stores the As Of column.
Then('the shareholder position for {string} as of {string} should have:') do |investor_label, as_of, table|
  position = ShareholderPosition.where(investor_label: investor_label)
                                .find { |sp| sp.round_name == as_of || sp.position_date.to_s == as_of }
  expect(position).not_to be_nil, "No shareholder position for #{investor_label} as of #{as_of}"
  expect_record_attributes(position, table)
end
