# Step definitions for features/fund/account_entries_index_query.feature, and the shared
# fixtures for features/fund/account_entries_default_fund.feature.
#
# features/support/env.rb excludes `account_entries` from DatabaseCleaner's truncation, so
# rows survive between scenarios and a reused fund id would pick them up. Clean up here
# rather than touching the shared exclusion list.
After('@account_entries_index_query') do
  next if @aeiq_funds.blank?

  AccountEntry.where(fund_id: @aeiq_funds.values.map(&:id)).delete_all
end

AEIQ_RELATED_TABLES = %w[funds investors capital_commitments investor_kycs].freeze
AEIQ_RELATED_COLUMN = /\b(?:#{AEIQ_RELATED_TABLES.join('|')})\b["`]?\.|\bt\d+_r\d+\b/
AEIQ_RELATED_FROM = /\ASELECT\s.*?\sFROM\s+["`]?(?:#{AEIQ_RELATED_TABLES.join('|')})["`]?(?:\s|\z)/mi
AEIQ_ENTRIES_FROM = /\ASELECT\s.*?\sFROM\s+["`]?account_entries["`]?(?:\s|\z)/mi

### Helpers ####################################################################

def aeiq_fund!(name)
  @aeiq_funds.fetch(name)
end

# A date that is always inside the current year, because the list defaults its reporting
# date lower bound to Jan 1 of the current year.
def aeiq_reporting_date
  Date.current.beginning_of_year + 30.days
end

def aeiq_commitment(fund, folio_id, investor_name)
  @aeiq_commitments ||= {}
  @aeiq_commitments[[fund.id, folio_id.to_s]] ||= begin
    holder = FactoryBot.create(:entity, name: "#{investor_name} Holder", entity_type: "Investment Fund")
    investor = Investor.create!(entity: fund.entity, investor_entity: holder, investor_name: investor_name,
                                primary_email: "aeiq#{SecureRandom.hex(4)}@example.com", category: "Co-Investor")
    kyc = FactoryBot.create(:investor_kyc, entity: fund.entity, investor: investor, full_name: "#{investor_name} KYC")
    CapitalCommitment.create!(entity: fund.entity, fund: fund, investor: investor, investor_kyc: kyc,
                              folio_id: folio_id.to_s, folio_currency: fund.currency,
                              unit_type: fund.unit_types.to_s.split(",").first.strip, fund_close: "First Close",
                              commitment_date: Date.new(2023, 4, 1), folio_committed_amount_cents: 1_000_000)
  end
end

def aeiq_entry(fund, name:, commitment: nil)
  AccountEntry.create!(entity_id: fund.entity_id, fund_id: fund.id, entry_type: "Fee", name: name,
                       amount_cents: 10_000, reporting_date: aeiq_reporting_date, cumulative: false,
                       generated: true, folio_id: commitment&.folio_id,
                       commitment_name: commitment&.to_s, capital_commitment_id: commitment&.id,
                       investor_id: commitment&.investor_id)
end

# SELECT statements made while the block runs, in the order they were issued.
def aeiq_capture_selects
  statements = []
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    sql = payload[:sql].to_s
    next unless sql.match?(/\A\s*SELECT/i)
    next if payload[:name].to_s.include?("SCHEMA")

    statements << sql
  end
  yield
  statements
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
end

def aeiq_select_list(sql)
  sql[/\ASELECT\s+(.*?)\s+FROM\s/mi, 1].to_s
end

def aeiq_feed_path(fund_name: nil, per_page: nil)
  params = { format: :json }
  params[:fund_id] = aeiq_fund!(fund_name).id if fund_name
  params[:per_page] = per_page if per_page
  account_entries_path(params)
end

def aeiq_load_feed(path)
  visit path
  @aeiq_rows = JSON.parse(page.body)
end

def aeiq_row!(name)
  @aeiq_rows.find { |row| row["name"] == name } || raise("no feed row named #{name.inspect} in #{@aeiq_rows.pluck('name')}")
end

### Setup ######################################################################

Given('the entity has funds {string}') do |names|
  @aeiq_funds ||= {}
  names.split(",").map(&:strip).each do |name|
    @aeiq_funds[name] = FactoryBot.create(:fund, entity_id: @entity.id, name: name, currency: "INR", unit_types: "A1")
  end
  @fund = @aeiq_funds[names.split(",").first.strip]
end

Given('fund {string} has an entry {string} for folio {string} of investor {string}') do |fund_name, entry_name, folio_id, investor_name|
  fund = aeiq_fund!(fund_name)
  aeiq_entry(fund, name: entry_name, commitment: aeiq_commitment(fund, folio_id, investor_name))
end

Given('fund {string} has a fund-level entry {string}') do |fund_name, entry_name|
  aeiq_entry(aeiq_fund!(fund_name), name: entry_name)
end

Given('fund {string} has {string} entries each on its own folio') do |fund_name, count|
  fund = aeiq_fund!(fund_name)
  count.to_i.times do |i|
    commitment = aeiq_commitment(fund, "F#{i + 1}", "Investor #{i + 1}")
    aeiq_entry(fund, name: "Fee #{i + 1}", commitment: commitment)
  end
end

Given('an employee with access to fund {string} only') do |fund_name|
  fund = aeiq_fund!(fund_name)
  @aeiq_employee = FactoryBot.create(:user, entity: fund.entity, first_name: "Eve")
  @aeiq_employee.add_role(:employee)
  AccessRight.create!(owner: fund, access_type: "Fund", user_id: @aeiq_employee.id, entity_id: fund.entity_id)
end

Given('I am signed in as the employee') do
  Capybara.reset_sessions!
  @user = @aeiq_employee
  log_in(@user)
end

### Viewing ####################################################################

When('I open the account entries list for fund {string}') do |fund_name|
  visit account_entries_path(fund_id: aeiq_fund!(fund_name).id)
end

When('I open the account entries list for fund {string} capturing the database queries') do |fund_name|
  @aeiq_selects = aeiq_capture_selects { visit account_entries_path(fund_id: aeiq_fund!(fund_name).id) }
end

When('I request the account entries feed for fund {string}') do |fund_name|
  aeiq_load_feed(aeiq_feed_path(fund_name: fund_name))
end

When('I request the account entries feed') do
  aeiq_load_feed(aeiq_feed_path)
end

When('I request the account entries feed for fund {string} with {string} per page') do |fund_name, per_page|
  selects = aeiq_capture_selects { aeiq_load_feed(aeiq_feed_path(fund_name: fund_name, per_page: per_page)) }
  @aeiq_lookups ||= {}
  @aeiq_lookups[per_page] = selects.grep(AEIQ_RELATED_FROM)
  @aeiq_rows_by_page ||= {}
  @aeiq_rows_by_page[per_page] = @aeiq_rows.size
end

### Assertions #################################################################

Then('the account entries page should load') do
  expect(page.status_code).to eq(200)
end

Then('the page load should have read account entries without selecting any related table columns') do
  entries_selects = @aeiq_selects.grep(AEIQ_ENTRIES_FROM)
  expect(entries_selects).not_to be_empty, "expected at least one SELECT from account_entries, got:\n#{@aeiq_selects.map { |q| q[0, 160] }.join("\n")}"

  offenders = entries_selects.select { |sql| aeiq_select_list(sql).match?(AEIQ_RELATED_COLUMN) }
  expect(offenders).to be_empty,
                       "account_entries SELECT also reads related table columns:\n#{offenders.map { |q| q[0, 300] }.join("\n")}"
end

Then('the feed should list {string} rows') do |count|
  expect(@aeiq_rows.size).to eq(count.to_i)
end

Then('the feed row {string} should show fund {string}, investor {string} and investing entity {string}') do |name, fund_name, investor_name, kyc_name|
  row = aeiq_row!(name)
  expect(row["fund_name"]).to eq(fund_name)
  expect(row["investor_name"]).to eq(investor_name)
  expect(row["investing_entity"]).to eq(kyc_name)
end

Then('the feed row {string} should have no investor and no folio') do |name|
  row = aeiq_row!(name)
  expect(row["investor_name"]).to be_blank
  expect(row["folio_currency"]).to be_blank
  expect(row["folio_id"]).to be_blank
end

Then('the feed should list only the entries {string}') do |names|
  expect(@aeiq_rows.pluck("name").sort).to eq(names.split(",").map(&:strip).sort)
end

Then('both page sizes should have listed their full page') do
  expect(@aeiq_rows_by_page.values).to eq([5, 10])
end

Then('both page sizes should have made the same number of related look-ups') do
  counts = @aeiq_lookups.transform_values(&:size)
  expect(counts.values.uniq.size).to eq(1),
                                     "related look-ups changed with page size: #{counts}\n" +
                                     @aeiq_lookups.map { |size, qs| "per_page=#{size}:\n" + qs.map { |q| "  #{q[0, 140]}" }.join("\n") }.join("\n")
end
