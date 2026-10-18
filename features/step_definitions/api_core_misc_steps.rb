# frozen_string_literal: true

# Steps for features/api/core_misc_api.feature — phase 9 of funds-json-api-hardening: the core / misc
# JSON endpoints (notifications, permissions, KYCs, approvals, documents, folders, valuations, ...).
# openspec/changes/funds-json-api-hardening/design.md#worked-examples — the H/E/X IDs in the feature.
#
# Reuses api_json_steps.rb (bearer client, {placeholder} ids, status / answer assertions) and only adds
# the records these endpoints work on — in my firm (Acme) and in the other firm (Beta) — plus generic
# "a column of a record" checks for proving nothing changed.

module ApiCoreMiscWorld
  def beta_entity
    Entity.find(api_ids.fetch(:beta_entity))
  end

  # The other firm's own user, so its records have a real uploader / owner
  def beta_user
    @beta_user ||= FactoryBot.create(:user, entity: beta_entity, first_name: "Bina")
  end

  def folio_commitment(n)
    @fund.capital_commitments.order(:id)[n - 1]
  end
end
World(ApiCoreMiscWorld)

# ── Setup ────────────────────────────────────────────────────────────────────

Given("{string} also has the role {string}") do |name, role|
  api_user(name).add_role(role.to_sym)
end

# {ravi_id} / {ravi_email} for the named user
Given("I remember the user {string}") do |name|
  user = api_user(name)
  api_ids[:"#{name.downcase}_id"] = user.id
  api_ids[:"#{name.downcase}_email"] = user.email
end

# (a fund grant also cascades to the fund's folders, so look for the fund row itself)
Then("my fund has an access right for the user {string}") do |name|
  expect(AccessRight.where(owner: @fund, user_id: api_user(name).id, entity_id: @entity.id)).to exist
end

# Two folders and a document in my firm, one folder and a document in the other firm
Given("both firms have folders and documents") do
  acme_folder = FactoryBot.create(:folder, entity: @entity, parent: @entity.root_folder, name: "Acme Reports")
  acme_folder2 = FactoryBot.create(:folder, entity: @entity, parent: @entity.root_folder, name: "Acme Archive")
  acme_document = FactoryBot.create(:document, entity: @entity, folder: acme_folder, user: @user, name: "Acme Deck")

  beta_folder = FactoryBot.create(:folder, entity: beta_entity, parent: beta_entity.root_folder, name: "Beta Data Room")
  beta_document = FactoryBot.create(:document, entity: beta_entity, folder: beta_folder, user: beta_user, name: "Beta Deck")

  api_ids.merge!(acme_folder: acme_folder.id, acme_folder2: acme_folder2.id, acme_document: acme_document.id,
                 beta_folder: beta_folder.id, beta_document: beta_document.id)
end

# A portfolio company with an instrument and a valuation in my firm; an instrument in the other firm
Given("both firms have a portfolio instrument and my firm has a valuation of {int} per share") do |price|
  instrument_for = lambda do |entity|
    pc_entity = FactoryBot.create(:entity, entity_type: "Company")
    company = Investor.new(entity:, investor_entity: pc_entity, investor_name: pc_entity.name, category: "Portfolio Company")
    company.save!(validate: false)
    [company, FactoryBot.create(:investment_instrument, entity:, portfolio_company: company, currency: "INR")]
  end
  acme_company, acme_instrument = instrument_for.call(@entity)
  _beta_company, beta_instrument = instrument_for.call(beta_entity)
  valuation = FactoryBot.create(:valuation, entity: @entity, owner: acme_company, investment_instrument: acme_instrument,
                                            valuation_date: Date.new(2026, 6, 30), per_share_value_cents: price * 100)
  api_ids.merge!(valuation: valuation.id, acme_instrument: acme_instrument.id, beta_instrument: beta_instrument.id)
end

# Two open approvals on my fund (the second is the target of a re-pointing attempt)
Given("my firm has two approvals on the fund") do
  approvals = Array.new(2) do |i|
    FactoryBot.create(:approval, entity: @entity, owner: @fund, title: "Approval #{i + 1}", approved: false)
  end
  api_ids.merge!(approval: approvals[0].id, approval2: approvals[1].id)
end

# Folio 1's investor is given the approval and has a pending response to it
Given("folio {int} has a pending response on the approval") do |n|
  approval = Approval.find(api_ids.fetch(:approval))
  investor = folio_commitment(n).investor
  AccessRight.create!(owner: approval, access_type: "Approval", access_to_investor_id: investor.id, entity: @entity, notify: false)
  response = ApprovalResponse.find_or_create_by!(approval:, investor:) do |r|
    r.entity = @entity
    r.response_entity_id = investor.investor_entity_id
    r.status = "Pending"
  end
  api_ids[:approval_response] = response.id
end

# An unverified, not-yet-submitted KYC for the folio's investor
Given("folio {int}'s investor has an unverified KYC") do |n|
  investor = folio_commitment(n).investor
  kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual", verified: false,
                                         pan_verified: false, bank_verified: false, completed_by_investor: false)
  api_ids[:kyc] = kyc.id
end

Given("I remember folio {int}'s investor") do |n|
  commitment = folio_commitment(n)
  api_ids[:"folio#{n}"] = commitment.id
  api_ids[:"folio#{n}_investor"] = commitment.investor_id
end

Given("I remember the other firm's investor") do
  api_ids[:beta_investor] = CapitalCommitment.find(api_ids.fetch(:beta_commitment)).investor_id
end

Given("my firm has an investor notice") do
  notice = InvestorNotice.create!(entity: @entity, title: "AGM", start_date: Time.zone.today, end_date: Time.zone.today + 30.days)
  api_ids[:investor_notice] = notice.id
end

Given("both firms have a form type") do
  api_ids[:form_type] = FormType.create!(entity: @entity, name: "Fund", tag: "Default").id
  api_ids[:beta_form_type] = FormType.create!(entity: beta_entity, name: "Fund", tag: "Default").id
end

Given("I remember the access right of folio {int}'s investor on the fund") do |n|
  api_ids[:access_right] = AccessRight.where(owner: @fund, access_to_investor_id: folio_commitment(n).investor_id).first!.id
end

# H33 — CKYC / KRA are external services: the KRA fetch is stubbed to succeed, the CKYC path only
# starts the OTP step (no external call is made on create)
Given("the KRA service answers successfully") do
  allow_any_instance_of(CkycKraService).to receive(:get_kra_data).and_return([true, "KRA data fetched"])
end

# ── Records ──────────────────────────────────────────────────────────────────

Given("I remember the last {word} as {string}") do |model_name, key|
  api_ids[key.to_sym] = model_name.constantize.order(:id).last!.id
end

Given("I note the {word} of {word} {string}") do |column, model_name, id|
  (@api_noted ||= {})[[model_name, column, api_fill(id)]] = model_name.constantize.find(api_fill(id)).public_send(column)
end

Then("the {word} of {word} {string} is unchanged") do |column, model_name, id|
  noted = @api_noted.fetch([model_name, column, api_fill(id)])
  expect(model_name.constantize.find(api_fill(id)).public_send(column)).to eq(noted)
end

Then("the {word} of {word} {string} is {string}") do |column, model_name, id, value|
  expect(model_name.constantize.find(api_fill(id)).public_send(column).to_s).to eq(api_fill(value))
end

Then("the last {word} has {word} {string}") do |model_name, column, value|
  expect(model_name.constantize.order(:id).last!.public_send(column).to_s).to eq(api_fill(value))
end
