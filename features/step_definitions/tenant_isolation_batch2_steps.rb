# Tenant isolation - batch 2. Exercises the scopes, policies, views and controllers fixed in
# openspec/changes/fix-tenant-isolation-batch2. @user / @entity ("Artha", a company admin) and
# @fund ("Artha F1") come from the shared steps.

module Batch2IsolationHelpers
  def b2_entities
    @b2_entities ||= {}
  end

  def b2_entity(name, entity_type)
    b2_entities[name] ||= begin
      entity = FactoryBot.create(:entity, name:, entity_type:)
      %i[enable_funds enable_documents enable_kycs enable_deals enable_secondary_sale enable_approvals].each do |flag|
        entity.permissions.set(flag) if entity.permissions.respond_to?(:set)
      end
      entity.save!
      entity
    end
  end

  # An LP record of Artha for `entity`, with an approved contact user of that entity.
  def b2_lp(entity)
    investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: entity.id,
                                            investor_name: entity.name, category: "LP")
    user = FactoryBot.create(:user, entity:)
    user.update_columns(curr_role: "investor")
    InvestorAccess.create!(investor:, user:, entity_id: @entity.id, email: user.email,
                           first_name: user.first_name, last_name: user.last_name, approved: true)
    [investor, user.reload]
  end

  def b2_commitment(fund, investor)
    kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual")
    FactoryBot.create(:capital_commitment, fund:, entity: @entity, investor:, investor_kyc: kyc)
  end

  def b2_share(owner, investor)
    AccessRight.create!(owner:, access_to_investor_id: investor.id, entity_id: @entity.id, notify: false)
  end

  def b2_document(name, owner, folder)
    Document.create!(entity: @entity, name:, owner:, folder:, user: @user,
                     file: File.new("public/img/whatsappQR.png", "r"))
  end

  def b2_advisor_view
    @b2_advisor.reload
  end
end
World(Batch2IsolationHelpers)

Given('batch 2 has another tenant {string} with PAN {string} and email {string}') do |name, pan, email|
  entity = b2_entity(name, "Investment Fund")
  entity.update_columns(pan:, primary_email: email)
  b2_entities[@entity.name] = @entity
end

# ---- B1 -------------------------------------------------------------------------------------

When('I open the entity page of {string}') do |name|
  visit entity_path(b2_entities.fetch(name))
end

Then('I see {string} on the company page') do |text|
  expect(page).to have_text(text)
end

Then('I do not see {string} or {string} on the company page') do |pan, email|
  expect(page).not_to have_text(pan)
  expect(page).not_to have_text(email)
end

Given('{string} is an LP of my fund with an approved contact user') do |name|
  @b2_lp_investor, @b2_lp_user = b2_lp(b2_entities.fetch(name))
end

Then('the full details of {string} are shown to me as its GP') do |name|
  expect(EntityPolicy.new(@user.reload, b2_entities.fetch(name)).full_details?).to be true
end

Then('the full details of my company are shown to the LP contact user') do
  expect(EntityPolicy.new(@b2_lp_user, @entity).full_details?).to be true
end

Then('the full details of my company are shown to me') do
  expect(EntityPolicy.new(@user.reload, @entity).full_details?).to be true
end

# ---- B3 -------------------------------------------------------------------------------------

Given('batch 2 client {string} invests in {string} and {string} and has an F1-only advisor') do |name, f1, f2|
  @b2_f1 = Fund.find_by!(name: f1)
  @b2_f2 = FactoryBot.create(:fund, entity: @entity, name: f2)
  @b2_client = b2_entity(name, "Investor")
  @b2_client_investor, @b2_client_user = b2_lp(@b2_client)
  @b2_c1 = b2_commitment(@b2_f1, @b2_client_investor)
  @b2_c2 = b2_commitment(@b2_f2, @b2_client_investor)
  [@b2_f1, @b2_f2].each { |fund| b2_share(fund, @b2_client_investor) }

  # The advisor, set up the way Add Investor Advisor does it, for F1 only.
  home = b2_entity("Advisory Firm", "Investor Advisor")
  @b2_advisor = FactoryBot.create(:user, entity: home)
  @b2_advisor.roles.delete_all
  @b2_advisor.add_role(:investor_advisor)
  @b2_advisor.update_columns(advisor_entity_id: home.id, advisor_entity_roles: "employee,investor_advisor", curr_role: "employee")
  @b2_grant = InvestorAdvisor.new(entity_id: @b2_client.id, email: @b2_advisor.email, allowed_roles: ["investor"])
  %i[enable_funds enable_documents enable_kycs enable_deals enable_secondary_sale enable_approvals].each { |f| @b2_grant.permissions.set(f) }
  @b2_grant.user = @b2_advisor
  @b2_grant.save(validate: false)
  InvestorAccess.create!(investor: @b2_client_investor, user: @b2_advisor, entity_id: @entity.id, email: @b2_advisor.email,
                         first_name: "Ada", last_name: "Visor", approved: true)
  AccessRight.create!(owner: @b2_f1, entity_id: @b2_client.id, user_id: @b2_advisor.id, notify: false, metadata: "investor_advisor")
end

Given('Artha shared an F1 statement, an F2 statement and an AGM deck with {string}') do |_name|
  @b2_doc_f1 = b2_document("F1 Q2 statement", @b2_c1, @b2_c1.document_folder)
  @b2_doc_f2 = b2_document("F2 Q2 statement", @b2_c2, @b2_c2.document_folder)
  root = Folder.where(entity_id: @entity.id, level: 0).first || Folder.where(entity_id: @entity.id).first
  @b2_agm_folder = Folder.create!(name: "AGM #{SecureRandom.hex(2)}", entity: @entity, parent: root)
  @b2_doc_agm = b2_document("AGM 2026 deck", nil, @b2_agm_folder)
  [@b2_doc_f1, @b2_doc_f2, @b2_doc_agm, @b2_c1.document_folder, @b2_agm_folder].each do |owner|
    b2_share(owner, @b2_client_investor) unless AccessRight.exists?(owner:, access_to_investor_id: @b2_client_investor.id)
  end
end

Given('the advisor has switched into {string}') do |_name|
  @b2_grant.switch(@b2_advisor)
  expect(b2_advisor_view.entity_id).to eq(@b2_client.id)
  expect(b2_advisor_view.investor_advisor?).to be true
end

Then("the advisor's document list for Artha is exactly the F1 statement") do
  expect(Document.for_investor(b2_advisor_view, @entity.id).distinct.pluck(:id)).to contain_exactly(@b2_doc_f1.id)
end

Then('the advisor can open the F1 statement but not the F2 statement or the AGM deck') do
  advisor = b2_advisor_view
  expect(DocumentPolicy.new(advisor, @b2_doc_f1).show?).to be true
  expect(DocumentPolicy.new(advisor, @b2_doc_f2).show?).to be false
  expect(DocumentPolicy.new(advisor, @b2_doc_agm).show?).to be false
end

Then("the client's own user lists all three documents") do
  expect(Document.for_investor(@b2_client_user, @entity.id).distinct.pluck(:id))
    .to include(@b2_doc_f1.id, @b2_doc_f2.id, @b2_doc_agm.id)
end

Then("the advisor's folder list includes the F1 statement's folder but not the AGM folder") do
  ids = Folder.for_investor(b2_advisor_view, @entity).distinct.pluck(:id)
  expect(ids).to include(@b2_c1.document_folder.id)
  expect(ids).not_to include(@b2_agm_folder.id)
end

Given('Artha shared an approval and a secondary sale with {string}') do |_name|
  @b2_approval = FactoryBot.build(:approval, entity: @entity)
  @b2_approval.save(validate: false)
  b2_share(@b2_approval, @b2_client_investor)
  @b2_sale = FactoryBot.create(:secondary_sale, entity: @entity)
  b2_share(@b2_sale, @b2_client_investor)
end

Given('the advisor has a personal grant on the secondary sale for {string}') do |_name|
  # As the advisor import's "Add To: Secondary Sale" creates it: scoped to the client's entity.
  AccessRight.create!(owner: @b2_sale, entity_id: @b2_client.id, user_id: @b2_advisor.id, notify: false, metadata: "investor_advisor")
end

Then('the advisor lists neither the approval nor the secondary sale') do
  advisor = b2_advisor_view
  expect(Approval.for_investor(advisor).pluck(:id)).not_to include(@b2_approval.id)
  expect(SecondarySale.for_investor(advisor).pluck(:id)).not_to include(@b2_sale.id)
end

Then("the client's own user lists both the approval and the secondary sale") do
  expect(Approval.for_investor(@b2_client_user).pluck(:id)).to include(@b2_approval.id)
  expect(SecondarySale.for_investor(@b2_client_user).pluck(:id)).to include(@b2_sale.id)
end

Then('the advisor lists the secondary sale') do
  expect(SecondarySale.for_investor(b2_advisor_view).pluck(:id)).to include(@b2_sale.id)
end

# ---- B4-1 -----------------------------------------------------------------------------------

Given("the fund shows ratios, with a fund-level ratio and one for each of two LPs' folios") do
  @fund.features.set(:show_fund_ratios)
  @fund.save(validate: false)
  lp1_entity = b2_entity("LP One", "Investor")
  lp2_entity = b2_entity("LP Two", "Investor")
  @b2_lp1, @b2_lp1_user = b2_lp(lp1_entity)
  @b2_lp2, = b2_lp(lp2_entity)
  [@b2_lp1, @b2_lp2].each { |investor| b2_share(@fund, investor) }
  c1 = b2_commitment(@fund, @b2_lp1)
  c2 = b2_commitment(@fund, @b2_lp2)
  make = lambda do |commitment|
    ratio = FundRatio.new(entity: @entity, fund: @fund, name: "IRR", value: 0.12, end_date: Time.zone.today,
                          capital_commitment_id: commitment&.id, owner: @fund)
    ratio.save(validate: false)
    ratio
  end
  @b2_ratio_fund = make.call(nil)
  @b2_ratio_lp1 = make.call(c1)
  @b2_ratio_lp2 = make.call(c2)
end

Then("the first LP's user lists the fund-level ratio and their own folio's ratio only") do
  ids = FundRatioPolicy::Scope.new(@b2_lp1_user, FundRatio).resolve.distinct.pluck(:id)
  expect(ids).to include(@b2_ratio_fund.id, @b2_ratio_lp1.id)
  expect(ids).not_to include(@b2_ratio_lp2.id)
end

Then("the first LP's user cannot open the other LP's folio ratio") do
  expect(FundRatioPolicy.new(@b2_lp1_user, @b2_ratio_lp2).show?).to be false
  expect(FundRatioPolicy.new(@b2_lp1_user, @b2_ratio_lp1).show?).to be true
end

# ---- B4-2 -----------------------------------------------------------------------------------

Given('{string} has a KYC with no commitment') do |_name|
  @b2_kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor: @b2_client_investor, kyc_type: "individual", verified: false)
  @b2_kyc.capital_commitments.each(&:destroy)
end

Given('{string} has a KYC committed only to {string}') do |_name, fund_name|
  @b2_kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor: @b2_client_investor, kyc_type: "individual", verified: false)
  FactoryBot.create(:capital_commitment, fund: Fund.find_by!(name: fund_name), entity: @entity,
                                         investor: @b2_client_investor, investor_kyc: @b2_kyc)
end

Then('the advisor can edit that KYC') do
  policy = InvestorKycPolicy.new(b2_advisor_view, @b2_kyc.reload)
  expect([policy.edit?, policy.update?]).to eq([true, true])
end

Then('the advisor can neither open nor edit that KYC') do
  policy = InvestorKycPolicy.new(b2_advisor_view, @b2_kyc)
  expect([policy.show?, policy.edit?, policy.update?]).to eq([false, false, false])
end

Then("the client's own user can still edit that KYC") do
  expect(InvestorKycPolicy.new(@b2_client_user, @b2_kyc).update?).to be true
end

# ---- B4-3 -----------------------------------------------------------------------------------

Given('{string} is a deal investor in a deal of my company') do |_name|
  @entity.update_columns(currency: "INR", units: "Crores") if @entity.currency.blank?
  deal = FactoryBot.create(:deal, entity: @entity)
  # Inserted directly: the save callbacks build a kanban card that needs a fully priced deal.
  DealInvestor.insert_all([{ deal_id: deal.id, investor_id: @b2_client_investor.id, entity_id: @entity.id,
                             investor_entity_id: @b2_client.id, created_at: Time.current, updated_at: Time.current }])
  @b2_deal_investor = DealInvestor.find_by!(deal_id: deal.id, investor_id: @b2_client_investor.id)
end

Then('the advisor cannot open that deal investor') do
  expect(DealInvestorPolicy.new(b2_advisor_view, @b2_deal_investor).show?).to be false
end

Then("the client's own user can still open that deal investor") do
  expect(DealInvestorPolicy.new(@b2_client_user, @b2_deal_investor).show?).to be true
end

# ---- B4-4 -----------------------------------------------------------------------------------

Given('there is a deal in my company that a plain employee has no access to') do
  @entity.update_columns(currency: "INR", units: "Crores") if @entity.currency.blank?
  @b2_deal = FactoryBot.create(:deal, entity: @entity)
  @b2_employee = FactoryBot.create(:user, entity: @entity)
  @b2_employee.roles.delete_all
  @b2_employee.add_role(:employee)
end

Then('restricting search results for the plain employee drops that deal') do
  expect(PolicyScopedSearch.restrict(@b2_employee.reload, Deal, [@b2_deal]).to_a).to be_empty
end

Then('restricting search results for me keeps that deal') do
  expect(PolicyScopedSearch.restrict(@user.reload, Deal, [@b2_deal]).to_a).to eq([@b2_deal])
end

# ---- B4-5 -----------------------------------------------------------------------------------

When('the user is moved into {string} without a new token') do |name|
  # What a persona switch does to users.entity_id; the token still names the old entity.
  @user.update_columns(entity_id: b2_entities.fetch(name).id)
end

# ---- B4-6 -----------------------------------------------------------------------------------

Given('there is a validation rule of {string} and one of my company') do |name|
  build = lambda do |entity|
    rule = ValidationRule.new(entity:, name: "Rule #{SecureRandom.hex(2)}", target_model: ValidationRule::TARGET_MODELS.first,
                              severity: ValidationRule::SEVERITIES.first, message_template: "x", condition_tree: { "all" => [] })
    rule.save(validate: false)
    rule
  end
  @b2_rule_other = build.call(b2_entities.fetch(name))
  @b2_rule_mine = build.call(@entity)
end

Then('I cannot view, update or delete the rule of {string}') do |_name|
  policy = ValidationRulePolicy.new(@user.reload, @b2_rule_other)
  expect([policy.show?, policy.update?, policy.destroy?]).to eq([false, false, false])
end

Then("I can still view and update my company's rule") do
  policy = ValidationRulePolicy.new(@user.reload, @b2_rule_mine)
  expect([policy.show?, policy.update?]).to eq([true, true])
end
