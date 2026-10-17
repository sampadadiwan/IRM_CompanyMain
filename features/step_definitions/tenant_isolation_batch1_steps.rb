# Tenant isolation - batch 1. Exercises the controllers, policies, models and jobs fixed in
# openspec/changes/fix-tenant-isolation-batch1 the way the app calls them: real requests through
# the rack_test driver for anything decided by request params, policies and models directly for
# the rest. @user / @entity (a company admin of "Artha") and @fund come from the shared steps.

module TenantIsolationHelpers
  def tenants
    @tenants ||= {}
  end

  # An entity with the feature flags these screens need, so a refusal is the rule under test and
  # never a missing flag.
  def flagged_entity(name, entity_type)
    entity = FactoryBot.create(:entity, name:, entity_type:)
    %i[enable_funds enable_investor_advisors enable_import_uploads enable_deals enable_documents].each do |flag|
      entity.permissions.set(flag) if entity.permissions.respond_to?(:set)
    end
    entity.save!
    entity
  end

  # A user holding the advisor role whose home is an "Investor Advisor" firm.
  def advisor_user(email, home_name: "Advisory Co")
    home = tenants[home_name] ||= flagged_entity(home_name, "Investor Advisor")
    user = FactoryBot.create(:user, email:, entity: home)
    user.roles.delete_all
    user.add_role(:investor_advisor)
    user.update_columns(advisor_entity_id: home.id, advisor_entity_roles: "employee,investor_advisor", curr_role: "employee")
    user.reload
  end

  def grant_for(user, entity, roles)
    grant = InvestorAdvisor.new(entity_id: entity.id, email: user.email, allowed_roles: roles)
    grant.permissions.set(:enable_funds)
    grant.user = user
    grant.save(validate: false)
    grant
  end

  def lp_of_my_fund(name)
    lp_entity = flagged_entity(name, "Investor")
    investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: lp_entity.id,
                                            investor_name: name, category: "LP")
    AccessRight.create!(owner: @fund, access_to_investor_id: investor.id, entity_id: @entity.id, notify: false)
    [lp_entity, investor]
  end

  def report_for(owner)
    # before_create :set_model derives the model from the url, so give it one.
    report = Report.new(entity: @entity, user: owner, name: "Isolation report #{SecureRandom.hex(3)}", curr_role: "employee",
                        url: "/capital_commitments")
    report.save(validate: false)
    report
  end

  def capture_report_entity
    @report_entities = []
    # Capture the entity the query engine is built for, then stop the job (it rescues and alerts).
    allow(ReportBuilderQueryEngine).to receive(:new) do |entity:, **|
      @report_entities << entity&.id
      raise TenantIsolationHelpers::Captured
    end
  end

  # Swallows the error a stub raises once it has captured what it needs.
  class Captured < StandardError; end
end
World(TenantIsolationHelpers)

Given('there is another tenant {string} with a fund {string}') do |name, fund_name|
  tenants[name] = flagged_entity(name, "Investment Fund")
  tenants[@entity.name] = @entity
  @zeta_fund = FactoryBot.create(:fund, entity: tenants[name], name: fund_name)
  # The logged-in admin needs the same flags on their own entity and user.
  %i[enable_investor_advisors enable_import_uploads enable_deals].each { |flag| @entity.permissions.set(flag) }
  @entity.save!
  @user.permissions.set(:enable_investor_advisors) if @user.permissions.respond_to?(:set)
  @user.save!
end

# ---- S1 -------------------------------------------------------------------------------------

Given('there is an advisor grant in my entity for {string}') do |email|
  @grant = grant_for(advisor_user(email), @entity, ["investor"])
end

When('I update that grant with entity {string}, email {string} and allowed roles {string}') do |name, email, roles|
  page.driver.submit :patch, investor_advisor_path(@grant),
                     { investor_advisor: { entity_id: tenants.fetch(name).id, email:, allowed_roles: roles.split(",") } }
end

Then('the grant still belongs to my entity with email {string}') do |email|
  @grant.reload
  expect(@grant.entity_id).to eq(@entity.id)
  expect(@grant.email).to eq(email)
end

Then("the grant's allowed roles are {string}") do |roles|
  expect(@grant.reload.allowed_roles.map(&:to_s)).to eq(roles.split(","))
end

# ---- S2 -------------------------------------------------------------------------------------

Given('there is an LP {string} of my fund') do |name|
  @lp_entity, @lp_investor = lp_of_my_fund(name)
end

When('I add advisor {string} for {string} on the fund {string}') do |email, _lp, fund_name|
  fund = Fund.find_by!(name: fund_name)
  page.driver.submit :post, create_for_investor_investor_advisors_path,
                     { investor_advisor: { investor_id: @lp_investor.id, fund_id: fund.id, email:,
                                           advisor_entity_name: "Firm #{SecureRandom.hex(3)}",
                                           first_name: "Ada", last_name: "Visor" } }
end

Then('I am denied access') do
  expect(page).to have_text("Access Denied")
end

Then('{string} has no access right on the fund {string}') do |email, fund_name|
  user = User.find_by(email:)
  fund = Fund.find_by!(name: fund_name)
  expect(user.nil? || AccessRight.where(owner: fund, user_id: user.id).none?).to be true
end

Then('{string} has an access right on the fund {string}') do |email, fund_name|
  user = User.find_by!(email:)
  expect(AccessRight.where(owner: Fund.find_by!(name: fund_name), user_id: user.id)).to exist
end

# ---- S3 -------------------------------------------------------------------------------------

When('I update my own user with entity {string} and first name {string}') do |name, first_name|
  page.driver.submit :patch, user_path(@user), { user: { entity_id: tenants.fetch(name).id, first_name: } }
end

Then('my user is still in my entity with first name {string}') do |first_name|
  @user.reload
  expect(@user.entity_id).to eq(@entity.id)
  expect(@user.first_name).to eq(first_name)
end

# ---- S4 -------------------------------------------------------------------------------------

When('I search documents for {string} passing the entity {string}') do |query, name|
  @searched_entity_ids = []
  # Capture the entity the search is filtered by, then stop: the assertion is about the filter,
  # and the test environment does not run Elasticsearch queries.
  allow(DocumentIndex).to receive(:filter) do |args|
    @searched_entity_ids << args.dig(:term, :entity_id)
    raise TenantIsolationHelpers::Captured
  end
  begin
    visit search_documents_path(entity_id: tenants.fetch(name).id, query:)
  rescue TenantIsolationHelpers::Captured
    nil
  end
end

Then('the document search ran against my own entity') do
  expect(@searched_entity_ids).to eq([@entity.id])
end

# ---- S5 -------------------------------------------------------------------------------------

Given("there is a secondary sale with an unverified offer by another investor's user") do
  sale = FactoryBot.create(:secondary_sale, entity: @entity)
  seller_entity = flagged_entity("Seller Co", "Investor")
  seller_investor = FactoryBot.create(:investor, entity_id: @entity.id, investor_entity_id: seller_entity.id,
                                                 investor_name: "Seller Co", category: "LP")
  @seller = FactoryBot.create(:user, entity: seller_entity)
  @seller.update_columns(curr_role: "investor")
  # The policy reads only who owns the offer and whether it is verified.
  @offer = Offer.new(entity: @entity, secondary_sale: sale, investor: seller_investor, user: @seller, verified: false)
  other_entity = flagged_entity("Other Investor", "Investor")
  @other_investor_user = FactoryBot.create(:user, entity: other_entity)
  @other_investor_user.update_columns(curr_role: "investor")
end

Then('an investor user of a different investor cannot edit, update or delete that offer') do
  policy = OfferPolicy.new(@other_investor_user.reload, @offer)
  expect([policy.edit?, policy.update?, policy.destroy?]).to eq([false, false, false])
end

Then("the offer's own seller can still edit, update and delete it") do
  policy = OfferPolicy.new(@seller.reload, @offer)
  expect([policy.edit?, policy.update?, policy.destroy?]).to eq([true, true, true])
end

# ---- S6 -------------------------------------------------------------------------------------

Given('there is an LP user of my fund with access to the fund') do
  lp_entity, investor = lp_of_my_fund("Patel Family")
  @lp_user = FactoryBot.create(:user, entity: lp_entity)
  @lp_user.update_columns(curr_role: "investor")
  InvestorAccess.create!(investor:, user: @lp_user, entity_id: @entity.id, email: @lp_user.email,
                         first_name: @lp_user.first_name, last_name: @lp_user.last_name, approved: true)
end

Then('the LP user can see the fund but not its reports') do
  policy = FundPolicy.new(@lp_user.reload, @fund)
  expect(policy.show?).to be true
  expect(policy.report?).to be false
end

Then("I can still open the fund's reports") do
  expect(FundPolicy.new(@user.reload, @fund).report?).to be true
end

# ---- S7a ------------------------------------------------------------------------------------

Given('there is a deal in my entity') do
  @entity.update_columns(currency: "INR", units: "Crores") if @entity.currency.blank?
  @deal = FactoryBot.create(:deal, entity: @entity)
end

Then("a user with only the deals feature cannot open the deal's edit page") do
  employee = FactoryBot.create(:user, entity: @entity)
  employee.roles.delete_all
  employee.add_role(:employee)
  expect(employee.reload.enable_deals).to be_truthy
  expect(DealPolicy.new(employee, @deal).edit?).to be false
end

Then("I can still open the deal's edit page") do
  expect(DealPolicy.new(@user.reload, @deal).edit?).to be true
end

# ---- S8 -------------------------------------------------------------------------------------

Given('I am an advisor with a grant on a client named {string}') do |name|
  @advisor = advisor_user("s8.#{SecureRandom.hex(3)}@advisor.example")
  client = flagged_entity("Client #{SecureRandom.hex(3)}", "Investor")
  client.update_columns(name:)
  @client_grant = grant_for(@advisor, client, ["investor"])
  log_in(@advisor)
end

When('I switch into that client') do
  page.driver.submit :post, switch_investor_advisors_path, { id: @client_grant.id }
end

Then('the confirmation shows {string} as text, not markup') do |name|
  within("#page_alerts") do
    expect(page).to have_text("switched to the advisor role for #{name}")
    expect(page).not_to have_css("b", text: "Bold")
  end
end

# ---- R1 / R1b -------------------------------------------------------------------------------

When('I post an investor import for my fund with entity {string}') do |name|
  file = Rack::Test::UploadedFile.new(Rails.public_path.join('sample_uploads/investor_access.xlsx'),
                                      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  page.driver.submit :post, import_uploads_path,
                     { import_upload: { name: "Isolation import", owner_type: "Fund", owner_id: @fund.id,
                                        entity_id: tenants.fetch(name).id, import_type: "InvestorAccess",
                                        import_file: file } }
end

Then('the import is saved under my entity') do
  upload = ImportUpload.where(name: "Isolation import").last
  expect(upload).to be_present
  expect(upload.entity_id).to eq(@entity.id)
end

Then('an advisor import into {string} granting {string} by me is refused') do |name, role|
  upload = ImportUpload.new(entity: tenants.fetch(name), user: @user, owner: @zeta_fund, name: "x", import_type: "InvestorAdvisor")
  row = { "Email" => "r1b@advisor.example", "Add To" => "Fund", "Name" => @zeta_fund.name,
          "Stakeholder" => "Anyone", "Allowed Roles" => role }
  expect { ImportInvestorAdvisor.new.save_row(row, upload, [], {}) }
    .to raise_error(RuntimeError, /company_admin.*company admin of/)
end

# ---- R2 -------------------------------------------------------------------------------------

Given('there is an advisor switched into a grant on my entity with roles {string}') do |roles|
  @advisor = advisor_user("r2.#{SecureRandom.hex(3)}@advisor.example")
  @home_id = @advisor.advisor_entity_id
  @switched_grant = grant_for(@advisor, @entity, roles.split(","))
  @switched_grant.switch(@advisor)
  expect(@advisor.reload.entity_id).to eq(@entity.id)
end

When('that grant is deleted') do
  InvestorAdvisor.find(@switched_grant.id).destroy
end

Then("the advisor is back in their home entity without the grant's roles") do
  @advisor.reload
  expect(@advisor.entity_id).to eq(@home_id)
  expect(@advisor.investor_advisor_id).to be_nil
  expect(@advisor.has_cached_role?(:company_admin)).to be false
end

# ---- R3 -------------------------------------------------------------------------------------

Given('an advisor advises clients {string} and {string} who are both LPs of my fund') do |c1, c2|
  @advisor = advisor_user("r3.#{SecureRandom.hex(3)}@advisor.example")
  @client_rows = {}
  [c1, c2].each do |name|
    lp_entity, investor = lp_of_my_fund(name)
    kyc = FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual")
    FactoryBot.create(:capital_commitment, fund: @fund, entity: @entity, investor:, investor_kyc: kyc)
    row = InvestorAccess.create!(investor:, user: @advisor, entity_id: @entity.id, email: @advisor.email,
                                 first_name: "Ada", last_name: "Visor", approved: true)
    expect(row.is_investor_advisor).to be true
    # The personal grant AddFolioInvestorAdvisor creates for each client.
    AccessRight.create!(owner: @fund, entity_id: lp_entity.id, user_id: @advisor.id, notify: false)
    @client_rows[name] = { row:, entity: lp_entity }
  end
end

When("the advisor's contact row on {string} is deleted") do |name|
  # Loaded fresh, as the delete request does.
  InvestorAccess.find(@client_rows.fetch(name)[:row].id).destroy
end

Then('the advisor has no access right on my fund for {string}') do |name|
  expect(AccessRight.where(owner: @fund, user_id: @advisor.id, entity_id: @client_rows.fetch(name)[:entity].id)).to be_empty
end

Then('the advisor still has their access right on my fund for {string}') do |name|
  expect(AccessRight.where(owner: @fund, user_id: @advisor.id, entity_id: @client_rows.fetch(name)[:entity].id)).to exist
end

# ---- R4 -------------------------------------------------------------------------------------

Given('there is a report of my entity owned by a Fund Advisor of my entity now switched into {string}') do |name|
  # A Fund Advisor who built the report while switched into my entity.
  owner = advisor_user("r4.#{SecureRandom.hex(3)}@advisor.example")
  @owner_grant = grant_for(owner, @entity, ["employee"])
  @report = report_for(owner)
  @schedule = ReportSchedule.new(report: @report, frequency: "daily", recipients: ["ops@artha.example"])
  @schedule.save(validate: false)
  # They have since switched persona: users.entity_id now points at the other tenant.
  owner.update_columns(entity_id: tenants.fetch(name).id)
end

Given("that Fund Advisor's grant on my entity is deleted") do
  # Removed without the R2 revert running against this fixture's stale persona.
  InvestorAdvisor.where(id: @owner_grant.id).update_all(deleted_at: Time.current)
end

Then('the report query did not run') do
  expect(@report_entities).to eq([])
end

# ---- S1-E / R1-U / R1b-H / R7-X ---------------------------------------------------------

Given("that advisor's login email is changed to {string}") do |email|
  @grant.user.update_columns(email:)
end

Given('I have an import on my fund') do
  @import = ImportUpload.new(name: "Isolation import", owner: @fund, entity: @entity, user: @user, import_type: "InvestorAccess")
  # A real file, so the later update is valid and the entity rule is what decides.
  @import.import_file = File.open(Rails.public_path.join("sample_uploads/investor_access.xlsx"))
  @import.save(validate: false)
end

When('I update that import with entity {string}') do |name|
  page.driver.submit :patch, import_upload_path(@import), { import_upload: { entity_id: tenants.fetch(name).id, name: "Isolation import" } }
end

Given('there is a Fund Advisor with a company_admin grant on {string} now at home') do |name|
  @fund_advisor = advisor_user("r1bh.#{SecureRandom.hex(3)}@advisor.example")
  grant_for(@fund_advisor, tenants.fetch(name), ["company_admin"])
  expect(@fund_advisor.reload.entity_id).to eq(@fund_advisor.advisor_entity_id)
end

Then('an advisor import into {string} granting {string} by that Fund Advisor is not refused for the role') do |name, role|
  upload = ImportUpload.new(entity: tenants.fetch(name), user: @fund_advisor, owner: @zeta_fund, name: "x", import_type: "InvestorAdvisor")
  row = { "Email" => "r1bh.row@advisor.example", "Add To" => "Fund", "Name" => @zeta_fund.name,
          "Stakeholder" => "Anyone", "Allowed Roles" => role }
  # The row may fail later (no such stakeholder), but never on the company_admin check.
  expect { ImportInvestorAdvisor.new.save_row(row, upload, [], {}) }.to raise_error(RuntimeError) { |e| expect(e.message).not_to match(/company_admin/) }
end

When('the grant is deleted and the advisor then switches using the copy loaded before') do
  stale = InvestorAdvisor.find(@r7_grant.id)
  InvestorAdvisor.where(id: @r7_grant.id).update_all(deleted_at: Time.current)
  begin
    stale.switch(@advisor)
  rescue ActiveRecord::RecordNotFound => e
    @switch_error = e
  end
end

Then('the switch is refused and the advisor is still in their home entity with their home roles') do
  expect(@switch_error).to be_present
  fresh = User.find(@advisor.id)
  expect(fresh.entity_id).to eq(@home_id)
  expect(fresh.roles.map(&:name).sort).to eq(@home_roles)
end

Given('there is a report of my entity owned by me') do
  @report = report_for(@user)
end

When("the report's schedule runs") do
  capture_report_entity
  ReportBuilderExportJob.perform_now(@report.id, @report.user_id, @schedule.id)
end

When('I export the report on demand') do
  capture_report_entity
  ReportBuilderExportJob.perform_now(@report.id, @user.id)
end

Then('the report query ran against my entity') do
  expect(@report_entities).to eq([@entity.id])
end

# ---- R5 -------------------------------------------------------------------------------------

Given('there is an advisor from {string} switched into my entity') do |home_name|
  @advisor = advisor_user("r5.#{SecureRandom.hex(3)}@advisor.example", home_name:)
  grant = grant_for(@advisor, @entity, ["employee"])
  grant.switch(@advisor)
  @advisor.reload
  expect(@advisor.entity_id).to eq(@entity.id)
  @home_admin = FactoryBot.create(:user, entity: tenants.fetch(home_name))
  @home_admin.add_role(:company_admin)
end

Then('I cannot view, edit or reset two-factor for that advisor') do
  policy = UserPolicy.new(@user.reload, @advisor)
  expect([policy.show?, policy.edit?, policy.update?, policy.view_two_factor?]).to eq([false, false, false, false])
end

Then('the advisor can still edit themselves') do
  expect(UserPolicy.new(@advisor, @advisor).update?).to be true
end

Then('a company admin of {string} can still edit the advisor') do |_name|
  expect(UserPolicy.new(@home_admin.reload, @advisor).update?).to be true
end

# ---- R7 -------------------------------------------------------------------------------------

Given('there is an advisor at home with a grant on my entity') do
  @advisor = advisor_user("r7.#{SecureRandom.hex(3)}@advisor.example")
  @home_id = @advisor.advisor_entity_id
  @home_roles = @advisor.roles.map(&:name).sort
  @r7_grant = grant_for(@advisor, @entity, ["employee"])
end

When("the advisor's switch fails while adding roles") do
  # Fail on the last role the switch adds (investor_advisor, after the entity has been saved),
  # not on setup_defaults' own add_role, which runs before the save.
  allow(@advisor).to receive(:add_role).and_call_original
  allow(@advisor).to receive(:add_role).with(:investor_advisor).and_raise(ActiveRecord::RecordInvalid)
  begin
    @r7_grant.switch(@advisor)
  rescue ActiveRecord::RecordInvalid
    nil
  end
end

Then('the advisor is still in their home entity with their home roles') do
  fresh = User.find(@advisor.id)
  expect(fresh.entity_id).to eq(@home_id)
  expect(fresh.roles.map(&:name).sort).to eq(@home_roles)
end
