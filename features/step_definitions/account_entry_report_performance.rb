# Step definitions for features/fund/account_entry_report_performance.feature.
#
# The point of this feature is the QUERY BUDGET against account_entries, not just the
# numbers on the page, so most steps either count queries around a page load or read the
# aggregates straight off AccountEntryReport. See
# docs/modules/reports/account_entry_report_performance.md.
#
# features/support/env.rb excludes `account_entries` from DatabaseCleaner's truncation for
# suite-wide speed, so rows survive between scenarios and would be picked up by a later
# scenario's fund (MySQL's TRUNCATE resets auto-increment on the tables it does clean, so
# a fund id gets reused). Clean up here rather than touching the shared exclusion list.
After('@account_entry_report_perf') do
  next if @fund.nil?

  AccountEntry.where(fund_id: @fund.id).delete_all
end

### Helpers ####################################################################

def aerp_commitment!(folio_id)
  @aerp_commitments.fetch(folio_id.to_s)
end

# One folio-level, non-cumulative account entry - the shape the report actually reports on.
def aerp_entry(name:, amount:, folio_id:, date:, cumulative: false, commitment_name: nil)
  commitment = aerp_commitment!(folio_id)
  AccountEntry.create!(entity_id: @fund.entity_id, fund_id: @fund.id, entry_type: "Fee",
                       name: name, amount_cents: BigDecimal(amount.to_s),
                       reporting_date: Date.parse(date.to_s),
                       cumulative: cumulative, generated: true,
                       folio_id: folio_id.to_s,
                       commitment_name: commitment_name || commitment.to_s,
                       capital_commitment_id: commitment.id)
end

# Builds the report service for the fund directly, bypassing the controller, for the
# assertions that are about aggregate numbers rather than about the rendered page.
def aerp_report(start_date, end_date, commitment_ids: nil)
  AccountEntryReport.new(fund: @fund,
                         start_date: Date.parse(start_date.to_s),
                         end_date: Date.parse(end_date.to_s),
                         capital_commitment_ids: commitment_ids)
end

# Counts SELECTs that actually touch account_entries while the block runs. Written here
# rather than reusing SqlQueryCounter because that helper keys off a single WHERE column
# and this budget spans several differently-shaped queries against one table.
def aerp_count_account_entry_queries
  queries = []
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    sql = payload[:sql].to_s
    next unless sql.match?(/\ASELECT/i)
    next unless sql.match?(/account_entries/i)
    next if payload[:name].to_s.include?("SCHEMA")

    queries << sql
  end
  yield
  queries
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
end

def aerp_fund_report_path(start_date, end_date, extra = {})
  # The fund-level report now refuses to run at all until a folio, entry name, entry type
  # or allocation_run_id narrows it - so every visit here defaults to "all fixture
  # folios" (equivalent to the old unfiltered view for these scenarios, since none of them
  # have folios outside @aerp_commitments) unless the caller already passed its own filter.
  defaults = { fund_id: @fund.id, start_date: start_date, end_date: end_date }
  defaults[:capital_commitment_id] = @aerp_commitments.values.map(&:id) if @aerp_commitments
  fund_report_account_entry_reports_path(defaults.merge(extra))
end

### Setup ######################################################################

# Each folio needs its own investor and commitment; folio_currency matches the fund's so
# AccountEntry's set_folio_amount callback is a pass-through and needs no exchange rate.
Given('the report fund has folios {string}') do |folio_ids|
  @aerp_commitments = {}
  unit_type = @fund.unit_types.to_s.split(",").first&.strip
  folio_ids.split(",").map(&:strip).each_with_index do |folio_id, index|
    holder = FactoryBot.create(:entity, name: "Folio #{folio_id} Holder", entity_type: "Investment Fund")
    investor = Investor.create!(entity: @entity, investor_entity: holder,
                                investor_name: "Folio #{folio_id} Holder",
                                primary_email: "aerp#{folio_id}@example.com",
                                category: "Co-Investor")
    @aerp_commitments[folio_id] = CapitalCommitment.create!(
      entity: @entity, fund: @fund, investor: investor,
      folio_id: folio_id, folio_currency: @fund.currency,
      unit_type: unit_type, fund_close: "First Close",
      commitment_date: Date.new(2023, 4, 1) + index.days,
      folio_committed_amount_cents: 1_000_000
    )
  end
end

Given('the ledger holds {string} of {string} for folio {string} on {string}') do |name, amount, folio_id, date|
  aerp_entry(name: name, amount: amount, folio_id: folio_id, date: date)
end

# commitment_name is denormalized onto account_entries, so the same folio can carry
# different values across rows once an investor is renamed. The folio KPI must still
# count that as one folio.
Given('the ledger holds {string} of {string} for folio {string} on {string} recorded as {string}') do |name, amount, folio_id, date, commitment_name|
  aerp_entry(name: name, amount: amount, folio_id: folio_id, date: date, commitment_name: commitment_name)
end

Given('the ledger holds a cumulative {string} of {string} for folio {string} on {string}') do |name, amount, folio_id, date|
  aerp_entry(name: name, amount: amount, folio_id: folio_id, date: date, cumulative: true)
end

# Volume fixture for the "more rows must not mean more queries" scenarios. Spread over
# every folio and every month so the pivot has real rows and real columns to build.
Given('the ledger holds {string} entries spread across the folios in {string}') do |count, year|
  folios = @aerp_commitments.keys
  count.to_i.times do |i|
    month = (i % 12) + 1
    aerp_entry(name: "Entry #{(i % 4) + 1}",
               amount: (i + 1) * 10,
               folio_id: folios[i % folios.size],
               date: Date.new(year.to_i, month, 28).to_s)
  end
end

### Viewing the report #########################################################

When('I view the fund report from {string} to {string}') do |start_date, end_date|
  # Remembered so the numeric assertions below report on the same window the page did.
  @aerp_start_date = start_date
  @aerp_end_date = end_date
  visit aerp_fund_report_path(start_date, end_date)
end

When('I view page {string} of the fund report from {string} to {string}') do |page, start_date, end_date|
  visit aerp_fund_report_path(start_date, end_date, page: page)
end

When('I view the fund report from {string} to {string} counting account entry queries') do |start_date, end_date|
  @aerp_start_date = start_date
  @aerp_end_date = end_date
  @aerp_queries = aerp_count_account_entry_queries { visit aerp_fund_report_path(start_date, end_date) }
end

When('I view the fund report from {string} to {string} filtered to folios {string}') do |start_date, end_date, folios|
  ids = folios.split(",").map { |f| aerp_commitment!(f.strip).id }
  visit aerp_fund_report_path(start_date, end_date, capital_commitment_id: ids)
end

# A Turbo Frame request for the pivot's own frame. The controller matches on the frame id
# and must build the pivot alone, skipping the KPIs, both charts and the filter dropdowns.
When('I request page {string} of the detail pivot as a Turbo Frame, counting account entry queries') do |page_number|
  # The rack_test driver exposes `page.driver.header`, but this suite runs on the
  # Playwright driver, which has no such method - extra headers go through the
  # underlying browser context instead. NB: the block arg must not be called `page` -
  # it would shadow Capybara's `page`.
  page.driver.with_playwright_page do |pw_page|
    pw_page.context.set_extra_http_headers("Turbo-Frame" => AccountEntryReportsController::DETAIL_FRAME_ID)
  end
  @aerp_queries = aerp_count_account_entry_queries do
    visit aerp_fund_report_path("2024-01-01", "2024-12-31", page: page_number)
  end
  page.driver.with_playwright_page do |pw_page|
    pw_page.context.set_extra_http_headers({})
  end
end

### Assertions #################################################################

Then('at most {string} queries should have been made against account entries') do |max|
  actual = @aerp_queries.size
  # Report the SQL itself on failure: the useful information in a budget regression is
  # WHICH query came back, not that the number went up.
  expect(actual).to(be <= max.to_i,
                    "expected at most #{max} SELECTs against account_entries, got #{actual}:\n" +
                    @aerp_queries.map.with_index { |q, i| "  #{i + 1}. #{q[0, 200]}" }.join("\n"))
end

Then('the response should contain the detail pivot frame') do
  expect(page.body).to include(AccountEntryReportsController::DETAIL_FRAME_ID)
end

Then('the report should show an entry count of {string}') do |count|
  within(".card", text: "Entry Count") { expect(page).to have_content(count) }
end

Then('the report should show {string} folios touched') do |count|
  within(".card", text: "Folios Touched") { expect(page).to have_content(count) }
end

Then('the report should show {string} distinct entry names') do |count|
  within(".card", text: "Distinct Entry Names") { expect(page).to have_content(count) }
end

Then('the report total in cents should be {string}') do |total|
  report = aerp_report(@aerp_start_date, @aerp_end_date)
  expect(report.summary_kpis[:total_amount_cents].to_d).to eq(BigDecimal(total))
end

Then('the report should say the range was shortened') do
  expect(page).to have_content("wider than the")
end

Then('the report should not say the range was shortened') do
  expect(page).to have_no_content("wider than the")
end

Then('the report start date should be {string}') do |expected|
  # f.date_field renders a locale-formatted display input plus a hidden ISO input; the
  # hidden one carries the value that actually gets submitted, so assert on that.
  value = find("input[name='start_date']", visible: :all).value
  expect(Date.parse(value)).to eq(Date.parse(expected))
end

Then('the report start date should be no earlier than {string}') do |earliest|
  value = find("input[name='start_date']", visible: :all).value
  expect(Date.parse(value)).to be >= Date.parse(earliest)
end

Then('the report page should load successfully') do
  expect(page.status_code).to eq(200)
end

Then('the trend total for the whole fund should be {string}') do |total|
  trend = aerp_report("2024-01-01", "2024-03-31").trailing_trend
  actual = trend.values.sum { |periods| periods.values.sum.to_d }
  expect(actual).to eq(BigDecimal(total))
end

Then('the trend total filtered to folios {string} should be {string}') do |folios, total|
  ids = folios.split(",").map { |f| aerp_commitment!(f.strip).id }
  trend = aerp_report("2024-01-01", "2024-03-31", commitment_ids: ids).trailing_trend
  actual = trend.values.sum { |periods| periods.values.sum.to_d }
  expect(actual).to eq(BigDecimal(total))
end
