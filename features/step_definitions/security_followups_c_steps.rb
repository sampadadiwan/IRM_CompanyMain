# Steps for the 2026-10 security review follow-ups F6 (features/security/security_review_2026_10_followups.feature):
# leftovers found after the F5 pass.
#   F6-1 / F6-1X   the allocate_account_entries sample fund formulas workbook had no Cache column, which
#                  ImportFundFormula requires, so the header check refused every row
#   F6-2 / F6-2a / F6-2H  interests#allocation_form and the turbo_stream branch of interests#allocate used
#                  views "Secondary allocations" (#503) deleted; both removed, the HTML / JSON allocate kept
#   F6-3           interests#finalize and offers#generate_esign_link were routed to no action; removed
#   F6-4           FundRatio.for_portfolio_companies filtered owner_type 'PortfolioCompany', which no row has
#
# Reused steps:
#   fund.rb                              — "there is a fund … for the entity", "Given import file … for …"
#   security_h8_h11_h14_h15_h19_steps.rb — "the sale has a seller with an approved offer and a buyer …",
#                                          "… has an unverified interest on the sale", "the interest of … has …"
#   security_followups_b_steps.rb        — "the sale's company admin allocates the interest of … with …",
#                                          "the … routes have no … action", "every … route points at an action …"
#   security_c4_c7_h16_l10_steps.rb      — sr_request / sr_sign_in, "the address is not found"

# RubyXL::Worksheet#delete_column lives in rubyXL's optional convenience methods
require "rubyXL/convenience_methods/worksheet"

module SecurityFollowupsCHelpers
  # The Accept header Turbo sends with a form submission (@hotwired/turbo FetchRequest)
  TURBO_FORM_ACCEPT = "text/vnd.turbo-stream.html, text/html, application/xhtml+xml".freeze

  # The data rows of a sample upload workbook (public/sample_uploads/<file>), keyed by header, each with its
  # spreadsheet row number under "_row" (the numbering ImportUpload#row_errors uses: the header is row 1)
  def f6_workbook_rows(file)
    sheet = Roo::Spreadsheet.open(Rails.public_path.join("sample_uploads", file).to_s).sheet(0)
    headers = sheet.row(1).map(&:to_s)
    # One hash per non-blank row, cells as the sheet holds them
    rows = (2..sheet.last_row).map { |row| headers.zip(sheet.row(row).map { |c| c.to_s.strip }).to_h.merge("_row" => row) }
    rows.reject { |r| r["Name"].blank? }
  end

  # The rows of this scenario's import (@import_file) that the import did not report as failed
  def f6_imported_rows
    failed = (@import_upload.row_errors || []).pluck("row")
    f6_workbook_rows(@import_file).reject { |r| failed.include?(r["_row"]) }
  end

  # Writes a copy of a sample workbook without one column into the scenario's own tmp dir; returns its path
  def f6_workbook_without_column(file, header)
    workbook = RubyXL::Parser.parse(Rails.public_path.join("sample_uploads", file).to_s)
    sheet = workbook[0]
    # The column whose header cell is `header`
    index = sheet[0].cells.index { |c| c&.value.to_s.strip == header }
    expect(index).not_to be_nil, "no #{header} column in #{file}"
    sheet.delete_column(index)
    # Each worker writes its own file (TEST_ENV_NUMBER), so parallel runs never share one
    path = Rails.root.join("tmp", "f6_#{ENV.fetch('TEST_ENV_NUMBER', '0')}_#{File.basename(file)}").to_s
    workbook.write(path)
    path
  end
end
World(SecurityFollowupsCHelpers)

# ---- F6-1 The allocate_account_entries sample formulas workbook ---------------------------------

Then('the only failed row is sheet row {int}, {string}, with {string}') do |row, name, message|
  # Exactly one row error, on the named row of the sheet
  errors = @import_upload.row_errors || []
  expect(errors.pluck("row")).to eq([row])
  expect(errors.first["message"]).to include(message)
  expect(f6_workbook_rows(@import_file).find { |r| r["_row"] == row }&.fetch("Name")).to eq(name)
end

Then('the fund has a formula for every other row of the sample workbook') do
  rows = f6_imported_rows
  # Every row that did not fail became one formula, at the sequence the sheet gave it
  formulas = @fund.fund_formulas.order(:sequence)
  expect(formulas.pluck(:sequence, :name)).to eq(rows.map { |r| [r["Sequence"].to_i, r["Name"]] })
end

Then("each imported formula's cache flag is the {string} cell of its sample workbook row") do |header|
  # The Cache cell of every imported row, by its sequence
  expected = f6_imported_rows.to_h { |r| [r["Sequence"].to_i, r[header].casecmp?("yes")] }
  # FundFormulaAttributes maps Cache to add_to_commitment_cache
  expect(@fund.fund_formulas.pluck(:sequence, :add_to_commitment_cache).to_h).to eq(expected)
end

Then('{int} of the imported formulas are added to the commitment cache') do |count|
  expect(@fund.fund_formulas.where(add_to_commitment_cache: true).count).to eq(count)
end

When('the sample workbook {string} is imported for the fund without its {string} column') do |file, header|
  # The workbook as it was before F6: every column but this one
  path = f6_workbook_without_column(file, header)
  @import_upload = ImportUpload.create!(entity: @entity, owner: @fund, import_type: "FundFormula", name: "Import FundFormula",
                                        user_id: @user.id, import_file: File.open(path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
ensure
  FileUtils.rm_f(path) if path
end

Then('the import upload status is {string}') do |status|
  expect(@import_upload.status).to eq(status)
end

Then('the fund has no fund formulas') do
  expect(@fund.fund_formulas).to be_empty
end

Then('every sample fund formulas workbook has every column the fund formula import requires') do
  # The header check ImportUtil#validate_headers runs, on every fund formulas sample file
  importer = ImportFundFormula.new
  files = Rails.root.glob("public/sample_uploads/**/*fund_formula*.xlsx")
  expect(files).not_to be_empty
  missing = files.to_h do |path|
    headers = importer.get_headers(Roo::Spreadsheet.open(path.to_s).sheet(0).row(1).map(&:to_s))
    [path.relative_path_from(Rails.root).to_s, importer.required_headers.reject { |h| headers.include?(h.downcase.strip.squeeze(" ").titleize) }]
  end
  expect(missing.reject { |_file, cols| cols.empty? }).to be_empty
end

# ---- F6-2 / F6-3 Interest and offer routes --------------------------------------------------------

When("the sale's company admin opens the old allocation form address of the interest of {string}") do |label|
  # No path helper exists any more: the address as an old link would send it
  sr_sign_in(@user)
  sr_request(:get, "/interests/#{sec_interests.fetch(label).id}/allocation_form")
end

When("the sale's company admin allocates the interest of {string} from a Turbo form with {string}") do |label, spec|
  sr_sign_in(@user)
  # The Accept header that sent the old inline allocation form down the turbo_stream branch
  page.driver.header("Accept", SecurityFollowupsCHelpers::TURBO_FORM_ACCEPT)
  sr_request(:patch, allocate_interest_path(sec_interests.fetch(label)), { interest: sec_fields(spec) })
ensure
  # Later requests of the scenario go out as a plain browser's
  page.driver.header("Accept", nil)
end

Then('the company admin is on the page of the interest of {string} with {string}') do |label, notice|
  # allocate redirected to the interest, and the redirect was followed
  expect(@sr_status).to eq(200)
  expect(page).to have_current_path(interest_path(sec_interests.fetch(label)))
  expect(page).to have_content(notice)
end

When("the sale's company admin patches the old finalize address of the interest of {string}") do |label|
  sr_sign_in(@user)
  sr_request(:patch, "/interests/#{sec_interests.fetch(label).id}/finalize")
end

When("the sale's company admin patches the old eSign link address of the seller's offer") do
  sr_sign_in(@user)
  sr_request(:patch, "/offers/#{@offer.id}/generate_esign_link")
end

# ---- F6-4 FundRatio.for_portfolio_companies ------------------------------------------------------

Given('the fund has ratios owned by:') do |table|
  table.hashes.each do |row|
    # "the fund", or "portfolio company <name>": a portco is an investors row of the fund manager
    owner = if row["owner"] == "the fund"
              @fund
            else
              name = row["owner"].delete_prefix("portfolio company ").strip
              FactoryBot.create(:investor, name:, category: "Portfolio Company", entity: @fund.entity,
                                           investor_entity: FactoryBot.create(:entity, entity_type: "Company"))
            end
    # Stored as FundRatiosJob writes them (owner_type "Fund" or "Investor")
    FundRatio.create!(entity_id: @fund.entity_id, fund: @fund, owner:, name: row["name"], value: row["display_value"].to_d,
                      display_value: row["display_value"], end_date: Date.new(2025, 3, 31), scenario: "Default", latest: true)
  end
end

Then("the fund's portfolio company ratios are {string}") do |list|
  # "<owner name> <ratio name>" of each row the scope returns for the fund
  found = FundRatio.for_portfolio_companies.where(fund: @fund).includes(:owner).map { |fr| "#{fr.owner.investor_name} #{fr.name}" }
  expect(found).to match_array(list.split(",").map(&:strip))
end
