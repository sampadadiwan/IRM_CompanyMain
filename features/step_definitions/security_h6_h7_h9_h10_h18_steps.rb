# frozen_string_literal: true

# Steps for the 2026-10 security review findings H6 (bulk actions), H7 (account_entries#delete_all),
# H9 (Fund#master_fund_id), H10 (parent ids on payments, remittances, fund units) and H18 (LPs listing
# staff-only fund records). Design and worked examples: docs/security/security_review_2026_10.md.
#
# Requests go through the bearer-token JSON API (features/step_definitions/api_json_steps.rb: api_users,
# api_ids placeholders, "{string} sends {word} {string}", "the API status is {int}"), so each scenario
# exercises the real controller, policy and (inline) job. These steps only add the records, users and
# assertions the findings need.

module SecurityH6H7H9H10H18World
  # An employee of my firm by name, created once and reused, with a bearer token (H6, H7)
  def h_employee(name)
    api_users[name] ||= begin
      user = FactoryBot.create(:user, entity: @entity, first_name: name)
      user.add_role(:employee)
      user
    end
    api_token_for!(name) unless api_client(name).access_token
    api_users[name]
  end

  # "read,update" → %i[read update]
  def h_permissions(spec)
    spec.split(",").map { |perm| perm.strip.to_sym }
  end

  # A fund of my firm, or of the other firm, by name
  def h_fund(name)
    Fund.find_by!(name:)
  end

  # Account entries on a fund's first commitment: "Fee:200,NAV:500" → one entry each
  def h_add_entries(fund, spec)
    commitment = fund.capital_commitments.order(:id).first
    spec.split(",").each_with_index do |pair, i|
      entry_type, amount = pair.split(":")
      FactoryBot.create(:account_entry, entity: fund.entity, fund:, capital_commitment: commitment,
                                        investor: commitment.investor, folio_id: commitment.folio_id,
                                        entry_type:, name: "#{entry_type} #{i}", amount_cents: amount.to_i * 100,
                                        reporting_date: Time.zone.today)
    end
  end

  # A fund with one commitment and one call (so one remittance) in the given firm
  def h_fund_with_remittance(entity, name)
    investor_entity = FactoryBot.create(:entity, entity_type: "Investor")
    investor = FactoryBot.create(:investor, entity:, investor_entity:, investor_name: investor_entity.name)
    fund = FactoryBot.create(:fund, entity:, name:)
    commitment = FactoryBot.build(:capital_commitment, fund:, investor:, orig_folio_committed_amount_cents: 100_000_000)
    expect(CapitalCommitmentCreate.call(capital_commitment: commitment)).to be_success
    call = FactoryBot.build(:capital_call, fund:, entity:, percentage_called: 20)
    expect(CapitalCallCreate.call(capital_call: call)).to be_success
    [fund, commitment, call, call.capital_remittances.first]
  end
end
World(SecurityH6H7H9H10H18World)

# ── Users ────────────────────────────────────────────────────────────────────

# H6-7, H6-X1, H7-2, H7-X1 — an employee of my firm holding an access right with these permissions
Given("{string} is an employee of my firm with {string} access to my fund") do |name, perms|
  AccessRight.create!(entity: @entity, owner: @fund, user_id: h_employee(name).id, notify: false,
                      permissions: h_permissions(perms))
end

Given("{string} is an employee of my firm with {string} access to the fund named {string}") do |name, perms, fund_name|
  AccessRight.create!(entity: @entity, owner: h_fund(fund_name), user_id: h_employee(name).id, notify: false,
                      permissions: h_permissions(perms))
end

# H18-7 — a company admin of another fund firm, with a token
Given("{string} is a company admin of another firm {string}") do |name, firm_name|
  firm = FactoryBot.create(:entity, name: firm_name, entity_type: "Investment Fund", enable_funds: true)
  api_users[name] = FactoryBot.create(:user, entity: firm, first_name: name)
  api_users[name].add_role(:company_admin)
  api_token_for!(name)
end

# H18-X1 — an advisor granted on the investor of folio n (AddFolioInvestorAdvisor), then switched into it
# exactly as the persona picker does (InvestorAdvisor#switch): a curr_role "investor" user of that entity
Given("an advisor {string} is switched into the investor of folio {int}") do |name, n|
  investor_name = @fund.capital_commitments.order(:id)[n - 1].investor.investor_name
  steps %(
    Given "#{investor_name}" has an approved advisor "#{name}" from "Wise Advisors"
    And the advisor "#{name}" is switched into "#{investor_name}"
  )
  # evergreen_advisor: the advisor user the grant step created (evergreen_advisor_steps.rb)
  api_users[name] = evergreen_advisor(name).reload
  expect(api_users[name].curr_role).to eq("investor")
  api_token_for!(name)
end

# ── Fund records ─────────────────────────────────────────────────────────────

# H6-X1, H7-X1, H10-X1 — a second fund of my firm with its own commitment, call and remittance
Given("my firm has a second fund {string} with a commitment, a call and a remittance") do |name|
  fund, commitment, call, remittance = h_fund_with_remittance(@entity, name)
  api_ids.merge!(second_fund: fund.id, second_commitment: commitment.id, second_call: call.id,
                 second_remittance: remittance.id)
end

Given("the fund {string} has account entries of {string}") do |fund_name, spec|
  h_add_entries(h_fund(fund_name), spec)
end

# H7-X2 — the other firm's fund (from "another firm {string} has a fund with a commitment, a call and a remittance")
Given("the other firm's fund has account entries of {string}") do |spec|
  h_add_entries(Fund.find(api_ids.fetch(:beta_fund)), spec)
end

Given("the fund {string} has an enabled formula {string}") do |fund_name, formula_name|
  fund = h_fund(fund_name)
  FundFormula.create!(entity_id: fund.entity_id, fund:, name: formula_name, entry_type: "Expense",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: "0", sequence: 1)
end

# H18 — one record of each staff-only model on my fund (the call comes from the Background)
Given("my fund also has the staff-only records: a formula {string}, a fund report, a distribution, a unit setting and a ratio formula") do |formula_name|
  FundFormula.create!(entity_id: @fund.entity_id, fund: @fund, name: formula_name, entry_type: "Expense",
                      enabled: true, rule_type: "GenerateAccountEntry", formula: "0", sequence: 1)
  FundReport.create!(fund: @fund, entity: @fund.entity, name: "Staff Report")
  FactoryBot.create(:capital_distribution, fund: @fund, entity: @fund.entity, generate_payments: false)
  # A unit setting's name must be one of the fund's unit types
  @fund.update_column(:unit_types, "A")
  FactoryBot.create(:fund_unit_setting, fund: @fund.reload, entity: @fund.entity, name: "A")
  api_ids[:ratio_formula] = FactoryBot.create(:ratio_formula, fund: @fund, entity: @fund.entity).id
end

# H6-5 — the KYC of folio n's investor, not yet verified
Given("folio {int} has a KYC that is not verified") do |n|
  investor = @fund.capital_commitments.order(:id)[n - 1].investor
  @h_kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, verified: false, completed_by_investor: false)
  api_ids[:kyc] = @h_kyc.id
end

# H6-6 — a document the LP uploaded on their own commitment: the one kind of row the documents bulk
# menu gives an LP (DocumentsController#fetch_rows keeps a non-admin's own uploads)
Given("{string} uploaded a document {string} on folio {int}") do |name, doc_name, n|
  commitment = @fund.capital_commitments.order(:id)[n - 1]
  folder = commitment.document_folder || Folder.where(entity_id: @entity.id).order(:id).first!
  @h_document = Document.create!(name: doc_name, text: "Uploaded by the LP", entity: @entity, folder:,
                                 owner: commitment, user: api_user(name),
                                 file: File.new("public/img/whatsappQR.png", "r"))
  api_ids[:"folio#{n}"] = commitment.id
end

# H9-H, H9-X2 — another fund of my own firm to act as master
Given("my firm has a master fund {string}") do |name|
  api_ids[:master_fund] = FactoryBot.create(:fund, entity: @entity, name:).id
end

Given("my fund is a feeder of {string}") do |name|
  @fund.update_column(:master_fund_id, h_fund(name).id)
end

# H10 — a payment on the remembered remittance, without units (cf. "... with units allocated")
Given("the remittance has a plain payment of {int}") do |amount|
  remittance = CapitalRemittance.find(api_ids[:remittance])
  payment = CapitalRemittancePayment.new(capital_remittance: remittance, fund: remittance.fund, entity: remittance.entity,
                                         folio_amount: amount, payment_date: Time.zone.today, notes: "Original")
  expect(CapitalRemittancePaymentCreate.call(capital_remittance_payment: payment)).to be_success
  api_ids[:payment] = payment.id
end

# H10-2 — the other folio's remittance on the same call
Given("I remember the other folio's remittance") do
  api_ids[:remittance2] = @capital_call.capital_remittances.where.not(id: api_ids[:remittance]).first!.id
end

Given("I note the collected amounts of both remittances") do
  @h_collected = CapitalRemittance.where(id: [api_ids[:remittance], api_ids[:remittance2]]).pluck(:id, :collected_amount_cents).to_h
end

Given("I note the other firm's remittance totals") do
  remittance = CapitalRemittance.find(api_ids[:beta_remittance])
  @h_beta_totals = [remittance.collected_amount_cents, remittance.capital_remittance_payments.count]
end

# ── Secondaries (H6-2, H6-H3, H6-S1…S3, H6-SH) ──────────────────────────────

# A company with a fixed-price sale: one seller's approved offer, one buyer's short-listed interest and an
# unverified allocation between them — the rows the offers and allocations bulk menus act on
Given("my company has a fixed-price sale with an approved offer, a short-listed interest and an unverified allocation") do
  steps %(
    Given there is a user "first_name=Sonal" for an entity "name=Urban Co;entity_type=Company"
    And the user has role "company_admin"
    And there is a sale "name=Bulk Sale;price_type=Fixed Price;final_price=10000;percent_allowed=100"
    And there is an existing investor entity "investor_name=Seller Co;entity_type=Investor" with employee "first_name=Sell"
    And the investor has "Seller" access rights to the sale
    And the investor has an offer "quantity=10" for the sale
    And the offer is approved
  )
  @h_seller = @employee_investor
  @h_offer = @offer.reload
  steps %(
    Given there is an existing investor entity "investor_name=Buyer Co;entity_type=Investor" with employee "first_name=Buy"
    And the investor has "Buyer" access rights to the sale
    And the investor has an interest "quantity=10;short_listed_status=short_listed;price=10000" for the sale
  )
  # Allocated as the allocation engine does (Allocation.build_from), not yet verified
  @h_allocation = Allocation.build_from(@h_offer, @interest.reload, 10, 10_000)
  @h_allocation.save!
  expect(@h_offer.reload.verified).to be(false)
  api_ids.merge!(sale: @sale.id, offer: @h_offer.id, allocation: @h_allocation.id)
  api_token_for!("me")
end

# The seller, in the investor persona, with a token
Given("{string} is the seller on that sale") do |name|
  @h_seller.add_role(:investor)
  @h_seller.update!(curr_role: "investor")
  api_users[name] = @h_seller
  api_token_for!(name)
end

# An employee of the selling company who can see the sale but not change it
Given("{string} is an employee of my company with read-only access to the sale") do |name|
  user = FactoryBot.create(:user, entity: @entity, first_name: name)
  user.add_role(:employee)
  AccessRight.create!(entity: @entity, owner: @sale, user_id: user.id, notify: false, permissions: %i[read])
  api_users[name] = user
  api_token_for!(name)
end

Given("the offer of that sale is verified") do
  @h_offer.update_column(:verified, true)
end

# H6-S3 — the SPA job itself (templates, documents) is not what is under test: only that the bulk action
# reaches it with the arguments OfferSpaJob#perform takes
Given("SPA generation for offers is stubbed") do
  allow_any_instance_of(Offer).to receive(:validate_spa_generation).and_return(nil)
  allow(OfferSpaJob).to receive(:perform_now)
end

# ── Requests ─────────────────────────────────────────────────────────────────

# H18-8 — the website page itself, signed in as that user (login.rb's log_in)
When("{string} opens the web page {string}") do |name, path|
  log_in(api_user(name))
  visit(api_fill(path))
end

# H10-4 — a fund unit on my fund, pointing at the other firm's commitment
When("I build a fund unit in my fund on the other firm's commitment") do
  commitment = @fund.capital_commitments.order(:id).first
  @h_fund_unit = FundUnit.new(entity: @entity, fund: @fund, investor: commitment.investor, unit_type: "A",
                              quantity: 10, price_cents: 1000, premium_cents: 0,
                              capital_commitment_id: api_ids.fetch(:beta_commitment))
end

# H10-X2 — what ImportCapitalRemittancePayment#save_crp does for an update-only row: re-assign the same
# firm, fund and remittance, plus the new values, then CapitalRemittancePaymentUpdate
When("the payment is re-saved the way an update-only import does") do
  payment = CapitalRemittancePayment.find(api_ids[:payment])
  payment.assign_attributes(entity_id: payment.fund.entity_id, fund: payment.fund,
                            capital_remittance: payment.capital_remittance, notes: "Re-imported")
  @h_result = CapitalRemittancePaymentUpdate.call(capital_remittance_payment: payment)
end

# ── Assertions: H6 ───────────────────────────────────────────────────────────

Then("no remittance of the call is verified") do
  expect(@capital_call.capital_remittances.where(verified: true)).to be_none
end

# The per-row failures BulkActionJob mails to the user (EntityMailer#doc_gen_errors)
Then("an errors email says {string}") do |text|
  bodies = ActionMailer::Base.deliveries.map { |mail| mail.body.encoded }
  expect(bodies.any? { |body| body.include?(text) }).to be(true), "no email mentions #{text.inspect}"
end

Then("every formula of my fund is still enabled") do
  expect(FundFormula.where(fund_id: @fund.id, enabled: false)).to be_none
  expect(FundFormula.where(fund_id: @fund.id)).to exist
end

Then("every formula of my fund is disabled") do
  expect(FundFormula.where(fund_id: @fund.id, enabled: true)).to be_none
  expect(FundFormula.where(fund_id: @fund.id)).to exist
end

Then("every formula of the fund {string} is still enabled") do |fund_name|
  formulas = FundFormula.where(fund_id: h_fund(fund_name).id)
  expect(formulas).to exist
  expect(formulas.where(enabled: false)).to be_none
end

Then("the KYC of folio {int} is still not verified") do |_n|
  expect(@h_kyc.reload.verified).to be(false)
end

Then("the document {string} still exists") do |doc_name|
  expect(Document.where(id: @h_document.id, name: doc_name)).to exist
end

Then("the sale's allocation is still unverified") do
  expect(@h_allocation.reload.verified).to be(false)
end

Then("the sale's allocation is verified") do
  expect(@h_allocation.reload.verified).to be(true)
end

Then("the sale's offer is still unverified") do
  expect(@h_offer.reload.verified).to be(false)
end

Then("the sale's offer is verified") do
  expect(@h_offer.reload.verified).to be(true)
end

# OfferSpaJob#perform(secondary_sale_id, offer_id, user_id) — the bulk action used to pass (offer_id, user_id)
Then("OfferSpaJob was run for the offer with the sale, the offer and me") do
  expect(OfferSpaJob).to have_received(:perform_now).with(@sale.id, @h_offer.id, @user.id)
end

# ── Assertions: H7 ───────────────────────────────────────────────────────────

Then("my fund has {int} account entries of type {string}") do |count, entry_type|
  expect(AccountEntry.where(fund_id: @fund.id, entry_type:).count).to eq(count)
end

Then("the fund {string} has {int} account entries") do |fund_name, count|
  expect(AccountEntry.where(fund_id: h_fund(fund_name).id).count).to eq(count)
end

Then("the other firm's fund still has {int} account entries") do |count|
  expect(AccountEntry.where(fund_id: api_ids.fetch(:beta_fund)).count).to eq(count)
end

# ── Assertions: H9 ───────────────────────────────────────────────────────────

Then("my fund has no master fund") do
  expect(@fund.reload.master_fund_id).to be_nil
end

Then("my fund's master fund is {string}") do |name|
  expect(@fund.reload.master_fund).to eq(h_fund(name))
end

Then("there is no fund named {string}") do |name|
  expect(Fund.where(name:)).to be_none
end

# ── Assertions: H10 ──────────────────────────────────────────────────────────

Then("the payment is still on its remittance") do
  expect(CapitalRemittancePayment.find(api_ids[:payment]).capital_remittance_id).to eq(api_ids[:remittance])
end

Then("the collected amounts of both remittances are unchanged") do
  now = CapitalRemittance.where(id: @h_collected.keys).pluck(:id, :collected_amount_cents).to_h
  expect(now).to eq(@h_collected)
end

Then("the other firm's remittance totals are unchanged") do
  remittance = CapitalRemittance.find(api_ids[:beta_remittance])
  expect([remittance.collected_amount_cents, remittance.capital_remittance_payments.count]).to eq(@h_beta_totals)
end

Then("the remittance is still on its own call") do
  expect(CapitalRemittance.find(api_ids[:remittance]).capital_call_id).to eq(@capital_call.id)
end

Then("the fund unit is refused with an error on {string}") do |attribute|
  expect(@h_fund_unit.save).to be(false)
  expect(@h_fund_unit.errors[attribute.to_sym]).to be_present, "errors: #{@h_fund_unit.errors.full_messages}"
end

Then("the re-saved payment kept its remittance and has the notes {string}") do |notes|
  expect(@h_result).to be_success, "errors: #{@h_result[:errors]}"
  payment = CapitalRemittancePayment.find(api_ids[:payment])
  expect(payment.capital_remittance_id).to eq(api_ids[:remittance])
  expect(payment.notes).to eq(notes)
end

Then("the remittance has the notes {string}") do |notes|
  expect(CapitalRemittance.find(api_ids[:remittance]).notes).to eq(notes)
end

# ── Assertions: H18 ──────────────────────────────────────────────────────────

# RatioFormulasController#index lists policy_scope(@fund.ratio_formulas) (it has no JSON view)
Then("{string} can list {int} ratio formula(s) of my fund") do |name, count|
  expect(Pundit.policy_scope!(api_user(name), RatioFormula).where(fund_id: @fund.id).count).to eq(count)
end

# H18-H2 — the five staff-only lists with a JSON view, each with this many rows of my fund
Then("every staff-only list of my fund has {int} row(s) for {string}") do |count, name|
  paths = %w[/fund_reports.json /fund_formulas.json /capital_calls.json /capital_distributions.json /fund_unit_settings.json]
  failures = paths.filter_map do |path|
    response = api_request(name, "GET", "#{path}?fund_id={fund}")
    rows = begin
      JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    end
    "#{path} → #{response.status} #{response.body.truncate(160)}" unless response.status == 200 && rows.is_a?(Array) && rows.size == count
  end
  expect(failures).to be_empty, failures.join("\n")
end

# H18-H2 — RatioFormulaPolicy#show? (permissioned_employee?) still admits the fund's own staff
Then("{string} may open the ratio formula") do |name|
  expect(RatioFormulaPolicy.new(api_user(name), RatioFormula.find(api_ids[:ratio_formula])).show?).to be(true)
end

Then("the web page does not mention {string}") do |text|
  expect(page).to have_no_content(text)
end
