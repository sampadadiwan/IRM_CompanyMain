# Steps for the 2026-10 security review findings C4 (secondary_sales#report removed), C7 (CKYC / KRA
# data authorized against its KYC), H16 (entities#report removed) and L10 (deal activity reorder
# endpoints removed). Design and worked examples: docs/security/security_review_2026_10.md (cards
# "C4", "C7", "H16" and the L10 row of "Core / misc — Medium and Low").
#
# Requests go through the rack_test driver as the signed-in user, the way a crafted URL or form
# would. @user / @entity come from the shared "Im logged in as a user ... for an entity" step;
# "I am denied access" (tenant_isolation_batch1_steps.rb) checks for the Access Denied flash.

module SecurityC4C7H16L10Helpers
  # Sends one request as the signed-in user and keeps its status and body. A removed route raises
  # ActionController::RoutingError in tests (show_exceptions is off) where production answers 404.
  def sr_request(method, path, params = {})
    # Submit through the driver so redirects are followed like a browser would
    page.driver.submit(method, path, params)
    @sr_status = page.status_code
    @sr_body = page.html
  rescue ActionController::RoutingError
    # No route matched: what a user gets in production is a 404 with nothing of the record in it
    @sr_status = 404
    @sr_body = ""
  end

  # A fresh session signed in as `user`, so a scenario can act as a second person
  def sr_sign_in(user)
    Capybara.reset_sessions!
    log_in(user)
  end

  # C7: CKYC / KRA service calls made during the scenario, in order (the services are stubbed)
  def c7_calls
    @c7_calls ||= []
  end

  # C7: an individual KYC of my firm with one CKYC row (OTP stage) and one KRA row (failed fetch),
  # both on the KYC's PAN so InvestorKyc#ckyc_data / #kra_data find them.
  def c7_kyc_with_data(pan, investor_name)
    # The KYC's investor, an LP entity of its own
    lp_entity = FactoryBot.create(:entity, name: investor_name, entity_type: "Investor")
    investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: lp_entity.id,
                                            investor_name:, category: "LP")
    # The KYC itself, unverified so its edit rights are live
    kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual", PAN: pan,
                                           verified: false)
    # One row per source, as the fetch flows create them
    ckyc = KycData.create!(entity: @entity, investor_kyc: kyc, source: "ckyc", PAN: pan,
                           phone: "9876543210", status: "OTP Sent")
    kra = KycData.create!(entity: @entity, investor_kyc: kyc, source: "kra", PAN: pan,
                          birth_date: kyc.birth_date, status: "Failed")
    [kyc, ckyc, kra]
  end

  # C7: the KYC's row for a source name as written in the feature ("CKYC" / "KRA")
  def c7_row(source)
    { "ckyc" => @c7_ckyc, "kra" => @c7_kra }.fetch(source.downcase)
  end

  # C7-5: a commitment of the KYC's investor to `fund_name`, carrying the KYC
  def c7_commit(kyc, fund_name)
    fund = Fund.find_by(entity_id: @entity.id, name: fund_name) || FactoryBot.create(:fund, entity: @entity, name: fund_name)
    FactoryBot.create(:capital_commitment, fund:, entity: @entity, investor: kyc.investor, investor_kyc: kyc)
    fund
  end

  # L10: the deal's template step titles in their current order
  def l10_template_titles
    DealActivity.where(deal: @deal, deal_investor_id: nil).order(:sequence).pluck(:title)
  end
end
World(SecurityC4C7H16L10Helpers)

# ---- Shared -----------------------------------------------------------------------------------

Then('the address is not found') do
  expect(@sr_status).to eq(404)
end

Given('I am signed in as a company admin of another firm {string}') do |name|
  # Another firm of the same kind, with every feature on, so a refusal is the rule under test
  entity = FactoryBot.create(:entity, name:, entity_type: "Investment Fund")
  outsider = FactoryBot.create(:user, entity:)
  outsider.add_role(:company_admin)
  sr_sign_in(outsider)
end

# ---- C4 ---------------------------------------------------------------------------------------

# Reuses the sale-access steps: a seller with an approved offer and a buyer with a short-listed
# interest, each an employee of their own investor entity. The offer and interest carry the PAN and
# bank account the removed report used to print.
Given('the sale has a seller with an approved offer and a buyer with a short-listed interest') do
  @c4_parties = {}
  steps %(
    Given there is an existing investor entity "investor_name=Seller;entity_type=Investor" with employee "first_name=Sell"
    And the investor has "Seller" access rights to the sale
    And the investor has an offer "quantity=10;PAN=SELLR1234P;bank_account_number=99887766554433" for the sale
    And the offer is approved
  )
  @c4_parties["seller"] = @employee_investor
  steps %(
    Given there is an existing investor entity "investor_name=Buyer;entity_type=Investor" with employee "first_name=Buy"
    And the investor has "Buyer" access rights to the sale
    And the investor has an interest "quantity=10;short_listed_status=short_listed;verified=true;PAN=BUYER1234Q" for the sale
  )
  @c4_parties["buyer"] = @employee_investor
end

When("the sale's {string} opens the sale's report address with report {string}") do |party, report|
  sr_sign_in(@c4_parties.fetch(party))
  # Literal path: the route helper went with the route
  sr_request(:get, "/secondary_sales/#{@sale.id}/report", report:)
end

When("the sale's {string} downloads the sale sheet as xlsx") do |party|
  sr_sign_in(@c4_parties.fetch(party))
  sr_request(:get, download_secondary_sale_path(@sale, format: :xlsx))
end

Then('no seller or buyer PAN or bank account is in the response') do
  [@offer.PAN, @offer.bank_account_number, @interest.PAN].each do |value|
    expect(@sr_body).not_to include(value)
  end
end

# ---- C7 ---------------------------------------------------------------------------------------

Given('the CKYC and KRA services are stubbed') do
  calls = c7_calls
  # Each paid call is recorded and answers success, so a refusal shows as "no call at all"
  allow_any_instance_of(CkycKraService).to receive(:get_kra_data) do |*|
    calls << :get_kra_data
    [true, "KRA data fetched"]
  end
  allow_any_instance_of(CkycKraService).to receive(:send_ckyc_otp) do |*|
    calls << :send_ckyc_otp
    [true, "OTP has been sent to the registered mobile number", "req-1"]
  end
  allow_any_instance_of(CkycKraService).to receive(:search_ckyc_data_and_send_otp) do |*|
    calls << :search_ckyc_data_and_send_otp
    [true, "OTP has been sent to the registered mobile number", "req-1"]
  end
  allow_any_instance_of(CkycKraService).to receive(:get_ckyc_data) do |*|
    calls << :get_ckyc_data
    [true, "CKYC data downloaded"]
  end
end

Given('the KYC {string} of my firm has CKYC and KRA data') do |pan|
  @c7_kyc, @c7_ckyc, @c7_kra = c7_kyc_with_data(pan, "Ravi Iyer")
end

Given('I am signed in as an employee of my firm with KYC create and update rights') do
  employee = FactoryBot.create(:user, entity: @entity)
  # The two toggles the design names: update reveals every KYC of the firm, create allows the fetches
  employee.extended_permissions.set(:investor_kyc_create)
  employee.extended_permissions.set(:investor_kyc_update)
  employee.save!
  sr_sign_in(employee)
end

Given('the KYC is committed only to my fund {string}') do |fund_name|
  c7_commit(@c7_kyc, fund_name)
end

Given('a second KYC {string} of my firm with CKYC and KRA data is committed to my fund {string}') do |pan, fund_name|
  @c7_second_kyc, = c7_kyc_with_data(pan, "Meera Rao")
  c7_commit(@c7_second_kyc, fund_name)
end

Given('I am signed in as an employee of my firm with access to the fund {string} only') do |fund_name|
  fund = Fund.find_by!(entity_id: @entity.id, name: fund_name)
  # No KYC toggles: what this employee sees of KYCs follows from their fund access alone
  employee = FactoryBot.create(:user, entity: @entity)
  AccessRight.create!(owner: fund, entity_id: @entity.id, user_id: employee.id, notify: false)
  sr_sign_in(employee)
end

When('I open the CKYC and KRA comparison of the KYC') do
  sr_request(:get, compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @c7_kyc.id))
end

When("I ask to re-fetch the KYC's KRA data") do
  sr_request(:put, refresh_kyc_data_path(@c7_kra))
end

When("I ask to send a CKYC OTP for the KYC's CKYC data") do
  sr_request(:get, send_ckyc_otp_kyc_data_path(@c7_ckyc))
end

When("I ask to delete the KYC's {string} data") do |source|
  sr_request(:delete, kyc_data_path(c7_row(source)))
end

Given("the KYC's CKYC data is a successful fetch") do
  @c7_ckyc.update_columns(status: "Success")
end

Then("the KYC's PAN is not in the response") do
  expect(@sr_body).not_to include(@c7_kyc.PAN)
end

Then('no CKYC or KRA service was called') do
  expect(c7_calls).to be_empty
end

Then("the KYC's {string} data still exists") do |source|
  expect(KycData.exists?(c7_row(source).id)).to be true
end

Then("the KYC's {string} data is deleted") do |source|
  expect(KycData.exists?(c7_row(source).id)).to be false
end

Then('I can open the CKYC and KRA comparison of the KYC') do
  sr_request(:get, compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @c7_kyc.id))
  expect(page).not_to have_text("Access Denied")
  # The side-by-side cards show the fetched rows' PAN
  expect(page).to have_text(@c7_kyc.PAN)
end

Then('I can open the CKYC and KRA comparison of the second KYC') do
  sr_request(:get, compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @c7_second_kyc.id))
  expect(page).not_to have_text("Access Denied")
  expect(page).to have_text(@c7_second_kyc.PAN)
end

Then("I can re-fetch the KYC's KRA data") do
  sr_request(:put, refresh_kyc_data_path(@c7_kra))
  expect(page).not_to have_text("Access Denied")
  expect(c7_calls).to include(:get_kra_data)
end

Then("I can download the KYC's CKYC data with an OTP") do
  # The OTP page's form posts the OTP with the request id the send step returned
  sr_request(:put, download_ckyc_with_otp_kyc_data_path(@c7_ckyc), otp: "123456", request_id: "req-1")
  expect(page).not_to have_text("Access Denied")
  expect(c7_calls).to include(:get_ckyc_data)
end

# ---- H16 --------------------------------------------------------------------------------------

When('I open the report address of {string} with report {string}') do |name, report|
  # Literal path: the route helper went with the route. b2_entities holds Artha and the other tenant.
  sr_request(:get, "/entities/#{b2_entities.fetch(name).id}/report", report:)
end

Then('neither {string} nor {string} is in the response') do |first, second|
  expect(@sr_body).not_to include(first)
  expect(@sr_body).not_to include(second)
end

When('I open the edit page of my company') do
  visit edit_entity_path(@entity)
end

Then("I see my company's edit form") do
  expect(page).not_to have_text("Access Denied")
  expect(page).to have_field("entity_name", disabled: true, with: @entity.name)
  expect(page).to have_field("entity_pan")
end

# ---- L10 --------------------------------------------------------------------------------------

When('they post a new position for the deal step {string} to the old reorder address') do |title|
  step_row = DealActivity.find_by!(deal: @deal, deal_investor_id: nil, title:)
  # The body the removed kanban drag handler sent
  sr_request(:post, "/deal_activities/update_sequences", dragged_column_id: step_row.id, new_position: 3)
end

When('they open the old single-step reorder address for the deal step {string}') do |title|
  step_row = DealActivity.find_by!(deal: @deal, deal_investor_id: nil, title:)
  sr_request(:get, "/deal_activities/#{step_row.id}/update_sequence", sequence: 2)
end

When('I set the order of the deal step {string} to {int} from its edit form') do |title, position|
  step_row = DealActivity.find_by!(deal: @deal, deal_investor_id: nil, title:)
  # The same PATCH the activity edit form sends for its "Sequence / Order" field
  sr_request(:patch, deal_activity_path(step_row), deal_activity: { sequence: position })
end

Then("the deal's template steps are in the order {string}") do |titles|
  expect(l10_template_titles).to eq(titles.split(",").map(&:strip))
end
