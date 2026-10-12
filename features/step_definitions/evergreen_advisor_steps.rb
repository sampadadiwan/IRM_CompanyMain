# Steps for features/fund/evergreen/advisor_portal.feature — investor advisors on the evergreen
# investor screens. An advisor is a user of an "Investor Advisor" firm who is granted an
# InvestorAdvisor on the investor's own entity, an AccessRight on the fund (entity_id = the
# investor's entity) and an approved InvestorAccess on the investor — exactly what
# InvestorAdvisorsController#create_for_investor does through AddFolioInvestorAdvisor. Switching into
# the investor (InvestorAdvisor#switch) makes the advisor a curr_role "investor" user of that entity.
# Worked examples H63–H66, E182–E187, X118–X123 — openspec/changes/open-ended-funds/design.md#worked-examples

# ---- Helpers ----

# The advisor user behind a name (created by the grant step below)
def evergreen_advisor(name)
  @evergreen_advisors&.fetch(name) || raise("No advisor called #{name}")
end

# The investor of the current fund's entity, by name
def evergreen_investor_named(name)
  Investor.find_by!(entity_id: @fund.entity_id, investor_name: name)
end

# The advisor's grant on the investor's entity
def evergreen_advisor_grant(advisor_name, investor_name)
  InvestorAdvisor.find_by!(user_id: evergreen_advisor(advisor_name).id, entity_id: evergreen_investor_named(investor_name).investor_entity_id)
end

# The advisor's investor access on the investor (the row that says "approved")
def evergreen_advisor_access(advisor_name, investor_name)
  InvestorAccess.find_by!(investor_id: evergreen_investor_named(investor_name).id, user_id: evergreen_advisor(advisor_name).id)
end

# Switch the advisor into the investor exactly as the topbar persona form does (InvestorAdvisor#switch)
def evergreen_switch_advisor(advisor_name, investor_name)
  advisor = evergreen_advisor(advisor_name)
  evergreen_advisor_grant(advisor_name, investor_name).switch(advisor)
  advisor.reload
  # Sanity: now acting inside the investor's entity, as an investor
  expect(advisor.entity_id).to eq(evergreen_investor_named(investor_name).investor_entity_id)
  expect(advisor.curr_role).to eq("investor")
  advisor
end

# ---- Granting ----

# The advisor of an advisory firm is added for the investor on this fund — the same operation the
# "Add Investor Advisor" form runs (AddFolioInvestorAdvisor: grant + fund access right + approved
# investor access). A second call for another investor reuses the same advisor user.
Given('{string} has an approved advisor {string} from {string}') do |investor_name, advisor_name, firm|
  inv = evergreen_investor_named(investor_name)
  @evergreen_advisors ||= {}
  advisor = @evergreen_advisors[advisor_name]
  unless advisor
    # A user of an "Investor Advisor" firm gets the investor_advisor role and the topbar switcher on create
    firm_entity = Entity.find_by(name: firm) || FactoryBot.create(:entity, name: firm, entity_type: "Investor Advisor")
    advisor = FactoryBot.create(:user, entity: firm_entity, first_name: advisor_name)
    expect(advisor.reload.has_cached_role?(:investor_advisor)).to be(true)
    @evergreen_advisors[advisor_name] = advisor
  end
  # Built as InvestorAdvisorsController#create_for_investor builds it (an LP-side "investor" grant)
  grant = InvestorAdvisor.new(email: advisor.email, entity_id: inv.investor_entity_id, allowed_roles: ["investor"],
                              permissions: inv.investor_entity.permissions, extended_permissions: %i[investor_kyc_read investor_read],
                              owner_name: @fund.name, created_by: @gp_user || @user, acting_user: @gp_user || @user)
  params = { investor_advisor: { advisor_entity_name: firm, first_name: advisor.first_name, last_name: advisor.last_name } }
  result = AddFolioInvestorAdvisor.call(investor_advisor: grant, investor: inv, fund: @fund, params:)
  raise "advisor grant failed: #{result[:errors]}" unless result.success?

  # Sanity: the fund access right and the approved investor access both exist
  expect(AccessRight.exists?(entity_id: inv.investor_entity_id, owner: @fund, user_id: advisor.id)).to be(true)
  expect(evergreen_advisor_access(advisor_name, investor_name).approved).to be(true)
end

# The advisor's investor access exists but is pending approval (approved = false)
Given('the access of advisor {string} to {string} is not approved') do |advisor_name, investor_name|
  access = evergreen_advisor_access(advisor_name, investor_name)
  access.update_columns(approved: false)
  expect(InvestorAccess.approved.exists?(id: access.id)).to be(false)
end

# The grant and its investor access stay, but the fund access right is taken away
Given('the fund access right of advisor {string} for {string} is removed') do |advisor_name, investor_name|
  inv = evergreen_investor_named(investor_name)
  AccessRight.where(entity_id: inv.investor_entity_id, owner: @fund, user_id: evergreen_advisor(advisor_name).id).find_each(&:destroy)
  expect(AccessRight.exists?(owner: @fund, user_id: evergreen_advisor(advisor_name).id)).to be(false)
end

# The fund admin deletes the advisor grant (InvestorAdvisor#remove_access_rights drops the fund
# access right and the investor access) — while the advisor is still switched in
Given('the fund admin removes the advisor {string} from {string}') do |advisor_name, investor_name|
  evergreen_advisor_grant(advisor_name, investor_name).destroy
  advisor = evergreen_advisor(advisor_name)
  expect(AccessRight.exists?(owner: @fund, user_id: advisor.id)).to be(false)
  expect(InvestorAccess.exists?(investor_id: evergreen_investor_named(investor_name).id, user_id: advisor.id)).to be(false)
end

# ---- Signing in and switching ----

Given('the advisor {string} is switched into {string}') do |advisor_name, investor_name|
  evergreen_switch_advisor(advisor_name, investor_name)
end

# Switched into the investor first (so the topbar's auto-switch has nothing to do), then a fresh login
When('the advisor {string} logs in to the portal for {string}') do |advisor_name, investor_name|
  advisor = evergreen_switch_advisor(advisor_name, investor_name)
  evergreen_fresh_login(advisor)
end

# The advisor signs in without switching anything first (whatever state the grant left him in)
When('the advisor {string} logs in to the portal') do |advisor_name|
  evergreen_fresh_login(evergreen_advisor(advisor_name).reload)
end

# The topbar persona picker, as the advisor would use it: pick the investor, wait for the switch
When('I switch the advisor persona to {string}') do |investor_name|
  grant = InvestorAdvisor.find_by!(user_id: @user.id, entity_id: evergreen_investor_named(investor_name).investor_entity_id)
  # The select auto-submits (persona#setPersona) and the switch redirects back with a notice
  within("#investor_advisors_form") { select(investor_name, from: "investor_advisor") }
  expect(page).to have_content("You have now been switched to the advisor role for #{investor_name}")
  expect(@user.reload.investor_advisor_id).to eq(grant.id)
end

# ---- Assertions on the investor screens ----

Then('the holding of folio {string} should show {string}') do |folio, text|
  expect(page).to have_css("#holding_#{folio.parameterize}", text:)
end

Then('the investor transactions should show {string}') do |text|
  expect(page).to have_css("#lp_transactions_table", text:)
end

Then('the investor transactions should not show {string}') do |text|
  # The table is there (so the absence is real), but the text is not in it
  expect(page).to have_css("#lp_transactions_table")
  expect(find("#lp_transactions_table")).not_to have_content(text)
end

# The Requests tab's table (Request / Amount / Units columns, as the GP order book)
Then('the investor requests should show {string}') do |text|
  expect(page).to have_css("#lp_requests_table", text:)
end

Then('the investor requests should not show {string}') do |text|
  # The table is there (so the absence is real), but the text is not in it
  expect(page).to have_css("#lp_requests_table")
  expect(find("#lp_requests_table")).not_to have_content(text)
end

Then('the request of {string} should not be listed') do |investor_name|
  DealingOrder.where(fund_id: @fund.id, investor_id: evergreen_investor_named(investor_name).id).find_each do |o|
    expect(page).not_to have_css("#lp_request_#{o.id}")
  end
end

Then('there should be no portal card of folio {string}') do |folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  # Wait for the landing page's Funds widget before judging the absence
  expect(page).to have_css(".show_funds")
  expect(page).not_to have_css("#lp_card_#{cc.id}")
end

Then('the folio choices should not include {string}') do |folio|
  options = find("#order_folio").all("option").map(&:text)
  expect(options.none? { |o| o.start_with?(folio) }).to be(true), "folio choices: #{options.inspect}"
end

Then('the latest order should be for {string} on folio {string} from the portal') do |investor_name, folio|
  order = DealingOrder.order(:id).last
  expect(order.investor_id).to eq(evergreen_investor_named(investor_name).id)
  expect(order.capital_commitment&.folio_id).to eq(folio)
  # Placed by the advisor in the portal, not entered by the GP
  expect(order.source).to eq("portal")
  expect(order.entered_by_id).to be_nil
end

# ---- Direct requests (no browser) ----

# A signed-in HTTP session for the advisor; fails loudly if the sign-in itself was refused, so a
# "nothing happened" assertion afterwards can never pass just because the request was anonymous
def evergreen_advisor_session(advisor_name)
  session = evergreen_http_session(evergreen_advisor(advisor_name))
  # Devise redirects away from the sign-in page only on success
  expect(session.response).to be_redirect
  expect(session.response.location.to_s).not_to include("sign_in")
  session
end

# The post reached the controller as the signed-in advisor (not bounced to the sign-in page)
def evergreen_expect_signed_in_response(session)
  puts "Direct request answered #{session.response.status} #{session.response.location}"
  expect(session.response.location.to_s).not_to include("sign_in")
end

# A signed-in HTTP post of the order form as the advisor, naming any folio
When('the advisor {string} tries to place a {string} order of {string} units on folio {string} directly') do |advisor_name, kind, units, folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  @orders_before = DealingOrder.count
  session = evergreen_advisor_session(advisor_name)
  session.post evergreen_orders_path(@fund), params: { dealing_order: { kind:, unit_type: "A", units:, capital_commitment_id: cc.id } }
  evergreen_expect_signed_in_response(session)
end

When('the advisor {string} tries to place a {string} order of {string} directly') do |advisor_name, kind, amount|
  @orders_before = DealingOrder.count
  session = evergreen_advisor_session(advisor_name)
  session.post evergreen_orders_path(@fund), params: { dealing_order: { kind:, unit_type: "A", amount: } }
  evergreen_expect_signed_in_response(session)
end

# The fund page fetched as the advisor in whatever entity he is in now (following one redirect)
When('the advisor {string} requests the fund page directly') do |advisor_name|
  session = evergreen_advisor_session(advisor_name)
  session.get fund_path(@fund)
  evergreen_expect_signed_in_response(session)
  session.follow_redirect! if session.response.redirect?
  @direct_body = session.response.body
  # Still signed in after the redirect (an anonymous page would trivially show nothing)
  expect(@direct_body).not_to include("user_password")
end

Then('the response should not show {string}') do |text|
  expect(@direct_body).not_to include(text)
end

Then('the response should not show the evergreen investor page') do
  expect(@direct_body).not_to include("evergreen_investor_page")
end
