# Step definitions covering the ShareholderPosition upload pipeline (ImportShareholderPosition),
# the Fully Diluted/Quantity Actuals approval workflow (ShareholderPositionApprover +
# ShareholderPositionPolicy), the shareholder positions list view, and GenerateCapTable/
# GenerateHorizontalCapTable's handling of ShareholderPosition rows - converted from the RSpec
# suites at spec/models/shareholder_position_spec.rb, spec/policies/shareholder_position_policy_spec.rb,
# spec/services/generate_cap_table_spec.rb, spec/views/shareholder_positions/_list.html.erb_spec.rb
# and spec/views/investments/_horizontal_captable.html.erb_spec.rb into end-to-end browser
# scenarios. A handful of narrow internal-method-only cases (e.g. calling
# ShareholderPositionApprover directly on an already-approved id, or private helpers like
# GenerateHorizontalCapTable#normalize_round_month_year) have no natural UI trigger and are not
# reproduced here - see the "best-effort UI equivalent" scope agreed with the user.

# Builds a temporary xlsx file for a ShareholderPosition upload from an array of row hashes
# (Cucumber table.hashes). Headers are the union of every row's keys, in first-seen order.
def build_shareholder_position_upload_file(rows)
  headers = []
  rows.each { |row| row.each_key { |key| headers << key unless headers.include?(key) } }

  package = Axlsx::Package.new
  package.workbook.add_worksheet(name: "Sheet1") do |sheet|
    sheet.add_row(headers)
    rows.each { |row| sheet.add_row(headers.map { |header| row[header] }) }
  end

  file = Tempfile.new(["shareholder_positions", ".xlsx"])
  file.binmode
  package.serialize(file.path)
  file
end

# Drives the real upload UI (ShareholderPositionUploadsController#new/#create) and then runs the
# import job synchronously, exactly like the "I upload investments file" step in investment.rb.
def perform_shareholder_position_upload(rows)
  file = build_shareholder_position_upload_file(rows)
  visit new_shareholder_position_upload_path
  fill_in('import_upload_name', with: "Shareholder Positions #{SecureRandom.hex(4)}")
  attach_file('files[]', file.path, make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  @import_upload = ImportUpload.last
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end

# A plain investor (shareholder) under the current entity - mirrors how "there is an existing
# portfolio company" builds its own backing Entity, without the "Portfolio Company" category.
Given('there is an investor named {string}') do |name|
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor", name: name)
  FactoryBot.create(:investor, investor_entity_id: investor_entity.id, entity_id: @entity.id,
                                investor_name: name, primary_email: investor_entity.primary_email)
end

# Direct creation of ShareholderPosition rows, bypassing the import pipeline entirely - for
# scenarios that only need existing ShareholderPosition state (GenerateCapTable/
# GenerateHorizontalCapTable behavior, list view rendering), not the upload/parsing behavior
# itself.
Given('there are the following shareholder positions for {string}:') do |company_name, table|
  company = Investor.find_by(investor_name: company_name)
  entity = company.entity

  table.hashes.each do |row|
    investor_name = row['investor_name']
    investor = Investor.find_by(investor_name: investor_name, entity_id: entity.id) ||
               FactoryBot.create(:investor, entity: entity, investor_name: investor_name,
                                             primary_email: "#{investor_name.parameterize}-#{SecureRandom.hex(3)}@example.com")

    ShareholderPosition.create!(
      entity: entity,
      investor: investor,
      portfolio_company: company,
      position_type: row['position_type'].presence || 'Shareholder',
      category: row['category'].presence || 'Other',
      subgroup: row['subgroup'].presence,
      round_name: row['round_name'].presence,
      position_date: row['position_date'].presence,
      position_amount: row['position_amount'].presence,
      quantity_actual: row['quantity_actual'].presence,
      fully_diluted_percentage: row['fully_diluted_percentage'].presence,
      instrument: row['instrument'].presence,
      investor_label: row['investor_label'].presence || investor_name,
      status: row['status'].presence || 'approved'
    )
  end
end

# Header-validation / cross-company scenarios where no "Portfolio Company" default should be
# auto-injected - every row must supply its own Portfolio Company/Stakeholder column (or
# deliberately omit it, to exercise the "column required" validation).
When('I upload a shareholder positions file with:') do |table|
  perform_shareholder_position_upload(table.hashes)
end

# Convenience wrapper for the common single-company case: rows that don't already specify a
# Portfolio Company/Stakeholder column get the given company name filled in automatically.
When('I upload a shareholder positions file for {string} with:') do |portfolio_company_name, table|
  rows = table.hashes.map do |row|
    if row['Portfolio Company'].present? || row['Stakeholder'].present?
      row
    else
      row.merge('Portfolio Company' => portfolio_company_name)
    end
  end
  perform_shareholder_position_upload(rows)
end

Then('the shareholder position upload should succeed') do
  expect(@import_upload.failed_row_count.to_i).to eq(0)
end

Then('the shareholder position upload should fail with {string}') do |message|
  expect(@import_upload.status.to_s).to include(message)
end

Then('the shareholder position upload should have {int} failed row(s)') do |count|
  expect(@import_upload.failed_row_count.to_i).to eq(count)
end

Then('{int} shareholder position(s) should have been created') do |count|
  expect(ShareholderPosition.where(import_upload_id: @import_upload.id).count).to eq(count)
end

Then('{int} unapproved shareholder position(s) should exist for {string} at {string}') do |count, investor_name, company_name|
  company = Investor.find_by(investor_name: company_name)
  investor = Investor.find_by(investor_name: investor_name)
  expect(ShareholderPosition.unapproved.where(portfolio_company_id: company.id, investor_id: investor.id).count).to eq(count)
end

# Looks up the most recently created position (approved or unapproved) for an investor/company
# pair and checks a vertical table of field => expected value. Numeric-looking expectations are
# compared as floats (decimal columns can round-trip with a different string representation than
# what was typed), everything else (category, subgroup, round_name, instrument, position_date,
# blank checks) is compared as a plain string.
Then('the {word} shareholder position for {string} at {string} should have:') do |status, investor_name, company_name, table|
  company = Investor.find_by(investor_name: company_name)
  investor = Investor.find_by(investor_name: investor_name)
  position = ShareholderPosition.where(portfolio_company_id: company.id, investor_id: investor.id, status: status)
                                 .order(:id).last
  expect(position).not_to be_nil, "No #{status} shareholder position found for #{investor_name} at #{company_name}"

  table.rows_hash.each do |field, expected|
    actual = position.public_send(field.to_sym)
    if expected.match?(/\A-?\d+(\.\d+)?\z/) && actual.is_a?(Numeric)
      expect(actual.to_f).to eq(expected.to_f), "expected #{field} to be #{expected} but was #{actual}"
    else
      expect(actual.to_s).to eq(expected), "expected #{field} to be #{expected.inspect} but was #{actual.to_s.inspect}"
    end
  end
end

# ── Cap table / horizontal cap table rendering ────────────────────────────────────────────────

Then('I should see {string} with quantity {string} and fully diluted {string} in the {string} round') do |investor_name, quantity, fully_diluted, round|
  col = page.all(".col").find { |c| c.has_css?("h1", text: "Funding Round: #{round}") }
  expect(col).not_to be_nil, "Funding Round: #{round} not found on the cap table page"
  row = col.all("tr").find { |r| r.has_content?(investor_name) }
  expect(row).not_to be_nil, "No row for #{investor_name} found in the #{round} round table"
  expect(row).to have_content(quantity)
  expect(row).to have_content(fully_diluted)
end

Then('I should see {string} with quantity {string}, percentage {string}, and fully diluted {string} in the {string} round') do |investor_name, quantity, percentage, fully_diluted, round|
  col = page.all(".col").find { |c| c.has_css?("h1", text: "Funding Round: #{round}") }
  expect(col).not_to be_nil, "Funding Round: #{round} not found on the cap table page"
  row = col.all("tr").find { |r| r.has_content?(investor_name) }
  expect(row).not_to be_nil, "No row for #{investor_name} found in the #{round} round table"
  expect(row).to have_content(quantity)
  expect(row).to have_content(percentage)
  expect(row).to have_content(fully_diluted)
end

Then('the horizontal cap table should show {string} nested under subgroup {string} under category {string}, in that order') do |investor_name, subgroup, category|
  within(".show_horizontal_cap_table") do
    rows = all("tr", visible: :all)
    category_index = rows.index { |r| r[:class].to_s.include?("parent") && !r[:class].to_s.include?("child") && r.text(:all).include?(category) }
    subgroup_index = rows.index { |r| r[:class].to_s.include?("child") && r[:class].to_s.include?("parent-sub") && r.text(:all).include?(subgroup) }
    investor_index = rows.index { |r| r[:class].to_s == "subchild" && r.text(:all).include?(investor_name) }

    expect(category_index).not_to be_nil, "Category row for #{category} not found"
    expect(subgroup_index).not_to be_nil, "Subgroup row for #{subgroup} not found"
    expect(investor_index).not_to be_nil, "Investor row for #{investor_name} not found"

    expect(category_index).to be < subgroup_index
    expect(subgroup_index).to be < investor_index
  end
end

Then('I should see {string} funding rounds for {string}') do |rounds_csv, investor_name|
  rounds_csv.split(",").map(&:strip).each do |round|
    expect(page).to have_content(round)
  end
end

# ── Shareholder positions list view ────────────────────────────────────────────────────────────

Given('I visit the shareholder positions list for {string}') do |company_name|
  company = Investor.find_by(investor_name: company_name)
  visit shareholder_positions_path(portfolio_company_id: company.id)
end

Then('I should see a shareholder position row for {string} with category {string}, fully diluted {string}, and quantity actual {string}') do |investor_name, category, fully_diluted, quantity_actual|
  row = page.all("tr").find { |r| r.has_content?(investor_name) }
  expect(row).not_to be_nil, "No shareholder position row for #{investor_name} found"
  expect(row).to have_content(category)
  expect(row).to have_content(fully_diluted)
  expect(row).to have_content(quantity_actual)
end

# ── Pending Fully Diluted/Quantity Actuals approval workflow ───────────────────────────────────

Then('I should see a pending updates banner for {string}') do |round|
  expect(page).to have_content("Pending Fully Diluted/Quantity Actuals updates for #{round}")
end

Then('I should not see a pending updates banner') do
  expect(page).not_to have_content("Pending Fully Diluted/Quantity Actuals updates")
end

Then('I should see {string} as a pending update with Accept and Deny buttons') do |investor_name|
  row = page.all("tr").find { |r| r.has_content?(investor_name) && (r.has_button?("Accept") || r.has_button?("Deny")) }
  expect(row).not_to be_nil, "Expected a pending update row with Accept/Deny buttons for #{investor_name}"
  expect(row).to have_button("Accept")
  expect(row).to have_button("Deny")
end

Then('I should see {string} as a pending update with a percent-only change message') do |investor_name|
  row = page.all("tr").find { |r| r.has_content?(investor_name) && r.has_content?("%-only change") }
  expect(row).not_to be_nil, "Expected a %-only pending update row for #{investor_name}"
  expect(row).not_to have_button("Accept")
  expect(row).not_to have_button("Deny")
end

# Row-scoped variant of the shared "I click {string} and confirm" step in kpi_approval_steps.rb -
# needed here because each pending row renders its own Accept/Deny buttons, so a plain page-wide
# click_on would ambiguously match every row's button when more than one is pending.
When('I click {string} for the pending update for {string}') do |button_label, investor_name|
  row = page.all("tr").find { |r| r.has_content?(investor_name) && r.has_button?(button_label) }
  raise "No row with a #{button_label} button found for #{investor_name}" unless row

  # Confirms in #confirmModal only if the button asks (features/support/confirm_modal_helpers.rb)
  click_and_confirm_if_asked(row.find_button(button_label))
  sleep 1
end
