# Investor advisor notification recipients — exercises Investor#notification_users (via
# Investor#visible_from_home_entity? and User#home_persona) and DocumentSender directly, the
# way the app's notifiers do. @user / @entity come from the shared login step.

Given("the advisor's home persona roles are {string}") do |roles|
  # Pin the home persona so the scenarios do not depend on setup_defaults' fallback.
  @user.update_columns(advisor_entity_id: @user.entity_id, advisor_entity_roles: roles)
  @user.reload
  expect(@user.investor_advisor?).to be false
end

Given('there is a fund company {string} with a fund {string}') do |entity_args, fund_args|
  @fund_company = FactoryBot.build(:entity, entity_type: "Investment Fund")
  key_values(@fund_company, entity_args)
  @fund_company.save!
  @fund = FactoryBot.build(:fund, entity: @fund_company)
  key_values(@fund, fund_args)
  @fund.save!
end

Given('the advisor is the sole approved contact on an investor record of the fund company for his own home entity') do
  home = Entity.find(@user.advisor_entity_id)
  @investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: home.id,
                                           investor_name: home.name, category: "LP")
  InvestorAccess.create!(investor: @investor, user: @user, entity_id: @fund_company.id,
                         first_name: @user.first_name, last_name: @user.last_name,
                         email: @user.email, approved: true)
  # Fund access is granted to the investor record, as production does — there is deliberately
  # no user-level access right for the advisor anywhere.
  AccessRight.create!(owner: @fund, access_to_investor_id: @investor.id, entity_id: @fund_company.id, notify: false)
  @user.reload
  expect(@user.entity_id).to eq(home.id)
  expect(@investor.approved_investor_accesses.count).to eq(1)
end

Given('the investor has a KYC with an approved document that grants access to the investor') do
  @investor_kyc = FactoryBot.create(:investor_kyc, entity: @fund_company, investor: @investor,
                                                   kyc_type: "individual", verified: true)
  @capital_commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund_company,
                                                               investor: @investor, investor_kyc: @investor_kyc)
  @document = Document.create!(entity: @fund_company, name: "Contribution Agreement", owner: @investor_kyc,
                               folder: @investor_kyc.document_folder, user: @user,
                               file: File.new("public/img/whatsappQR.png", "r"))
  # Document creation inherits the folder's investor-scoped grant; only add it if it did not.
  AccessRight.where(owner: @document, access_to_investor_id: @investor.id).first ||
    AccessRight.create!(owner: @document, access_to_investor_id: @investor.id, entity_id: @fund_company.id,
                        access_type: "Document", notify: false)
  expect(@document.reload.subject_to_approval?).to be false
  expect(@document.access_rights.where(access_to_investor_id: @investor.id).count).to eq(1)
  expect(@document.access_rights.where.not(user_id: nil)).to be_empty
end

Given('the advisor has switched into an unrelated host entity that granted him roles {string}') do |roles|
  @host_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @host_entity.permissions.set(:enable_investor_advisors)
  @host_entity.save!
  @investor_advisor_record = InvestorAdvisor.new(entity_id: @host_entity.id, email: @user.email,
                                                 allowed_roles: roles.split(",").map(&:strip))
  # Bypass ensure_user validation: user already has investor_advisor role
  @investor_advisor_record.user = @user
  @investor_advisor_record.save(validate: false)
  @investor_advisor_record.switch(@user)
  @user.reload
  expect(@user.investor_advisor?).to be true
  expect(@user.entity_id).to eq(@host_entity.id)
  @switched_state = [@user.entity_id, @user.roles.map(&:name).sort]
end

Then('the advisor is a notification recipient for the KYC document') do
  expect(@investor.notification_users(@document).map(&:id)).to include(@user.id)
  expect(@document.notification_users.map(&:id)).to include(@user.id)
end

Then('sending the KYC document succeeds and is delivered to the advisor') do
  expect { DocumentSender.send(@document, @user.id, nil) }.not_to raise_error
  open_email(@user.email)
  expect(current_email).not_to be_nil, "No email delivered to #{@user.email}"
end

Then("the advisor's persisted entity and roles are unchanged by the recipient check") do
  @user.reload
  expect([@user.entity_id, @user.roles.map(&:name).sort]).to eq(@switched_state)
end

When('I record the notification recipients for the KYC document while switched') do
  @recipients_while_switched = @document.notification_users.map(&:id).sort
  expect(@recipients_while_switched).to include(@user.id)
end

Then('the notification recipients for the KYC document after reverting are the same set') do
  expect(@document.notification_users.map(&:id).sort).to eq(@recipients_while_switched)
end

Then('a user who is not switched away has no home persona') do
  expect(@user.reload.home_persona).to be_nil
end

Then('the home persona of the advisor carries only his home entity and home roles') do
  persona = @user.home_persona
  expect(persona).to be_present
  home = Entity.find(@user.advisor_entity_id)
  expect(persona.entity_id).to eq(home.id)
  expect(persona.entity_type).to eq(home.entity_type)
  expect(persona.investor_advisor?).to be false

  home_roles = @user.advisor_entity_roles.split(",").map(&:strip).sort
  expect(persona.roles.map(&:name).sort).to eq(home_roles)
  expect(persona.has_cached_role?(:investor_advisor)).to be true
  expect(persona.has_cached_role?(:company_admin)).to be false
  expect(persona.has_cached_role?(:approver)).to be false

  # Tripwire: nothing that touches the persona can persist it.
  expect(persona).to be_readonly
  expect { persona.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)

  # And building it changed nothing on the real user.
  @user.reload
  expect(@user.entity_id).to eq(@host_entity.id)
  expect(@user.has_cached_role?(:company_admin)).to be true
end

Given("there is an unapproved generated document in the advisor's home entity that only a company admin there could see") do
  home = Entity.find(@user.advisor_entity_id)
  @home_investor = FactoryBot.create(:investor, entity_id: home.id, investor_entity_id: home.id,
                                                investor_name: home.name, category: "LP")
  InvestorAccess.create!(investor: @home_investor, user: @user, entity_id: home.id,
                         first_name: @user.first_name, last_name: @user.last_name,
                         email: @user.email, approved: true)
  home_kyc = FactoryBot.create(:investor_kyc, entity: home, investor: @home_investor, kyc_type: "individual")
  # A private folder: only the company_admin branch of DocumentPolicy#show? ignores folder
  # privacy, so the home persona cannot reach the draft through the KYC owner policy - which
  # now shows a commitment-less KYC to home-entity staff (#1746 visibility rule).
  # Owner is set explicitly: Folder#set_parent_permissions copies the parent's private flag
  # onto an ownerless child, which would undo private: true.
  private_folder = Folder.create!(name: "Drafts", parent: home_kyc.document_folder, entity: home,
                                  owner: home_kyc, private: true)
  # from_template_id + not approved => subject_to_approval? and not yet approved: the
  # investor-side paths of DocumentPolicy#show? require approval.
  @hidden_document = Document.create!(entity: home, name: "Generated draft", owner: home_kyc,
                                      folder: private_folder, user: @user,
                                      file: File.new("public/img/whatsappQR.png", "r"),
                                      from_template_id: @document.id, approved: false)
  AccessRight.where(owner: @hidden_document, access_to_investor_id: @home_investor.id).first ||
    AccessRight.create!(owner: @hidden_document, access_to_investor_id: @home_investor.id, entity_id: home.id,
                        access_type: "Document", notify: false)
  expect(@hidden_document.reload.subject_to_approval?).to be true
  expect(@hidden_document.approved).to be false
  # Guard the premise: if the folder stops being private, the home persona can see the draft.
  expect(@hidden_document.folder.reload.private).to be true
end

Then('the switched-in roles combined with the home entity would expose that document') do
  # The hybrid the fix must never evaluate: home entity_id with the roles persisted from the host.
  hybrid = User.find(@user.id)
  hybrid.entity_id = hybrid.advisor_entity_id
  expect(hybrid.has_cached_role?(:company_admin)).to be true
  expect(DocumentPolicy.new(hybrid, @hidden_document).show?).to be true
  # The genuine home persona cannot see it.
  expect(DocumentPolicy.new(@user.home_persona, @hidden_document).show?).to be false
end

Then('the advisor is not a notification recipient for that document') do
  expect(@home_investor.notification_users(@hidden_document).map(&:id)).not_to include(@user.id)
  expect(@hidden_document.notification_users.map(&:id)).not_to include(@user.id)
  expect { DocumentSender.send(@hidden_document, @user.id, nil) }.to raise_error(StandardError, /not approved/)
end

Then('the advisor is a recipient of the KYC form notification') do
  expect(@investor_kyc.notification_users.map(&:id)).to include(@user.id)
end

When('I record the KYC form recipients while switched') do
  @kyc_recipients_while_switched = @investor_kyc.notification_users.map(&:id).sort
  expect(@kyc_recipients_while_switched).to include(@user.id)
end

Then('the KYC form recipients after reverting are the same set') do
  expect(@investor_kyc.reload.notification_users.map(&:id).sort).to eq(@kyc_recipients_while_switched)
end

When('I visit the KYC document while switched into the host entity') do
  expect(@user.reload.investor_advisor?).to be true
  visit document_path(@document)
end

Then('I am told to switch my persona back to view it') do
  expect(page).to have_text("Access Denied")
  expect(page).to have_text("Switch your persona to Self")
end

When('I visit that hidden document') do
  visit document_path(@hidden_document)
end

Then('I am simply denied access') do
  expect(page).to have_text("Access Denied")
  expect(page).not_to have_text("Switch your persona")
end

Given('the host entity is renamed to {string}') do |name|
  @host_entity.update_columns(name: name)
end

Then('the host entity name is shown escaped, not rendered as markup') do
  # The layout also has an empty <span id="alert">; the flash lives in #page_alerts.
  within("#page_alerts .alert-danger") do
    expect(page).to have_text("Client <b>Bold</b> & Co")
    expect(page).not_to have_css("b", text: "Bold")
  end
end

Given('the stored home persona roles are changed to {string}') do |roles|
  @user.update_columns(advisor_entity_roles: roles)
  @user.reload
end

Then('the home persona roles equal the roles after a real revert') do
  persona_roles = @user.home_persona.roles.map(&:name).sort
  expect(persona_roles).to include("investor_advisor")
  InvestorAdvisor.revert(@user, nil)
  @user.reload
  expect(@user.investor_advisor?).to be false
  expect(@user.roles.map(&:name).sort).to eq(persona_roles)
end

Given("the advisor is also an approved contact on another client's investor record with a KYC document") do
  @client_entity = FactoryBot.create(:entity, entity_type: "Investor")
  @client_investor = FactoryBot.create(:investor, entity_id: @fund_company.id, investor_entity_id: @client_entity.id,
                                                  investor_name: @client_entity.name, category: "LP")
  InvestorAccess.create!(investor: @client_investor, user: @user, entity_id: @fund_company.id,
                         first_name: @user.first_name, last_name: @user.last_name,
                         email: @user.email, approved: true)
  AccessRight.create!(owner: @fund, access_to_investor_id: @client_investor.id, entity_id: @fund_company.id, notify: false)
  client_kyc = FactoryBot.create(:investor_kyc, entity: @fund_company, investor: @client_investor,
                                                kyc_type: "individual", verified: true)
  FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund_company,
                                         investor: @client_investor, investor_kyc: client_kyc)
  @client_document = Document.create!(entity: @fund_company, name: "Client Contribution Agreement", owner: client_kyc,
                                      folder: client_kyc.document_folder, user: @user,
                                      file: File.new("public/img/whatsappQR.png", "r"))
  AccessRight.where(owner: @client_document, access_to_investor_id: @client_investor.id).first ||
    AccessRight.create!(owner: @client_document, access_to_investor_id: @client_investor.id,
                        entity_id: @fund_company.id, access_type: "Document", notify: false)
  expect(@client_investor.investor_entity_id).not_to eq(@user.advisor_entity_id)
end

Then("the advisor is not a notification recipient for the client's document and his home persona is not consulted") do
  expect_any_instance_of(User).not_to receive(:home_persona)
  expect(@client_investor.notification_users(@client_document).map(&:id)).not_to include(@user.id)
  expect(@client_document.notification_users.map(&:id)).not_to include(@user.id)
end
