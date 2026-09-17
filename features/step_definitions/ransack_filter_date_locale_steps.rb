# Steps for features/core/ransack_filter_date_locale.feature — covers the generic
# Ransack condition-builder filter's date-attribute value field.

Given('there is an existing capital commitment for {string} and {string} with committed amount {string} and commitment date {string}') do |fund_name, _investor_name, committed_amount, commitment_date|
  fund     = @entity.funds.find_by!(name: fund_name)
  investor = @investor # set by "there is an existing investor" step
  amount_cents = (committed_amount.to_d * 100).to_i

  @capital_commitment = FactoryBot.create(:capital_commitment,
    entity: @entity, fund: fund, investor: investor,
    folio_id: SecureRandom.hex(4),
    unit_type: fund.unit_types.split(",").first&.strip,
    folio_currency: fund.currency,
    folio_committed_amount_cents: amount_cents,
    committed_amount_cents: amount_cents,
    commitment_date: Date.parse(commitment_date),
    skip_cf_before_save: true)
end

# Forces the following page load(s) to report a specific browser locale, which
# WithLocale#extract_locale_from_accept_language_header reads to set I18n.locale.
# Requires a Playwright page to already exist, hence the throwaway visit first.
Given('my browser sends an Accept-Language header of {string}') do |locale|
  visit(capital_commitments_path)
  page.driver.with_playwright_page do |pw_page|
    pw_page.set_extra_http_headers("Accept-Language" => locale)
  end
end

When('I select {string} as the filter attribute') do |label|
  select(label, from: first(".attribute-select")[:id])
end

Then('the filter value field should be the locale-date widget') do
  # first(".row.form-group") would grab the wrong row here — capital_commitments'
  # filter_ext partial renders its own "Fund Name" row with the same row/form-group
  # classes, before the Ransack condition-builder row. Scope from the attribute
  # select (unique to condition rows) up to its own row instead.
  row = find(".attribute-select").find(:xpath, "./ancestor::div[contains(@class, 'form-group')]")
  expect(row).to have_css(".value-field-date")
  expect(row).to have_no_css(".value-field-text")
end

When('I fill in the filter date with {string}') do |value|
  find(".value-field-date input[type='text']").set(value)
end

When('I submit the filter') do
  find(".search-button").click
end
