# Onboarding read-backs: G45 fund unit settings JSON (features/api/fund_unit_settings_json.feature) and the payments
# list N+1 (features/api/funds_json_api_lists.feature H16, E9)

# Unit settings for the fund, in the given order (the index lists them by id)
Given("the fund has the unit settings:") do |table|
  table.hashes.each do |row|
    FactoryBot.create(:fund_unit_setting, entity: @entity, fund: @fund, name: row["name"], management_fee: row["management_fee"],
                                          setup_fee: row["setup_fee"], carry: row["carry"], gp_units: row["gp_units"] == "true")
  end
end

# The fund from 'there is a second fund … for the entity' (@fund_b), addressable as {fund_b}
Given("the second fund has a unit setting {string}") do |name|
  FactoryBot.create(:fund_unit_setting, entity: @entity, fund: @fund_b, name:)
  api_ids[:fund_b] = @fund_b.id
end

# Ties one class to an import upload, as a FundUnitSetting import would; the upload is inserted directly (no import job)
Given("the unit setting {string} was written by an import upload") do |name|
  api_ids[:import_upload] = api_insert_import_upload(entity: @entity, fund: @fund, user: @user, import_type: "FundUnitSetting")
  @fund.fund_unit_settings.find_by!(name:).update_column(:import_upload_id, api_ids[:import_upload])
end

# ── Payments list N+1 (funds_json_api_lists.feature H16, E9) ─────────────────

# Pays every remittance of the fund in full, like 'the remittances are paid' does for one call
Given("every remittance of my fund is paid") do
  @fund.capital_remittances.where.missing(:capital_remittance_payments).find_each do |cr|
    crp = cr.capital_remittance_payments.new(fund_id: cr.fund_id, entity_id: cr.entity_id,
                                             folio_amount_cents: cr.folio_call_amount_cents, payment_date: cr.remittance_date)
    CapitalRemittancePaymentCreate.call(capital_remittance_payment: crp)
  end
end

Then("every payment in the API answer names a folio of my fund") do
  folios = @fund.capital_commitments.pluck(:folio_id)
  # Not `all(be_in(…))`: in the Cucumber world `all` is the browser driver's element finder
  expect(last_api_json.pluck("folio_id") - folios).to be_empty
end

# SQL statements run while serving one API GET (schema and cached queries excluded)
def api_sql_count_for(path)
  count = 0
  counter = lambda do |*, payload|
    count += 1 unless payload[:name].in?(%w[SCHEMA CACHE]) || payload[:cached]
  end
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { api_request("me", "GET", path) }
  count
end

When("I count the SQL queries for {string}") do |path|
  @first_query_count = api_sql_count_for(path)
end

When("I count the SQL queries again for {string}") do |path|
  @second_query_count = api_sql_count_for(path)
end

Then("the second query count is the same as the first") do
  expect(@second_query_count).to eq(@first_query_count), "2 payments: #{@first_query_count} queries, 12 payments: #{@second_query_count}"
end
