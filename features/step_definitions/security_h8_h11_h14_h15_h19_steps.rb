# Steps for the 2026-10 security review findings H8 (portfolio_scenarios#simple_scenario), H11
# (allocations list + PII Ransack), H14 (KPI approval), H15 (RM sale actions and template ids) and
# H19 (LP workflow flags on offers, interests and EOIs). Design and worked examples:
# docs/security/security_review_2026_10.md (cards "H8", "H11", "H14", "H15", "H19").
#
# Requests go through the rack_test driver as the signed-in user, the way a crafted URL or form
# would, using sr_request / sr_sign_in (security_c4_c7_h16_l10_steps.rb). "I am denied access"
# (tenant_isolation_batch1_steps.rb) checks for the Access Denied flash. @user / @entity are the
# signed-in admin from the shared "Im logged in as a user ... for an entity" step; @sale, @offer and
# @interest come from the secondaries Background (secondary_sale.rb steps).

module SecurityH8H11H14H15H19Helpers
  # ---- Secondaries parties ------------------------------------------------------------------

  # The sale's LP parties by their label in the feature ("A", "X", ...)
  def sec_parties
    @sec_parties ||= {}
  end

  def sec_offers
    @sec_offers ||= {}
  end

  def sec_interests
    @sec_interests ||= {}
  end

  # Allocations by their pair in the feature ("A->B")
  def sec_allocations
    @sec_allocations ||= {}
  end

  # An LP of the sale's firm, as a real seller or buyer is set up: their own Investor-type firm, the
  # sale firm's Investor record for it, a user with an approved investor access, and a sale grant
  # with `metadata` ("Seller" / "Buyer"). Created once per label.
  def sec_party(label, metadata)
    sec_parties[label] ||= begin
      # The LP's own firm and the selling firm's record of it
      lp_entity = FactoryBot.create(:entity, name: "#{label} Holdings", entity_type: "Investor")
      investor = FactoryBot.create(:investor, entity_id: @sale.entity_id, investor_entity_id: lp_entity.id,
                                              investor_name: lp_entity.name, category: "LP")
      # A signed-up user of the LP with an approved access to that investor
      user = FactoryBot.create(:user, entity: lp_entity, first_name: "Party#{label}")
      InvestorAccess.create!(investor:, user:, entity_id: @sale.entity_id, email: user.email,
                             first_name: user.first_name, last_name: user.last_name, approved: true)
      user.update_columns(curr_role: "investor")
      # The sale grant the sale page gives a seller or buyer
      AccessRight.create!(owner: @sale, entity_id: @sale.entity_id, access_to_investor_id: investor.id,
                          metadata:, access_type: "SecondarySale", notify: false)
      { entity: lp_entity, investor:, user: user.reload }
    end
  end

  # The party's offer on the sale (10 shares at the sale's minimum price), created on first use
  def sec_offer_of(label)
    sec_offers[label] ||= begin
      party = sec_party(label, "Seller")
      FactoryBot.create(:offer, entity: @sale.entity, secondary_sale: @sale, user: party[:user],
                                investor: party[:investor], quantity: 10, price: @sale.min_price,
                                full_name: "#{label} Seller", PAN: "PAN#{label}0001")
    end
  end

  # The party's interest on the sale (10 shares at the sale's minimum price), created on first use
  def sec_interest_of(label)
    sec_interests[label] ||= begin
      party = sec_party(label, "Buyer")
      FactoryBot.create(:interest, secondary_sale: @sale, entity: @sale.entity, user: party[:user],
                                   investor: party[:investor], interest_entity: party[:entity],
                                   price: @sale.min_price, quantity: 10, short_listed_status: "short_listed",
                                   verified: false, buyer_entity_name: "#{label} Buyer", PAN: "PAN#{label}0002",
                                   email: "#{label.downcase}@buyer.example")
    end
  end

  # One allocation "S->B": 2 shares of seller S's offer to buyer B's interest
  def sec_allocate(pair)
    seller, buyer = pair.split("->").map(&:strip)
    allocation = Allocation.build_from(sec_offer_of(seller), sec_interest_of(buyer), 2, @sale.min_price)
    allocation.save!
    sec_allocations[pair] = allocation
  end

  # "A->B, C->D" → ["A->B", "C->D"]
  def sec_pair_list(pairs)
    pairs.split(",").map(&:strip)
  end

  # "k=v;k=v" → { "k" => "v" } (an empty value stays "", for an expected nil)
  def sec_fields(spec)
    spec.split(";").to_h { |pair| pair.split("=", 2).map(&:strip) }
  end

  # Checks each "k=v" against the record as saved; numbers and money compare as numbers
  def sec_expect_saved(record, spec)
    record.reload
    sec_fields(spec).each do |attr, expected|
      actual = record.public_send(attr)
      if actual.is_a?(Numeric) || actual.is_a?(Money)
        expect(actual.to_d).to eq(expected.to_d), "#{attr}: expected #{expected}, got #{actual}"
      else
        expect(actual.to_s).to eq(expected), "#{attr}: expected #{expected.inspect}, got #{actual.inspect}"
      end
    end
  end

  # A sale of `entity` created the way the app creates one (folders included)
  def sec_sale_for(entity, name)
    owner = FactoryBot.create(:user, entity:)
    sale = FactoryBot.build(:secondary_sale, entity:, name:, start_date: Time.zone.today)
    SecondarySaleCreate.wtf?(secondary_sale: sale, current_user: owner)
    sale.save!
    sale.reload
  end

  def sec_foreign_sales
    @sec_foreign_sales ||= {}
  end

  # Another firm with a live sale of its own
  def sec_foreign_sale(firm, sale_name)
    sec_foreign_sales[sale_name] ||= begin
      entity = Entity.find_by(name: firm) || FactoryBot.create(:entity, name: firm, entity_type: "Company")
      sec_sale_for(entity, sale_name)
    end
  end

  # An "Offer Template" named SPA on `sale`, as the sale's Documents tab uploads one
  def sec_offer_template(sale)
    doc = Document.new(entity_id: sale.entity_id, owner: sale, name: "SPA", user: User.first, owner_tag: "Offer Template")
    doc.file = File.open("public/sample_uploads/Purchase-Agreement-1.docx", "rb")
    doc.save!
    doc
  end

  def sec_templates
    @sec_templates ||= {}
  end

  # An RM user: their own RM firm, the investor + rm roles real RMs hold
  def sec_rm(name)
    rm_entity = FactoryBot.create(:entity, name: "#{name} Wealth", entity_type: "RM")
    rm = FactoryBot.create(:user, entity: rm_entity, first_name: name)
    rm.add_role(:investor)
    rm.add_role(:rm)
    rm.update_columns(curr_role: "investor")
    rm.reload
  end

  def sec_rms
    @sec_rms ||= {}
  end

  # Records which (record, template) pairs the offer generator was asked to render, without rendering
  def sec_stub_offer_generator
    @sec_rendered = []
    allow(OfferSpaGenerator).to receive(:new) do |model, template, *_args, **_opts|
      @sec_rendered << [model.id, template.id]
      double("OfferSpaGenerator", generated_document: nil)
    end
  end

  # Watch (and swallow) the document jobs a request could queue, for "no SPA generation was queued"
  def sec_watch_doc_jobs
    allow(OfferSpaJob).to receive(:perform_later)
    allow(InterestDocJob).to receive(:perform_later)
  end

  # ---- KPIs ---------------------------------------------------------------------------------

  # A user of a new firm of the fund's kind holding `roles`, signed in
  def kpi_sign_in_outsider(firm, entity_type, *roles)
    entity = FactoryBot.create(:entity, name: firm, entity_type:)
    user = FactoryBot.create(:user, entity:)
    roles.each { |role| user.add_role(role) }
    sr_sign_in(user.reload)
  end
end
World(SecurityH8H11H14H15H19Helpers)

# ==== H11 =====================================================================================

Given('the sale has allocations {string}') do |pairs|
  sec_pair_list(pairs).each { |pair| sec_allocate(pair) }
end

Given('another firm {string} has a sale {string}') do |firm, sale_name|
  sec_foreign_sale(firm, sale_name)
end

When("{string} lists the sale's allocations") do |label|
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:get, allocations_path(secondary_sale_id: @sale.id))
end

When("{string} lists the sale's allocations filtered by {string} {string}") do |label, condition, value|
  sr_sign_in(sec_parties.fetch(label)[:user])
  # The generic filter dropdown sends the condition as q[...]
  sr_request(:get, allocations_path(secondary_sale_id: @sale.id, q: { condition => value }))
end

When('{string} lists the allocations of the sale {string}') do |label, sale_name|
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:get, allocations_path(secondary_sale_id: sec_foreign_sales.fetch(sale_name).id))
end

When("the sale's company admin lists the sale's allocations sorted by {string}") do |sort|
  sr_sign_in(@user)
  sr_request(:get, allocations_path(secondary_sale_id: @sale.id, q: { s: sort }))
end

Then('the allocations listed are {string}') do |pairs|
  shown = sec_pair_list(pairs)
  sec_allocations.each do |pair, allocation|
    row = %(id="allocation_#{allocation.id}")
    if shown.include?(pair)
      expect(@sr_body).to include(row), "#{pair} should be listed"
    else
      expect(@sr_body).not_to include(row), "#{pair} should not be listed"
    end
  end
end

Then('the allocations listed in order are {string}') do |pairs|
  # Every row is listed, and in the order given
  positions = sec_pair_list(pairs).map { |pair| @sr_body.index(%(id="allocation_#{sec_allocations.fetch(pair).id}")) }
  expect(positions).to all(be_present)
  expect(positions).to eq(positions.sort)
end

Then('{string} is not in the response') do |text|
  expect(@sr_body).not_to include(text)
end

Given('{string} uses the holding persona') do |label|
  sec_parties.fetch(label)[:user].update_columns(curr_role: "holding")
end

Then('the allocations {string} can list are {string}') do |label, pairs|
  # The list the allocations index starts from, for this user
  user = sec_parties.fetch(label)[:user].reload
  listed = AllocationPolicy::Scope.new(user, Allocation).resolve.where(secondary_sale_id: @sale.id).pluck(:id)
  expect(listed).to match_array(sec_pair_list(pairs).map { |pair| sec_allocations.fetch(pair).id })
end

# ==== H15 =====================================================================================

Given('there is an RM {string} with no access to the sale {string}') do |name, sale_name|
  sec_rms[name] = sec_rm(name)
  expect(AccessRight.where(owner: sec_foreign_sales.fetch(sale_name), user_id: sec_rms[name].id)).to be_none
end

Given('there is an RM {string} with access to the sale') do |name|
  sec_rms[name] = sec_rm(name)
  # A direct grant on the sale, as the sale's Access tab gives an RM
  AccessRight.create!(owner: @sale, entity_id: @sale.entity_id, user_id: sec_rms[name].id,
                      access_type: "SecondarySale", notify: false)
end

Given('the sale has closed') do
  @sale.update_columns(start_date: Time.zone.today - 10.days, end_date: Time.zone.today - 1.day)
  @sale.reload
end

When('the RM {string} asks to regenerate the offer SPAs of the sale {string}') do |name, sale_name|
  sec_watch_doc_jobs
  sr_sign_in(sec_rms.fetch(name))
  sr_request(:patch, generate_spa_secondary_sale_path(sec_foreign_sales.fetch(sale_name)), { offer_doc_generation: "true" })
end

Then('no SPA generation was queued') do
  expect(OfferSpaJob).not_to have_received(:perform_later)
  expect(InterestDocJob).not_to have_received(:perform_later)
end

Then('the RM {string} may not upload interests or offers into the sale {string}') do |name, sale_name|
  policy = Pundit.policy(sec_rms.fetch(name), sec_foreign_sales.fetch(sale_name))
  # import? is what ImportUploadPolicy asks of the upload's owner
  expect([policy.import_interests?, policy.import_offers?, policy.import?]).to eq([false, false, false])
end

Then('the RM {string} may upload interests into the sale') do |name|
  policy = Pundit.policy(sec_rms.fetch(name), @sale)
  expect([policy.import_interests?, policy.import?]).to eq([true, true])
end

Then("the RM {string} may not regenerate the sale's SPAs or upload offers into it") do |name|
  policy = Pundit.policy(sec_rms.fetch(name), @sale)
  expect([policy.generate_spa?, policy.import_offers?]).to eq([false, false])
end

Then("the RM {string} may neither regenerate the sale's SPAs nor upload interests into it") do |name|
  policy = Pundit.policy(sec_rms.fetch(name), @sale)
  expect([policy.generate_spa?, policy.import_interests?, policy.import?]).to eq([false, false, false])
end

Given("the seller's offer already has a generated {string}") do |name|
  # A generated (non-template) document on the Background seller's approved offer
  doc = Document.new(entity_id: @sale.entity_id, owner: @offer, name:, user: @user, owner_tag: "Generated")
  doc.file = File.open("public/sample_uploads/Purchase-Agreement-1.docx", "rb")
  doc.save!
  @sec_generated_doc = doc
end

Given('another firm {string} has a sale {string} with an offer SPA template') do |firm, sale_name|
  sec_templates[sale_name] = sec_offer_template(sec_foreign_sale(firm, sale_name))
end

Given('my firm has another sale {string} with an offer SPA template') do |sale_name|
  sec_foreign_sales[sale_name] = sec_sale_for(@entity, sale_name)
  sec_templates[sale_name] = sec_offer_template(sec_foreign_sales[sale_name])
end

When("the documents of the seller's offer are generated with the template of the sale {string}") do |sale_name|
  sec_stub_offer_generator
  # What offers#generate_docs queues, with a template id that is not this sale's. perform returns
  # the job's error list
  @sec_job_errors = OfferSpaJob.new.perform(@sale.id, @offer.id, @user.id, template_id: sec_templates.fetch(sale_name).id)
end

When("the documents of the seller's offer are generated with the sale's own template") do
  sec_stub_offer_generator
  @sec_own_template = @sale.documents.templates.find_by!(name: "SPA", owner_tag: "Offer Template")
  @sec_job_errors = OfferSpaJob.new.perform(@sale.id, @offer.id, @user.id, template_id: @sec_own_template.id)
end

Then('the generation reports {string}') do |message|
  expect(Array(@sec_job_errors).pluck(:msg)).to include(message)
end

Then('no document was rendered') do
  expect(@sec_rendered).to be_empty
end

Then("the seller's offer still has its generated {string}") do |name|
  expect(@offer.documents.not_templates.where(name:)).to exist
  expect(Document.exists?(@sec_generated_doc.id)).to be(true)
end

Then("the sale's own template was rendered for the seller's offer") do
  expect(@sec_rendered).to eq([[@offer.id, @sec_own_template.id]])
end

# ==== H19 (offers / interests) ================================================================

Given('{string} has an unverified offer on the sale') do |label|
  expect(sec_offer_of(label).verified).to be(false)
end

Given('{string} has an unverified interest on the sale') do |label|
  expect(sec_interest_of(label).verified).to be(false)
end

When('{string} updates their offer with {string}') do |label, spec|
  sec_watch_doc_jobs
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:patch, offer_path(sec_offers.fetch(label)), { offer: sec_fields(spec) })
end

When("{string} updates their offer with {string} and points it at the buyer's interest") do |label, spec|
  sec_watch_doc_jobs
  sr_sign_in(sec_parties.fetch(label)[:user])
  # interest_id is a firm-only field: the Background buyer's interest
  sr_request(:patch, offer_path(sec_offers.fetch(label)), { offer: sec_fields(spec).merge("interest_id" => @interest.id) })
end

When('I update the offer of {string} with {string}') do |label, spec|
  sr_request(:patch, offer_path(sec_offers.fetch(label)), { offer: sec_fields(spec) })
end

Then('the offer of {string} has {string}') do |label, spec|
  sec_expect_saved(sec_offers.fetch(label), spec)
end

When('{string} updates their interest with {string}') do |label, spec|
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:patch, interest_path(sec_interests.fetch(label)), { interest: sec_fields(spec) })
end

When("the sale's company admin updates the interest of {string} with {string}") do |label, spec|
  sr_sign_in(@user)
  sr_request(:patch, interest_path(sec_interests.fetch(label)), { interest: sec_fields(spec) })
end

Then('the interest of {string} has {string}') do |label, spec|
  sec_expect_saved(sec_interests.fetch(label), spec)
end

Given('the sale lets its firm manage interests') do
  @sale.update_column(:manage_interests, true)
end

When('{string} creates an offer on the sale for the investor of {string}') do |label, other|
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:post, offers_path, { offer: { secondary_sale_id: @sale.id, investor_id: sec_parties.fetch(other)[:investor].id,
                                            quantity: 5, price: @sale.min_price, full_name: "Not #{other}" } })
end

Then('the investor of {string} has {int} offer(s) on the sale') do |label, count|
  expect(@sale.offers.where(investor_id: sec_parties.fetch(label)[:investor].id).count).to eq(count)
end

# ==== H19 (EOIs) ==============================================================================

Given('there is an LP {string} of the opportunity with a signed-up user') do |name|
  # The LP's own firm, the fund's record of it, and a user with an approved access
  lp_entity = FactoryBot.create(:entity, name:, entity_type: "Investor")
  @eoi_investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: lp_entity.id,
                                               investor_name: name, category: "LP")
  @eoi_lp_user = FactoryBot.create(:user, entity: lp_entity)
  InvestorAccess.create!(investor: @eoi_investor, user: @eoi_lp_user, entity_id: @entity.id, email: @eoi_lp_user.email,
                         first_name: @eoi_lp_user.first_name, last_name: @eoi_lp_user.last_name, approved: true)
  @eoi_lp_user.update_columns(curr_role: "investor")
  @eoi_lp_user.reload
  # The opportunity is shared with the LP
  AccessRight.create!(owner: @investment_opportunity, access_type: "InvestmentOpportunity",
                      access_to_investor_id: @eoi_investor.id, entity: @entity, notify: false)
end

Given('the LP has an unapproved EOI on the opportunity') do
  # 2,000,000 - inside the opportunity's ticket range (factory: 1,000,000 to 100,000,000)
  @eoi = ExpressionOfInterest.create!(investment_opportunity: @investment_opportunity, entity: @entity,
                                      investor: @eoi_investor, eoi_entity: @eoi_investor.investor_entity,
                                      user: @eoi_lp_user, amount_cents: 200_000_000, approved: false,
                                      verified: false, show_data_room: false)
end

When('the LP updates their EOI with {string}') do |spec|
  sr_sign_in(@eoi_lp_user)
  sr_request(:patch, expression_of_interest_path(@eoi), { expression_of_interest: sec_fields(spec) })
end

When('the LP allocates their EOI with {string}') do |spec|
  sr_sign_in(@eoi_lp_user)
  sr_request(:patch, allocate_expression_of_interest_path(@eoi), { expression_of_interest: sec_fields(spec) })
end

When('I allocate the EOI with {string}') do |spec|
  sr_request(:patch, allocate_expression_of_interest_path(@eoi), { expression_of_interest: sec_fields(spec) })
end

Then('the EOI has {string}') do |spec|
  sec_expect_saved(@eoi, spec)
end

Then('the LP may still edit their EOI but is not offered the Data Room toggle') do
  lp = @eoi_lp_user.reload
  # The row's Show / Hide Data Room buttons render only when both are true
  expect(Pundit.policy(lp, @eoi.reload).update?).to be(true)
  expect(Pundit.policy(lp, @investment_opportunity).update?).to be(false)
end

Then('the LP may not open the allocation form of their EOI') do
  policy = Pundit.policy(@eoi_lp_user.reload, @eoi.reload)
  expect([policy.allocation_form?, policy.allocate?]).to eq([false, false])
end

# ==== H14 =====================================================================================

Given('I am signed in as an approver of another firm {string}') do |firm|
  kpi_sign_in_outsider(firm, "Investment Fund", :approver)
end

Given('I am signed in as a support user of another firm {string}') do |firm|
  # Support approves as themselves (the 232 prod approvals by 2 support users)
  kpi_sign_in_outsider(firm, "Company", :support, :approver)
end

Given('I am signed in as an approver of my firm') do
  approver = FactoryBot.create(:user, entity: @entity)
  approver.add_role(:approver)
  sr_sign_in(approver.reload)
end

Given('there is an unapproved KPI {string} for the company as the second KPI') do |args|
  first = @kpi
  steps %(Given there is an unapproved KPI "#{args}" for the company)
  @second_kpi = @kpi
  @kpi = first
end

Given('KPI report journey moves are watched') do
  allow(KpiReport).to receive(:journey_progress_for_portco).and_call_original
end

When('I approve the KPI by its address') do
  sr_request(:patch, approve_kpi_path(@kpi))
end

When('I unapprove the KPI by its address') do
  sr_request(:patch, unapprove_kpi_path(@kpi))
end

When('I reject the second KPI by its address') do
  sr_request(:delete, reject_kpi_path(@second_kpi))
end

When('I reject all pending KPIs of the portfolio company for the fund {string}') do |fund_name|
  sr_request(:patch, approve_all_kpis_path, { entity_id: Entity.find_by!(name: fund_name).id,
                                              portfolio_company_id: @portfolio_company.id, reject: "true" })
end

When('I approve all pending KPIs of the portfolio company for the fund {string}') do |fund_name|
  sr_request(:patch, approve_all_kpis_path, { entity_id: Entity.find_by!(name: fund_name).id,
                                              portfolio_company_id: @portfolio_company.id })
end

Then('no KPI report journey was moved') do
  expect(KpiReport).not_to have_received(:journey_progress_for_portco)
end

Given('there is an LP user of my firm with the approver role who is shown the KPI') do
  # An LP of the fund whose investor the KPI report is shared with, holding the approver role
  lp_entity = FactoryBot.create(:entity, name: "Patel Family", entity_type: "Investor")
  investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: lp_entity.id,
                                          investor_name: "Patel Family", category: "LP")
  @kpi_lp_user = FactoryBot.create(:user, entity: lp_entity)
  InvestorAccess.create!(investor:, user: @kpi_lp_user, entity_id: @entity.id, email: @kpi_lp_user.email,
                         first_name: @kpi_lp_user.first_name, last_name: @kpi_lp_user.last_name, approved: true)
  @kpi_lp_user.update_columns(curr_role: "investor")
  @kpi_lp_user.add_role(:approver)
  AccessRight.create!(owner: @kpi.kpi_report, entity_id: @entity.id, access_to_investor_id: investor.id, notify: false)
  @kpi_lp_user.reload
end

Then('the LP user is offered no Approve or Reject on the KPI') do
  # The show page and the grid render Approve / Reject only when these are true
  policy = Pundit.policy(@kpi_lp_user, @kpi.reload)
  expect([policy.approve?, policy.reject?]).to eq([false, false])
end

When('the LP user approves the KPI by its address') do
  sr_sign_in(@kpi_lp_user)
  sr_request(:patch, approve_kpi_path(@kpi))
end

# ==== H8 ======================================================================================

When('I open the summary scenario of the fund {string}') do |fund_name|
  visit simple_scenario_portfolio_scenarios_path(fund_id: Fund.find_by!(name: fund_name).id)
end

When('the LP user opens the summary scenario of the fund {string}') do |fund_name|
  sr_sign_in(@lp_user.reload)
  visit simple_scenario_portfolio_scenarios_path(fund_id: Fund.find_by!(name: fund_name).id)
end

Given('there is an employee of my firm with read-only access to the fund {string}') do |fund_name|
  @read_only_employee = FactoryBot.create(:user, entity: @entity)
  # A grant on the fund with no update permission: the fund opens, its edit actions do not
  AccessRight.create!(owner: Fund.find_by!(name: fund_name), entity_id: @entity.id, user_id: @read_only_employee.id,
                      access_type: "Fund", notify: false)
end

When('the read-only employee opens the summary scenario of the fund {string}') do |fund_name|
  sr_sign_in(@read_only_employee.reload)
  visit simple_scenario_portfolio_scenarios_path(fund_id: Fund.find_by!(name: fund_name).id)
end

Then('no scenario IRR is shown') do
  expect(page).to have_no_text("Scenario IRR")
end

Then('the summary scenario with its IRRs is shown') do
  expect(page).to have_text("Current IRR")
  expect(page).to have_text("Scenario IRR")
end
