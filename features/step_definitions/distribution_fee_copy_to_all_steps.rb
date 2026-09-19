# Steps for features/fund/distribution_fee_copy_to_all.feature
#
# "my browser sends an Accept-Language header of {string}" is reused from
# ransack_filter_date_locale_steps.rb — do not redefine it here.
#
# Every fee row repeats the same element ids (fee_start_date, fee_end_date, ...),
# because _distribution_fee_fields.html.erb hard-codes them, so every interaction
# below has to be scoped to a single .nested-fields row. That is the same reason
# capital_distribution.rb wraps its fills in `within all('.nested-fields').last`.

# The visible, typeable half of a locale-date widget: it carries the id and no name.
FEE_START_DISPLAY = "#fee_start_date".freeze
# The submitted half: ISO value, real name, no id. Always :all — it is type="hidden".
FEE_START_HIDDEN  = "input[name*='[start_date]']".freeze

def fee_rows
  all(".nested-fields")
end

def fee_row_start_display(row)
  row.find(FEE_START_DISPLAY).value
end

def fee_row_start_hidden(row)
  row.find(FEE_START_HIDDEN, visible: :all).value
end

When('I open the new Capital Distribution form for {string}') do |fund_name|
  fund = Fund.find_by!(name: fund_name)
  visit(fund_path(fund))
  click_on("Distributions")
  click_on("New Distribution")
  expect(page).to have_field("capital_distribution_title", wait: 15)
end

When('I add {string} distribution fee rows') do |count|
  count.to_i.times do |i|
    click_link("Add Account Entries")
    # cocoon appends into #form_distribution_fee; wait for the row to exist before
    # adding the next one, or the clicks race the insertion.
    expect(page).to have_selector(".nested-fields", count: i + 1, wait: 10)
  end
end

When('I fill in the first fee row start date with {string}') do |value|
  within(fee_rows.first) { fill_in("fee_start_date", with: value) }
end

When('I fill in the second fee row start date with {string}') do |value|
  within(fee_rows[1]) { fill_in("fee_start_date", with: value) }
end

When('I copy the first fee row to all rows') do
  # distribution_fee_fields_controller#connect hides every copy link but the first
  # row's, so this is the only visible one.
  within(fee_rows.first) { click_link("Copy To All") }
end

# NOTE: do NOT write `expect(values).to all(eq(x))` in a Cucumber step. Capybara's
# DSL defines `all` as a DOM finder and it is mixed into the World, so it shadows
# RSpec's `all` matcher — the matcher object gets passed to Capybara as a CSS
# selector and Playwright fails with `Unexpected token "#" while parsing css
# selector "#<RSpec::Matchers::BuiltIn::Eq:...>"`. Compare whole arrays instead.
def expect_every_fee_row(values, expected, what)
  expect(values).not_to be_empty, "no fee rows on the form"
  expect(values).to eq(Array.new(values.size, expected)),
                    "expected every fee row to #{what} #{expected.inspect}, got #{values.inspect}"
end

Then('every fee row start date should display {string}') do |expected|
  # The point of the fix: this is the VISIBLE field, so an ISO leak shows up here.
  expect_every_fee_row(fee_rows.map { |row| fee_row_start_display(row) }, expected, "display")
end

Then('every fee row should submit the start date {string}') do |expected|
  # ...and this is what the server actually receives, which must stay ISO.
  expect_every_fee_row(fee_rows.map { |row| fee_row_start_hidden(row) }, expected, "submit")
end
