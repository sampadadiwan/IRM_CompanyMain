# frozen_string_literal: true

# Steps for the fund pages' JSON API used with a bearer token (features/api/*.feature).
# openspec/changes/funds-json-api-hardening/design.md#worked-examples — the H/E/X IDs in the features.
#
# The API is the website's own actions, so the setup reuses the fund steps (logged-in user,
# investors, fund, commitments, call) and these steps only add: tokens for named users, a second
# firm to aim at, bearer requests with {placeholder} ids, and assertions on status / headers / JSON.

# One Rack::Test session per caller, JSON in and out, with a bearer token.
class ApiJsonClient
  include Rack::Test::Methods

  attr_accessor :access_token

  def app
    Rails.application
  end

  def call(verb, path, body = nil)
    header "Content-Type", "application/json"
    header "Accept", "application/json"
    header "Authorization", access_token ? "Bearer #{access_token}" : nil
    send(verb, path, body)
    last_response
  end

  def json
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    nil
  end
end

module ApiJsonWorld
  # Users the scenarios name ("me" is the logged-in fund admin from the fund steps)
  def api_users
    @api_users ||= {}
  end

  def api_user(name)
    name == "me" ? @user : api_users.fetch(name)
  end

  def api_client(name)
    @api_clients ||= {}
    @api_clients[name] ||= ApiJsonClient.new
  end

  # A devise-api token for the user, the same kind the website and the mobile app accept
  def api_token_for!(name)
    user = api_user(name)
    token = Devise::Api::Token.create!(resource_owner: user,
                                       access_token: Devise::Api::Token.generate_uniq_access_token(user),
                                       refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user),
                                       expires_in: 1.day.to_i)
    api_client(name).access_token = token.access_token
  end

  # {fund}, {beta_fund}, {beta_entity}, … in paths and bodies → the shared setup's ids
  def api_ids
    @api_ids ||= {}
  end

  def api_fill(text)
    text.gsub(/\{(\w+)\}/) { api_ids.fetch(Regexp.last_match(1).to_sym) { raise "unknown placeholder {#{Regexp.last_match(1)}}" }.to_s }
  end

  def api_request(name, verb, path, body = nil)
    @last_api_client = api_client(name)
    @last_api_client.call(verb.downcase.to_sym, api_fill(path), body && api_fill(body))
  end

  def last_api_response
    (@last_api_client || raise("no API request has been made yet")).last_response
  end

  def last_api_json
    @last_api_client.json
  end

  # Dot path into the JSON body: "errors.due_date.0", "0.id"
  def api_dig(path)
    path.split(".").reduce(last_api_json) { |memo, key| memo.is_a?(Array) ? memo[key.to_i] : memo&.dig(key) }
  end

  # Makes the logged-in fund admin's records addressable as placeholders
  def api_remember_own_records!
    api_ids[:entity] = @entity.id
    api_ids[:fund] = @fund.id
    api_ids[:commitment] = @fund.capital_commitments.first&.id
    api_ids[:call] = @capital_call&.id
    api_ids[:remittance] = @capital_call&.capital_remittances&.first&.id
    api_ids[:first_investor] = @fund.capital_commitments.order(:id).first&.investor&.investor_name
  end
end
World(ApiJsonWorld)

# ── Setup ────────────────────────────────────────────────────────────────────

Given("I have an API token") do
  api_remember_own_records!
  api_token_for!("me")
end

Given("{string} is an employee of my firm with no fund access") do |name|
  api_users[name] = FactoryBot.create(:user, entity: @entity, first_name: name)
  api_users[name].add_role(:employee)
  api_token_for!(name)
end

Given("{string} is an employee of my firm with create access to the fund") do |name|
  api_users[name] = FactoryBot.create(:user, entity: @entity, first_name: name)
  api_users[name].add_role(:employee)
  AccessRight.create!(entity: @entity, owner: @fund, user_id: api_users[name].id, notify: false,
                      permissions: %i[create read update])
  api_token_for!(name)
end

Given("{string} is an investor user in the fund") do |name|
  investor = @fund.capital_commitments.first.investor
  api_users[name] = FactoryBot.create(:user, entity: investor.investor_entity, first_name: name)
  api_users[name].add_role(:investor)
  api_token_for!(name)
end

Given("{string} is a support user of my firm") do |name|
  api_users[name] = FactoryBot.create(:user, entity: @entity, first_name: name)
  api_users[name].add_role(:support)
  api_token_for!(name)
end

# E14 — a group company whose child entity is my firm
Given("{string} is a company admin of a group company that owns my firm") do |name|
  group = FactoryBot.create(:entity, name: "#{@entity.name} Group", entity_type: "Group Company")
  @entity.update!(parent_entity_id: group.id)
  api_users[name] = FactoryBot.create(:user, entity: group, first_name: name)
  api_users[name].add_role(:company_admin)
  api_token_for!(name)
end

# A second firm with its own fund, investor, commitment, call and remittance — the target of the
# cross-firm requests
Given("another firm {string} has a fund with a commitment, a call and a remittance") do |firm_name|
  beta = FactoryBot.create(:entity, name: firm_name, entity_type: "Investment Fund", enable_funds: true)
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor")
  investor = FactoryBot.create(:investor, entity: beta, investor_entity:, investor_name: investor_entity.name)
  fund = FactoryBot.create(:fund, entity: beta, name: "#{firm_name} Fund")
  commitment = FactoryBot.build(:capital_commitment, fund:, investor:, orig_folio_committed_amount_cents: 100_000_000)
  expect(CapitalCommitmentCreate.call(capital_commitment: commitment)).to be_success
  call = FactoryBot.build(:capital_call, fund:, entity: beta, percentage_called: 20)
  expect(CapitalCallCreate.call(capital_call: call)).to be_success

  api_ids.merge!(beta_entity: beta.id, beta_fund: fund.id, beta_commitment: commitment.id,
                 beta_call: call.id, beta_remittance: call.capital_remittances.first.id)
end

# X13 X14 — a payment on the remittance, with fund units allocated against the remittance for more
# than the rest of the collected amount, so the remittance and the payment both refuse to be deleted
Given("the remittance has a payment of {int} with units allocated") do |amount|
  remittance = CapitalRemittance.find(api_ids[:remittance])
  payment = CapitalRemittancePayment.new(capital_remittance: remittance, fund: remittance.fund, entity: remittance.entity,
                                         folio_amount: amount, payment_date: Time.zone.today)
  expect(CapitalRemittancePaymentCreate.call(capital_remittance_payment: payment)).to be_success
  FactoryBot.create(:fund_unit, entity: remittance.entity, fund: remittance.fund, owner: remittance,
                                capital_commitment: remittance.capital_commitment, investor: remittance.investor,
                                quantity: 10, price_cents: payment.amount_cents / 10, premium_cents: 0)
  api_ids[:payment] = payment.id
end

# H4 — remembers the distribution payment made by "there is a capital distribution payment for the fund"
Given("I remember that distribution payment") do
  api_ids[:distribution_payment] = @record.id
end

# ── Requests ────────────────────────────────────────────────────────────────

When("{string} sends {word} {string}") do |name, verb, path|
  api_request(name, verb, path)
end

When("{string} sends {word} {string} with:") do |name, verb, path, body|
  api_request(name, verb, path, body)
end

# X8 — the test environment raises instead of rendering, so capture what production would answer
When("{string} sends POST {string} without the request object") do |name, path|
  api_request(name, "POST", path, "{}")
rescue StandardError => e
  @api_exception = e
end

Then("Rails answers it as a bad request \\(400), not a server error") do
  expect(@api_exception).to be_a(ActionController::ParameterMissing)
  expect(ActionDispatch::ExceptionWrapper.status_code_for_exception(@api_exception.class.name)).to eq(400)
end

# ── Assertions ───────────────────────────────────────────────────────────────

Then("the API status is {int}") do |status|
  expect(last_api_response.status).to eq(status), "body: #{last_api_response.body.truncate(600)}"
end

Then("the API answer at {string} is {string}") do |path, value|
  expect(api_dig(path).to_s).to eq(api_fill(value))
end

Then("the API answer has an error on {string}") do |field|
  expect(last_api_json).to be_a(Hash)
  errors = last_api_json["errors"] || last_api_json
  expect(errors.keys).to include(field), "body: #{last_api_response.body.truncate(600)}"
end

Then("the API answer is a list of {int} row(s)") do |count|
  expect(last_api_json).to be_a(Array)
  expect(last_api_json.size).to eq(count)
end

Then("the API header {string} is {string}") do |name, value|
  expect(last_api_response.headers[name].to_s).to eq(value)
end

Then("the API header {string} mentions {string}") do |name, text|
  expect(last_api_response.headers[name].to_s).to include(text)
end

Then("the API answer is JSON") do
  expect(last_api_response.media_type).to eq("application/json")
  expect(last_api_json).not_to be_nil
end

# ── Records ──────────────────────────────────────────────────────────────────

Then("the capital call {string} has {int} remittance(s) in my firm") do |name, count|
  call = CapitalCall.find_by!(name:)
  expect(call.entity_id).to eq(@entity.id)
  expect(call.capital_remittances.count).to eq(count)
  expect(call.capital_remittances.where.not(entity_id: @entity.id)).to be_none
end

# E15 — the website's own form post (session cookie, no token) with the hidden firm field tampered
When("I submit the New Capital Call form on my fund with the firm set to {string}") do |firm_name|
  page.driver.submit :post, "/capital_calls",
                     capital_call: { fund_id: @fund.id, entity_id: Entity.find_by!(name: firm_name).id,
                                     name: "Tampered form", percentage_called: 10, call_date: "2026-10-20",
                                     due_date: "2026-11-20", call_basis: "Percentage of Commitment",
                                     fund_closes: ["All"] }
end

Then("the last {word} belongs to my firm") do |model_name|
  expect(model_name.constantize.order(:id).last.entity_id).to eq(@entity.id)
end

Then("the {word} with id {string} still exists") do |model_name, id|
  expect(model_name.constantize.exists?(api_fill(id))).to be(true)
end

Then("the {word} with id {string} is gone") do |model_name, id|
  expect(model_name.constantize.exists?(api_fill(id))).to be(false)
end

# X12 — the website's own answer to another firm's record, unchanged by this change
When("I open {string} in the browser") do |path|
  visit api_fill(path)
end

Then("the API answer mentions {string}") do |text|
  expect(last_api_response.body).to include(text)
end

Then("the {word} count is unchanged") do |model_name|
  expect(model_name.constantize.count).to eq(@api_counts.fetch(model_name))
end

Given("I note the {word} count") do |model_name|
  (@api_counts ||= {})[model_name] = model_name.constantize.count
end

Given("I note the collected amount of the remittance") do
  @api_collected_before = CapitalRemittance.find(api_ids[:remittance]).collected_amount_cents
end

Then("the collected amount of the remittance is unchanged") do
  expect(CapitalRemittance.find(api_ids[:remittance]).collected_amount_cents).to eq(@api_collected_before)
end

Then("the remittance's collected amount went up by {int}") do |amount|
  expect(CapitalRemittance.find(api_ids[:remittance]).collected_amount_cents - @api_collected_before).to eq(amount * 100)
end

# ── Reads (phase 5) ─────────────────────────────────────────────────────────

# The approved investor user of the n-th folio (from "there is an existing investor ... with 1 users")
Given("{string} is the investor user of folio {int}") do |name, n|
  commitment = @fund.capital_commitments.order(:id)[n - 1]
  user = InvestorAccess.find_by!(investor_id: commitment.investor_id, approved: true).user
  user.add_role(:investor)
  user.update!(curr_role: "investor")
  api_users[name] = user
  api_ids[:"folio#{n}"] = commitment.id
  api_token_for!(name)
end

Given("folio {int} has account entries of {string}") do |n, spec|
  commitment = @fund.capital_commitments.order(:id)[n - 1]
  # "NAV:1000,NAV:500,Fee:200" → one entry each
  spec.split(",").each_with_index do |pair, i|
    entry_type, amount = pair.split(":")
    FactoryBot.create(:account_entry, entity: @entity, fund: @fund, capital_commitment: commitment,
                                      investor: commitment.investor, folio_id: commitment.folio_id,
                                      entry_type:, name: "#{entry_type} #{i}", amount_cents: amount.to_i * 100,
                                      # this year: the ledger list defaults to entries after 1 Jan of the current year
                                      reporting_date: Time.zone.today)
  end
end

Given("folio {int} pays its remittance in full") do |n|
  commitment = @fund.capital_commitments.order(:id)[n - 1]
  remittance = commitment.capital_remittances.first
  payment = CapitalRemittancePayment.new(capital_remittance: remittance, fund: @fund, entity: @entity,
                                         folio_amount: remittance.folio_call_amount.to_f, payment_date: Time.zone.today)
  expect(CapitalRemittancePaymentCreate.call(capital_remittance_payment: payment)).to be_success
end

Given("I remember folio {int}") do |n|
  api_ids[:"folio#{n}"] = @fund.capital_commitments.order(:id)[n - 1].id
end

# H8 — the summary's figures are the fund's own rollups, so it equals what the overview shows
Then("the API answer matches the fund's own committed, called, collected and due amounts") do
  fund = @fund.reload
  expect(api_dig("committed_amount")).to eq(fund.committed_amount.to_f)
  expect(api_dig("call_amount")).to eq(fund.call_amount.to_f)
  expect(api_dig("collected_amount")).to eq(fund.collected_amount.to_f)
  expect(api_dig("due_amount")).to eq((fund.call_amount - fund.collected_amount).to_f)
  expect(fund.call_amount.to_f).to be_positive # a real call, so the comparison is not 0 = 0
end

Then("the API answer has the keys {string}") do |keys|
  expect(last_api_json.keys).to include(*keys.split(",").map(&:strip))
end

Given("my fund tracks in {string}") do |currency|
  @fund.update_column(:tracking_currency, currency)
end

# H19 — every fund list endpoint answers 200 with a JSON array for a bearer-token caller
Then("every fund list answers 200 with JSON for {string}") do |name|
  paths = %w[/funds.json /capital_commitments.json /capital_calls.json /capital_remittances.json
             /capital_remittance_payments.json /capital_distributions.json /capital_distribution_payments.json
             /account_entries.json /fund_units.json /fund_ratios.json /commitment_adjustments.json]
  failures = paths.filter_map do |path|
    response = api_request(name, "GET", "#{path}?fund_id={fund}")
    body = begin
      JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    end
    "#{path} → #{response.status} #{response.body.truncate(160)}" unless response.status == 200 && body.is_a?(Array)
  end
  expect(failures).to be_empty, failures.join("\n")
end

# ── Profile › API tokens (phase 6) ─────────────────────────────────────────

# H10 — a website session that has already passed two-factor (the code step itself is covered by the
# two-factor features); Warden signs the session in exactly as log_in does for other users
Given("I am signed in to the website with two-factor on") do
  @user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "authenticator")
  Warden.test_mode!
  login_as(@user, scope: :user)
  visit("/")
end

When("I create the API token {string} on Profile › API tokens") do |name|
  visit "/users/api_tokens"
  fill_in "api_token_name", with: name
  click_on "create_api_token"
end

Then("I see the new token once with a Copy button") do
  expect(page).to have_css("#new_api_token #api_token_value")
  expect(page).to have_css("#copy_api_token")
  expect(page).to have_content("Copy it now. It will not be shown again.")
  @shown_token = find("#api_token_value").text
  expect(@shown_token).to eq(ApiToken.order(:id).last.devise_api_token.access_token)
end

Then("reloading Profile › API tokens shows {string} without the token") do |name|
  visit "/users/api_tokens"
  expect(page).to have_css("#api_tokens", text: name)
  expect(page).not_to have_content(@shown_token)
end

# Mints through the model (the screen is covered by H10) and points the named caller at the token
Given("{string} has the API token {string}") do |name, token_name|
  api_token, access = ApiToken.mint!(user: api_user(name), name: token_name)
  @api_tokens_by_name = (@api_tokens_by_name || {}).merge(token_name => api_token)
  api_client(name).access_token = access
end

Given("{string} already has {int} live API tokens") do |name, count|
  count.times { |i| ApiToken.mint!(user: api_user(name), name: "Token #{i + 1}") }
end

Given("the API token {string} was created {int} days ago") do |token_name, days|
  api_token = @api_tokens_by_name.fetch(token_name)
  at = days.days.ago
  api_token.update_columns(created_at: at)
  api_token.devise_api_token.update_columns(created_at: at)
end

Given("the API token {string} is revoked") do |token_name|
  @api_tokens_by_name.fetch(token_name).revoke!
end

Given("the API token {string} was last used {int} minutes ago") do |token_name, minutes|
  @api_tokens_by_name.fetch(token_name).update_columns(last_used_at: minutes.minutes.ago)
  @last_used_before = @api_tokens_by_name.fetch(token_name).reload.last_used_at
end

Then("the API token {string} last-used time is unchanged") do |token_name|
  expect(@api_tokens_by_name.fetch(token_name).reload.last_used_at).to be_within(1.second).of(@last_used_before)
end

Then("the API token {string} was just used") do |token_name|
  expect(@api_tokens_by_name.fetch(token_name).reload.last_used_at).to be > 1.minute.ago
end

When("I revoke {string} on Profile › API tokens") do |token_name|
  api_token = @api_tokens_by_name.fetch(token_name)
  visit "/users/api_tokens"
  # rack_test: the modal's form is in the page, so its button submits directly
  click_on "confirm_revoke_api_token_#{api_token.id}"
end

When("I try to create another API token on Profile › API tokens") do
  step 'I create the API token "One too many" on Profile › API tokens'
end

Then("{string} has {int} live API token(s)") do |name, count|
  expect(ApiToken.live.where(user_id: api_user(name).id).count).to eq(count)
end

# X19 — another signed-in user sends the revoke for Meera's token
When("{string} tries to revoke the API token {string} from the website") do |name, token_name|
  Warden.test_mode!
  login_as(api_user(name), scope: :user)
  page.driver.submit :delete, "/users/api_tokens/#{@api_tokens_by_name.fetch(token_name).id}", {}
end

Then("the API token {string} is still live") do |token_name|
  expect(@api_tokens_by_name.fetch(token_name).reload).to be_live
end

# X21 — devise-api's refresh endpoint, called with the API token's refresh token
When("{string} tries to refresh the API token {string}") do |name, token_name|
  @last_api_client = api_client(name)
  refresh = @api_tokens_by_name.fetch(token_name).devise_api_token.refresh_token
  @last_api_client.header "Authorization", "Bearer #{refresh}"
  @last_api_client.post "/users/tokens/refresh"
end

# E20 — a signed-in phone for the user, beside the API token
Given("{string} is signed in on a phone") do |name|
  MobileDevice.register!(api_user(name), install_id: "install-api-tokens", platform: "ios", name: "Meera's iPhone")
end

Then("Profile › Devices lists only the phone") do
  visit "/users/mobile_devices"
  expect(page).to have_css("#mobile_devices", text: "Meera's iPhone")
  expect(page).not_to have_content("Quarterly script")
end

Then("Profile › API tokens lists only the token") do
  visit "/users/api_tokens"
  expect(page).to have_css("#api_tokens", text: "Quarterly script")
  expect(page).not_to have_content("Meera's iPhone")
end

# ── Lists (phase 4) ─────────────────────────────────────────────────────────

# Each call generates one remittance per commitment, so N calls on a 2-folio fund add 2N remittances
Given("there are {int} more capital calls on my fund") do |count|
  count.times do |i|
    call = FactoryBot.build(:capital_call, fund: @fund, entity: @entity, name: "More #{i + 1}", percentage_called: 1)
    expect(CapitalCallCreate.call(capital_call: call)).to be_success
  end
  api_remember_own_records!
end

# E7 — the website asking for the same list with its session cookie (no token)
When("the website reads {string}") do |path|
  visit api_fill(path)
  @website_json = JSON.parse(page.body)
end

Then("the website gets a list of {int} row(s)") do |count|
  expect(@website_json.size).to eq(count)
end

# ── Onboarding-agent additions (phase 3, G8–G10) ─────────────────────────────

def api_insert_import_upload(entity:, fund:, user:, **extra)
  ImportUpload.insert!(
    { entity_id: entity.id, owner_type: "Fund", owner_id: fund.id, user_id: user.id, name: "Commitments",
      import_type: "CapitalCommitment", status: "Processed",
      import_file_data: { id: "in.xlsx", storage: "store", metadata: {} }.to_json,
      created_at: Time.current, updated_at: Time.current }.merge(extra), returning: :id
  ).rows.first.first
end

# An import upload with a known outcome. Inserted directly: creating one through the model runs the
# import job inline, and these scenarios are about what the JSON reports, not the importer.
Given("my fund has an import upload of {int} rows with {int} failed and a results file") do |total, failed|
  api_ids[:import_upload] = api_insert_import_upload(
    entity: @entity, fund: @fund, user: @user, total_rows_count: total, processed_row_count: total - failed,
    failed_row_count: failed, custom_fields_created: "Source;Region",
    import_results_data: { id: "results.xlsx", storage: "store", metadata: {} }.to_json
  )
end

# E23 — still pending: no counts yet and no results file
Given("my fund has a pending import upload") do
  api_ids[:import_upload] = api_insert_import_upload(entity: @entity, fund: @fund, user: @user, status: nil)
end

Given("{string} has an import upload") do |firm_name|
  firm = Entity.find_by!(name: firm_name)
  api_ids[:beta_import_upload] = api_insert_import_upload(entity: firm, fund: Fund.find(api_ids[:beta_fund]),
                                                          user: FactoryBot.create(:user, entity: firm))
end

Given("my firm is in sandbox mode with sandbox emails {string}") do |emails|
  setting = @entity.entity_setting || @entity.create_entity_setting!
  setting.update!(sandbox: true, sandbox_emails: emails)
end

# H18 X26 — the deletion job itself is the importer's business; here only whether it was started
Given("import data deletion jobs are watched") do
  allow(ImportUploadDeleteAllJob).to receive(:perform_later)
end

Then("an import data deletion job was started for the upload") do
  expect(ImportUploadDeleteAllJob).to have_received(:perform_later).with(api_ids[:import_upload], anything)
end

Then("no import data deletion job was started") do
  expect(ImportUploadDeleteAllJob).not_to have_received(:perform_later)
end

# E24 — the upload page's own Delete data request (session cookie, no token)
When("I delete the import upload's data from the website") do
  page.driver.submit :delete, "/import_uploads/#{api_ids[:import_upload]}/delete_data", {}
end

Then("the API answer has no {string}") do |key|
  expect(last_api_json).not_to have_key(key)
end

Then("the API answer at {string} is present") do |path|
  expect(api_dig(path)).to be_present
end

Then("the API answer at {string} is null") do |path|
  expect(api_dig(path)).to be_nil
end
