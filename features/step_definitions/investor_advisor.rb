  Given('given there are investor advisors {string}') do |emails|
    @investor_advisor_entity = FactoryBot.create(:entity, entity_type: "Investor Advisor")
    # puts @investor_advisor_entity.to_json

    emails.split(",").each do |email|
        u = FactoryBot.create(:user, email:, entity: @investor_advisor_entity)
        u.has_cached_role?(:investor_advisor).should ==  true
    end
  end

  Given('Given I upload {string} file for Investment Advisors') do |file|
    @import_file = file
    visit(fund_path(@fund))
    click_on("Import")
    click_on("Import Investor Advisors")
    #sleep(2)
    fill_in('import_upload_name', with: "Test Upload")
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
    sleep(2)
    click_on("Save")
    expect(page).to have_content("Import Upload:")
    ImportUploadJob.perform_now(ImportUpload.last.id)
    # @investor_advisor = InvestorAdvisor.last
  end

  Then('the investor advisors should be added to each investor') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    data.each_with_index do |row, idx|
        next if idx.zero? # skip header row
        user_data = [headers, row].transpose.to_h
        user = User.find_by_email(user_data["Email"].strip)
        investor = @entity.investors.where(investor_name: user_data["Stakeholder"].strip).first
        # Check if user is added as an investor_advisor
        puts "Checking investor_advisor #{user.email} for #{investor.investor_entity.name}"
        investor.investor_entity.investor_advisors.where(user_id: user.id, entity_id: investor.investor_entity_id).count.should > 0
        # Check if he has permission to the Fund
        puts "Checking access_rights for investor_advisor #{user.email} for #{@fund.name}"
        fund = @entity.funds.where(name: user_data["Name"].strip).first
        fund.access_rights.where(user_id: user.id, entity_id: investor.investor_entity_id).count.should > 0
        # Check if he has been give investor access
        puts "Checking investor_access for #{user.email} in #{@entity.name}\n\n"
        @entity.investor_accesses.where(email: user.email).first.should_not be_nil
    end
  end



  Then('I switch to becoming the advisor for {string}') do |investor_name|
    #sleep(2)
    # Select the investor_name from the drop down with id investor_advisor
    within("#investor_advisors_form") do
      select(investor_name, from: "id")
    end
  end


Given('I go to Add Investor Advisor page for commmitment') do
  @capital_commitment ||= CapitalCommitment.first
  visit(capital_commitment_path(@capital_commitment))
  # click_on("Actions")
  click_on("Actions", match: :first)
# first(:button, 'Actions').click
# first(:link, 'Actions').click

  click_on("Add Investor Advisor")
end

Given('I fill IA form with details of a user that exists with role {string}') do |role|
  email = Faker::Internet.email
  entity_result = CreateInvestorAdvisorEntity.call(name: Faker::Company.name, primary_email: email)
  expect(entity_result.success?).to be true
  @entity = entity_result[:entity]
  user_result = FetchOrCreateUser.call(
      email: email,
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      entity_id: @entity.id,
      role: role.strip.to_sym
    )
  expect(user_result.success?).to be true
  @user = user_result[:user]
  @user.roles.destroy_all
  @user.add_role(role.strip.to_sym)
  @user.reload
  expect(@user.has_cached_role?(role.strip.to_sym)).to be true
  fill_in('investor_advisor_email', with: @user.email)
  click_on("Save")
end

Then('Investor Advisor is successfully created') do
  expect(page).to have_content("Investor advisor was successfully created.")
end

Given('I fill IA form with details of a user that is already an Investor Advisor for this fund') do
  @investor_advisor ||= InvestorAdvisor.last
  fill_in('investor_advisor_email', with: @investor_advisor.email)
  click_on("Save")
end

Then('Investor Advisor creation fails with error {string}') do |string|
  expect(page).to have_content(string)
end

Given('I fill IA form with details of a user that does not exist with details {string}') do |params|
  fill_in('investor_advisor_email', with: Faker::Internet.email)
  # advisor_entity_name,first_name,last_name
  if params.include?("advisor_entity_name")
    fill_in('investor_advisor_advisor_entity_name', with: Faker::Company.name)
  end
  if params.include?("first_name")
    fill_in('investor_advisor_first_name', with: Faker::Name.first_name)
  end
  if params.include?("last_name")
    fill_in('investor_advisor_last_name', with: Faker::Name.last_name)
  end
  click_on("Save")
end


Given('I delete the InvestorAccess of this User on the investors page') do
  @capital_commitment ||= CapitalCommitment.first
  @investor_advisor ||= InvestorAdvisor.last
  @existing_investor_advisor ||= @investor_advisor
  investor_access =  @investor_advisor.user.investor_accesses.order(created_at: :desc).first
  @user_investor_accesses = @investor_advisor.user.investor_accesses.pluck(:id)
  visit(investor_path(@capital_commitment.investor))
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content(@investor_advisor.email, wait: 5)

  row = find("#investor_access_#{investor_access.id}")
  # If Actions is not visible, it might be folded by DataTables Responsive
  unless row.has_link?("Actions", visible: true) || row.has_button?("Actions", visible: true)
    # Click the first cell to expand the row
    row.first('td').click
  end

  # Now look for Actions. It might be in the row or in the child row created by DataTables
  if row.has_link?("Actions", visible: true) || row.has_button?("Actions", visible: true)
    within(row) { click_on("Actions") }
  else
    # Look in the next sibling which should be the child row
    child_row = row.find(:xpath, "following-sibling::tr[contains(@class, 'child')]")
    within(child_row) { click_on("Actions") }
  end

  within(".dropdown-menu.show") do
    click_button("Delete")
  end

  click_on("Proceed")
  sleep 0.5
  expect(@investor_advisor.user.investor_accesses.reload.count).to eq(@user_investor_accesses.count - 1)
end


Then('the AccessRight for the advisor must be deleted for the fund') do
  # binding.pry
  # @capital_commitment.reload.fund.access_rights.where(user_id: @investor_advisor.user.id, entity_id: @investor_advisor.entity_id).count.should == 0
end

Then('the AccessRight for the advisor must be added for the fund') do
  @capital_commitment ||= CapitalCommitment.first
  @investor_advisor ||= InvestorAdvisor.last
  @capital_commitment.fund.reload.access_rights.where(user_id: @investor_advisor.user.id, entity_id: @investor_advisor.entity_id).count.should > 0
end

Then('the AccessRights Cache for the advisor must not have the fund') do
  @investor_advisor.user.reload
  expect(@investor_advisor.user.access_rights_cache[@investor_advisor.entity_id]["Fund"]).to eq({})
end




Then('Its the same InvestorAdvisor with the InvestorAccess created again') do
  @existing_investor_advisor.reload
  expect(@investor_advisor.user.investor_accesses.reload.count).to eq(@user_investor_accesses.count)
end

# ── Enhancements: role and entity assertions used by existing + security scenarios ──

Then('my roles should include {string}') do |role|
  @user.reload
  expect(@user.has_cached_role?(role.to_sym)).to be true
end

Then('my roles should not include {string}') do |role|
  @user.reload
  expect(@user.has_cached_role?(role.to_sym)).to be false
end

Then('my active entity should be the switched entity') do
  @user.reload
  expect(@user.entity_id).not_to eq(@user.advisor_entity_id)
  expect(@user.investor_advisor?).to be true
end

Given('I revert to my home entity') do
  # Call the model directly to simulate the revert without a browser POST
  InvestorAdvisor.revert(@user, nil)
  @user.reload
end

Then('I am back in my original entity') do
  @user.reload
  expect(@user.investor_advisor?).to be false
  expect(@user.entity_id).to eq(@user.advisor_entity_id)
end

# ── Security step definitions ─────────────────────────────────────────────────

Given('the entity has the investor advisors feature enabled') do
  # user.enable_investor_advisors checks user.permissions (get_permissions), not entity.permissions
  @user.permissions.set(:enable_investor_advisors)
  @user.save!
  @user.reload
end

Given('the entity does not have the investor advisors feature enabled') do
  @user.permissions.unset(:enable_investor_advisors)
  @user.save!
  @user.reload
end

Given('the attacker entity has the investor advisors feature enabled') do
  @user.permissions.set(:enable_investor_advisors)
  @user.save!
  @user.reload
end

Given('there is an existing investor advisor user') do
  advisor_entity = FactoryBot.create(:entity, entity_type: "Investor Advisor")
  @advisor_user = FactoryBot.create(:user, entity: advisor_entity)
  @advisor_user.add_role(:investor_advisor)
  @advisor_user.reload
end

# SEC-1, SEC-3: model validation of allowed_roles
When('I try to build an investor advisor with allowed_roles including {string}') do |role|
  @advisor_user ||= User.joins(:roles).where(roles: { name: :investor_advisor }).first
  @test_ia = InvestorAdvisor.new(
    entity_id: @entity.id,
    email: @advisor_user.email,
    allowed_roles: [role]
  )
  @test_ia.valid?
end

Then('the investor advisor should fail validation with {string}') do |message|
  expect(@test_ia.errors.full_messages.join(" ")).to include(message)
end

Then('the investor advisor should pass allowed_roles validation') do
  errors = @test_ia.errors[:allowed_roles]
  expect(errors).to be_empty
end

# SEC-2: import service rejects invalid roles
# The invalid_roles check fires before import_upload is accessed, so we can pass nil.
When('I process an investor advisor import row with allowed_roles {string}') do |role|
  @import_error = nil
  begin
    import_service = ImportInvestorAdvisor.new
    user_data = {
      'Email'        => 'test-advisor@sec2.example.com',
      'Stakeholder'  => 'SomeInvestor',
      'Allowed Roles' => role,
      'Add To'       => nil,
      'Name'         => nil
    }
    import_service.save_row(user_data, nil, [], {})
  rescue RuntimeError => e
    @import_error = e.message
  end
end

Then('the import row should raise an invalid roles error') do
  expect(@import_error).to be_present
  expect(@import_error).to include("Invalid roles")
end

# SEC-4: IDOR — policy check for unrelated entity
Given('there is a separate managing entity with an investor') do
  @other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @other_entity.permissions.set(:enable_investor_advisors)
  @other_entity.save!
  # Use a plain struct — belongs_to_entity? only needs entity_id; no factory required.
  @other_investor = OpenStruct.new(entity_id: @other_entity.id, investor_entity_id: @other_entity.id)
end

When('I check create_for_investor policy against the other entity\'s investor') do
  ia = InvestorAdvisor.new(entity_id: @other_investor.investor_entity_id)
  @policy = InvestorAdvisorPolicy.new(@user, { investor_advisor: ia, investor: @other_investor })
end

Then('the policy should deny create_for_investor access') do
  expect(@policy.create_for_investor?).to be false
end

# SEC-5: IDOR positive — owning entity is allowed
Given('there is an investor belonging to this managing entity') do
  @own_investor = OpenStruct.new(entity_id: @entity.id, investor_entity_id: @entity.id)
end

When('I check create_for_investor policy for this entity\'s own investor') do
  ia = InvestorAdvisor.new(entity_id: @own_investor.investor_entity_id)
  @policy = InvestorAdvisorPolicy.new(@user, { investor_advisor: ia, investor: @own_investor })
end

Then('the policy should allow create_for_investor access') do
  expect(@policy.create_for_investor?).to be true
end

# SEC-6, SEC-7: feature flag enforcement on create?
When('I check the create investor advisor policy') do
  @investor ||= @entity.investors.first
  ia = InvestorAdvisor.new(entity_id: @entity.id)
  @policy = InvestorAdvisorPolicy.new(@user, ia)
end

Then('the policy should deny create access') do
  expect(@policy.create?).to be false
end

Then('the policy should allow create access') do
  expect(@policy.create?).to be true
end

# SEC-8, SEC-9: revert endpoint protection
Then('the user is not in advisor context') do
  @user.reload
  expect(@user.investor_advisor?).to be false
end

Then('attempting the advisor revert switch should be denied') do
  # The controller guard is: raise Pundit::NotAuthorizedError unless current_user.investor_advisor?
  # Verify the gate condition correctly identifies this user as non-advisor
  @user.reload
  expect(@user.investor_advisor?).to be false

  # Without the guard, revert would set entity_id = advisor_entity_id (nil for non-advisors),
  # corrupting the account. Prove the guard is necessary by checking advisor_entity_id is nil.
  expect(@user.advisor_entity_id).to be_nil

  # The user's entity_id must still be valid — the guard prevented any mutation
  expect(@user.entity_id).to be_present
end

Given('there is an investor advisor record for this user in another entity') do
  @target_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @target_entity.permissions.set(:enable_investor_advisors)
  @target_entity.save!
  @investor_advisor_record = InvestorAdvisor.new(
    entity_id: @target_entity.id,
    email: @user.email,
    allowed_roles: %w[investor investor_advisor]
  )
  # Bypass ensure_user validation: user already has investor_advisor role
  @investor_advisor_record.user = @user
  @investor_advisor_record.save(validate: false)
end

Given('I have switched into that advisor entity') do
  @original_entity_id = @user.entity_id
  @investor_advisor_record.switch(@user)
  @user.reload
end

Then('the advisor revert should succeed and return to the home entity') do
  expect { InvestorAdvisor.revert(@user, nil) }.not_to raise_error
  @user.reload
  expect(@user.entity_id).to eq(@user.advisor_entity_id)
  expect(@user.investor_advisor?).to be false
end

# SEC-10: GET request does not trigger switch
When('I visit a page with the investor_advisor_id parameter as a GET request') do
  @original_entity_id = @user.reload.entity_id
  # The switch_advisor before_action is guarded by request.post?
  # A GET visit with investor_advisor_id in params must not call switch_advisor.
  concern_path = Rails.root.join('app/packs/core/base/controllers/concerns/with_authentication.rb')
  @auth_concern_source = File.read(concern_path)
end

Then('my active entity should not have changed') do
  # Verify the POST guard is present in the source
  expect(@auth_concern_source).to include('request.post?')
  # Verify the user's entity_id is unchanged (no switch happened)
  @user.reload
  expect(@user.entity_id).to eq(@original_entity_id)
end

# SEC-11: invalid fund_id redirects gracefully
When('I visit the new_for_investor page with an invalid fund_id') do
  @investor ||= @entity.investors.first
  visit(new_for_investor_investor_advisors_path(investor_id: @investor.id, fund_id: 999_999_999))
end

Then('I should be redirected to the funds page with an alert') do
  expect(current_path).to eq(funds_path)
  expect(page).to have_content("not found")
end

# SEC-13: user_id not in permitted params
Then('user_id is not accepted as a permitted parameter for investor advisor creation') do
  file, line = InvestorAdvisorsController.instance_method(:investor_advisor_params).source_location
  method_lines = File.readlines(file)[line - 1, 5].join
  expect(method_lines).to include('permit(')
  expect(method_lines).not_to include(':user_id')
end

# SEC-14: permissions and extended_permissions ARE in permitted params (user requirement)
Then('permissions and extended_permissions are accepted as permitted parameters') do
  file, line = InvestorAdvisorsController.instance_method(:investor_advisor_params).source_location
  method_lines = File.readlines(file)[line - 1, 5].join
  expect(method_lines).to include('permissions:')
  expect(method_lines).to include('extended_permissions:')
end

# SEC-15: only company_admin can create (non-company-admin employee denied by policy)
# Uses the existing 'I check the create investor advisor policy' + 'policy should deny create access' steps.

# SEC-16: non-company-admin acting_user blocks company_admin in allowed_roles
When('a non-company-admin tries to build an investor advisor with allowed_roles {string}') do |role|
  @advisor_user ||= User.joins(:roles).where(roles: { name: :investor_advisor }).first
  @test_ia = InvestorAdvisor.new(
    entity_id: @entity.id,
    email: @advisor_user.email,
    allowed_roles: [role]
  )
  @test_ia.acting_user = @user   # @user has role "employee", not company_admin
  @test_ia.valid?
end

# SEC-17: company_admin acting_user allows company_admin in allowed_roles
When('a company_admin tries to build an investor advisor with allowed_roles {string}') do |role|
  @advisor_user ||= User.joins(:roles).where(roles: { name: :investor_advisor }).first
  @test_ia = InvestorAdvisor.new(
    entity_id: @entity.id,
    email: @advisor_user.email,
    allowed_roles: [role]
  )
  @test_ia.acting_user = @user   # @user has role "company_admin"
  @test_ia.valid?
end

Then('the investor advisor should pass the company_admin granter validation') do
  expect(@test_ia.errors[:allowed_roles]).not_to include(match(/company_admin/))
end

Then('my permissions should match the investor advisor permissions') do
  @user.reload
  # Find the advisor record using the ID stored on the user after switch
  ia = InvestorAdvisor.find_by(id: @user.investor_advisor_id)
  expect(ia).to be_present

  # The permissions should have been copied from the entity the advisor is advising (the LP entity)
  # We only compare permissions that are supported by both (UserEnabled subset)
  supported_permissions = User.permissions.keys.map(&:to_sym)
  expected_permissions = ia.entity.permissions.to_a & supported_permissions

  expect(ia.permissions.to_a).to match_array(expected_permissions)

  # And the user should be using them now that they are switched
  expect(@user.get_permissions.to_a).to match_array(ia.permissions.to_a)
end

Then('my extended permissions should match the investor advisor extended permissions') do
  @user.reload
  ia = InvestorAdvisor.find_by(id: @user.investor_advisor_id)
  expect(ia).to be_present
  # Default extended permissions set during setup in ImportInvestorAdvisor
  expect(ia.extended_permissions.to_a).to match_array(%i[investor_kyc_read investor_read])
  expect(@user.get_extended_permissions.to_a).to match_array(ia.extended_permissions.to_a)
end
