# Step definitions for features/fund/account_entries_default_fund.feature.
# Fixtures (funds, entries, employee, the feed helpers) come from
# account_entries_index_query_steps.rb.

# Loads the HTML page, to read what the filter shows, and then the JSON feed with the same
# parameters, to read which entries are listed.
def aedf_open_list(params)
  visit account_entries_path(params)
  @aedf_fund_filter = page.find("select#fund_id", visible: :all).all("option[selected]", visible: :all).map(&:text)
  @aedf_builder_values = page.all("input[name$='[value]']", visible: :all).map(&:value).compact_blank
  @aedf_delete_actions = page.all("form[action*='delete_all']", visible: :all).pluck(:action)
  @aedf_notice = page.all(".alert-info", visible: :all).map(&:text)
  @aedf_export_links = page.all("a[href*='.xlsx']", visible: :all).pluck(:href)
  aeiq_load_feed(account_entries_path(params.merge(format: :json)))
end

When('I open the account entries list without selecting a fund') do
  aedf_open_list({})
end

When('I choose fund {string} in the account entries list') do |fund_name|
  aedf_open_list(fund_id: aeiq_fund!(fund_name).id)
end

# The "All Funds" option of the top filter submits fund_id= (blank).
When('I choose all funds in the account entries list') do
  aedf_open_list(fund_id: "")
end

When('I open the account entries list with the funds {string} in a fund_id_in filter') do |fund_names|
  ids = fund_names.split(",").map { |name| aeiq_fund!(name.strip).id }
  aedf_open_list(q: { fund_id_in: ids })
end

Given('I am signed in as the first user of entity {string}') do |entity_name|
  Capybara.reset_sessions!
  @user = User.where(entity_id: Entity.find_by!(name: entity_name).id).order(:id).first
  log_in(@user)
end

Then('the filter should show only fund {string}') do |fund_name|
  expect(@aedf_fund_filter).to eq([fund_name])
  fund_ids = @aeiq_funds.values.map { |fund| fund.id.to_s }
  expect(@aedf_builder_values & fund_ids).to be_empty, "the default fund is also repeated as a separate filter row"
end

Then('the feed should be empty') do
  expect(@aeiq_rows).to be_empty
end

Then('the delete results and export links should be for fund {string}') do |fund_name|
  fund_id = aeiq_fund!(fund_name).id
  expect(@aedf_delete_actions).not_to be_empty
  expect(@aedf_export_links).not_to be_empty
  (@aedf_delete_actions + @aedf_export_links).each do |link|
    expect(link).to match(/fund_id=#{fund_id}(&|\z)/), "expected #{link} to name fund #{fund_id}"
  end
end

Then('the delete results and export links should not name a fund') do
  expect(@aedf_delete_actions + @aedf_export_links).not_to be_empty
  (@aedf_delete_actions + @aedf_export_links).each do |link|
    expect(link).not_to match(/fund_id=\d/), "expected #{link} not to name a fund"
  end
end

Given('fund {string} is positioned first') do |fund_name|
  fund = aeiq_fund!(fund_name)
  fund.update_columns(json_fields: (fund.json_fields || {}).merge("position" => "1"))
end

# Only the import_upload_id column matters to the list, so the entries just point at an id.
Given('fund {string} has an import with the entry {string}') do |fund_name, entry_name|
  @aedf_import_id = 900_001
  aeiq_entry(aeiq_fund!(fund_name), name: entry_name).update_columns(import_upload_id: @aedf_import_id)
end

When('I open the account entries list for that import') do
  aedf_open_list(import_upload_id: @aedf_import_id)
end

When('I open the account entries list narrowed to folio {string}') do |folio_id|
  aedf_open_list(q: { folio_id_eq: folio_id })
end

Then('the page should say it shows fund {string}') do |fund_name|
  expect(@aedf_notice.join(" ")).to include("Showing account entries of fund #{fund_name}")
end

Then('the page should not say which fund it shows') do
  expect(@aedf_notice.join(" ")).not_to include("Showing account entries of fund")
end

When('I delete the entry {string}') do |entry_name|
  entry = AccountEntry.find_by!(name: entry_name)
  page.driver.submit :delete, account_entry_path(entry), {}
end

Then('I should be back on the account entries list of fund {string}') do |fund_name|
  expect(page).to have_current_path(/\A#{Regexp.escape(account_entries_path)}\?.*fund_id=#{aeiq_fund!(fund_name).id}(&|\z)/)
end
