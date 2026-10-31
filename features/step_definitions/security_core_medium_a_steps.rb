# Steps for the 2026-10 security review, "Core / misc — Medium and Low" rows M7 (chats), M12 (kanban
# boards), M13 (NDA signatories / folder), M14 (nudges), M15 (write-before-authorize: boards, grid
# columns, Configure Grid), M17 (Permission), M18 (task templates), M22 (incoming email create) and
# M25 (form type clone). Scenarios: features/security/security_review_2026_10_medium.feature.
# Design and worked examples: docs/security/security_review_2026_10.md#core--misc--medium-and-low
#
# Requests go through the rack_test driver as the signed-in user, the way a crafted URL or form
# would. People and firms are named in the feature ("Priya" of "Alpha Capital") and kept in hashes,
# so a scenario can switch between them. "I am denied access" (tenant_isolation_batch1_steps.rb)
# checks for the Access Denied flash a refusal redirects to.

module SecurityCoreMediumAHelpers
  # Firms by name
  def cma_firms
    @cma_firms ||= {}
  end

  # People by first name
  def cma_users
    @cma_users ||= {}
  end

  def cma_firm(name)
    cma_firms.fetch(name)
  end

  def cma_user(name)
    cma_users.fetch(name)
  end

  # A fund firm with every feature on (so a refusal is the rule under test), and the default
  # CapitalCommitment form type the grid steps use
  def cma_create_firm(name)
    entity = FactoryBot.create(:entity, name:, entity_type: "Investment Fund")
    FormType.where(name: "CapitalCommitment", entity:, tag: "Default").first_or_create!
    cma_firms[name] = entity
  end

  # A user of `entity` with all user permissions (the factory's default), optionally company admin
  def cma_create_user(entity, first_name, admin: false)
    user = FactoryBot.create(:user, entity:, first_name:, last_name: "Tester")
    user.add_role(:company_admin) if admin
    cma_users[first_name] = user
  end

  # Sends one request as the signed-in user; the response is then on `page`. A removed route raises
  # ActionController::RoutingError in tests (show_exceptions is off) where production answers 404.
  def cma_request(method, path, params = {})
    page.driver.submit(method, path, params)
    @cma_status = page.status_code
  rescue ActionController::RoutingError
    @cma_status = 404
  end

  # The firm's root folder; SetupCompany makes it, guarded as the data room steps do
  def cma_root_folder(entity)
    root = entity.root_folder || Folder.create!(name: "/", entity:, level: 0, folder_type: :system)
    entity.update_column(:root_folder_id, root.id) if entity.root_folder_id != root.id
    root
  end

  # The firm's level-1 "Data Room" folder, as the data room steps make it
  def cma_data_room(entity)
    cma_root_folder(entity).children.find_or_create_by!(name: "Data Room", entity:, folder_type: :regular)
  end

  # The firm's NDA config, on its data room
  def cma_nda_config(firm_name)
    NdaConfig.find_by!(entity: cma_firm(firm_name), owner: cma_data_room(cma_firm(firm_name)))
  end

  # A stakeholder of `entity`: an LP entity of its own and the investor row
  def cma_create_investor(entity, name)
    lp_entity = FactoryBot.create(:entity, name: "#{name} LP", entity_type: "Investor")
    Investor.create!(investor_name: name, entity:, investor_entity: lp_entity, category: "LP",
                     primary_email: lp_entity.primary_email)
  end

  # A deal of `entity`, made the way the deal template steps make one (no template steps)
  def cma_create_deal(entity, name)
    deal = Deal.new(name:, amount_cents: 500_000, status: "Open", currency: entity.currency,
                    entity_id: entity.id, skip_templates: "1")
    result = CreateDeal.call(deal:)
    raise "Deal creation failed: #{deal.errors.full_messages}" unless result.success?

    deal
  end
end
World(SecurityCoreMediumAHelpers)

# ---- Shared -----------------------------------------------------------------------------------

Given('the firm {string} with company admin {string}') do |firm_name, first_name|
  cma_create_user(cma_create_firm(firm_name), first_name, admin: true)
end

Given('{string} is a plain employee of {string}') do |first_name, firm_name|
  cma_create_user(cma_firm(firm_name), first_name)
end

Given('{string} is a plain employee of {string} without the kanban permission') do |first_name, firm_name|
  user = cma_create_user(cma_firm(firm_name), first_name)
  # User#update_kanban_permissions turns kanban back on while deals are on, so both go
  user.permissions.unset(:enable_kanban)
  user.permissions.unset(:enable_deals)
  user.save!
end

Given('{string} is a support user and company admin of {string}') do |first_name, firm_name|
  user = cma_create_user(cma_firm(firm_name), first_name, admin: true)
  user.add_role(:support)
end

Given('{string} is signed in') do |first_name|
  # A fresh session, so a scenario can act as a second person
  Capybara.reset_sessions!
  log_in(cma_user(first_name))
end

Then('the response mentions {string}') do |text|
  expect(page.html).to include(text)
end

Then('the response does not mention {string}') do |text|
  expect(page.html).not_to include(text)
end

Then('the page loads') do
  expect(@cma_status).to eq(200)
end

Then('the request is answered with not found') do
  expect(@cma_status).to eq(404)
end

# ---- M7 chats ---------------------------------------------------------------------------------

Given('{string} has an assistant chat asking {string}') do |first_name, question|
  user = cma_user(first_name)
  @cma_chats ||= {}
  chat = Chat.create!(user:, entity: user.entity, owner: user, assistant_type: "FundAssistant", name: "#{first_name} Chat")
  chat.messages.create!(role: "user", content: question)
  chat.messages.create!(role: "assistant", content: "Answered.")
  @cma_chats[first_name] = chat
end

When("they open {string}'s chat") do |first_name|
  cma_request(:get, chat_path(@cma_chats.fetch(first_name)))
end

When("they open the efficiency report of {string}'s chat") do |first_name|
  cma_request(:get, efficiency_report_assistants_path(chat_id: @cma_chats.fetch(first_name).id))
end

When('they open the efficiency report of a chat that does not exist') do
  cma_request(:get, efficiency_report_assistants_path(chat_id: (Chat.maximum(:id) || 0) + 1000))
end

# ---- M12 kanban -------------------------------------------------------------------------------

Given('{string} has a kanban board {string} with a card {string}') do |firm_name, board_name, card_title|
  entity = cma_firm(firm_name)
  # A plain board owns itself, as BoardsController#create leaves it; its columns come from the
  # firm's kanban steps
  board = KanbanBoard.create!(name: board_name, entity:)
  board.update!(owner: board)
  column = board.kanban_columns.first || KanbanColumn.create!(name: "Todo", sequence: 1, entity:, kanban_board: board)
  KanbanCard.create!(kanban_board: board, kanban_column: column, entity:, title: card_title)
end

When('they filter the board {string}') do |board_name|
  cma_request(:get, kanban_cards_path(board_id: KanbanBoard.find_by!(name: board_name).id))
end

When('they search the board {string}') do |board_name|
  cma_request(:get, search_kanban_cards_path(kanban_board: KanbanBoard.find_by!(name: board_name).id))
end

When('they list deal investors on the board {string}') do |board_name|
  cma_request(:get, deal_investors_path(turbo: true, boards: true, board_id: KanbanBoard.find_by!(name: board_name).id))
end

# ---- M13 NDA ----------------------------------------------------------------------------------

Given('{string} has a data room NDA with signatory {string}') do |firm_name, first_name|
  entity = cma_firm(firm_name)
  admin = User.with_role(:company_admin).find_by!(entity_id: entity.id)
  # The NDA on the firm's data room (fake_shrine_nda_document: nda_config_steps.rb)
  nda_config = NdaConfig.create!(owner: cma_data_room(entity), entity:, enabled: true,
                                 nda_document_data: fake_shrine_nda_document,
                                 validity_type: "until_revoked", acceptance_method: "click_through")
  # An LP user of a stakeholder, tagged as its signatory
  lp_entity = FactoryBot.create(:entity, name: "#{first_name} Family Office", entity_type: "Investor")
  lp_user = cma_create_user(lp_entity, first_name)
  NdaSignatory.create!(nda_config:, user: lp_user, tagged_by: admin)
end

When('they remove the signatory {string} through the NDA of {string}') do |first_name, firm_name|
  signatory = NdaSignatory.find_by!(user: cma_user(first_name))
  cma_request(:delete, nda_status_signatory_path(signatory, nda_config_id: cma_nda_config(firm_name).id))
end

When('they open the NDA status summary of {string} for the data room of {string}') do |config_firm, folder_firm|
  cma_request(:get, nda_status_summary_path(nda_config_id: cma_nda_config(config_firm).id,
                                            folder_id: cma_data_room(cma_firm(folder_firm)).id))
end

Then('{string} is still a signatory of the NDA of {string}') do |first_name, firm_name|
  expect(NdaSignatory.where(user: cma_user(first_name), nda_config: cma_nda_config(firm_name))).to exist
end

Then('{string} is no longer a signatory of the NDA of {string}') do |first_name, firm_name|
  expect(NdaSignatory.where(user: cma_user(first_name), nda_config: cma_nda_config(firm_name))).not_to exist
end

# ---- M14 nudges -------------------------------------------------------------------------------

Given('{string} has a deal investor {string} whose LP contact is {string}') do |firm_name, investor_name, email|
  entity = cma_firm(firm_name)
  investor = cma_create_investor(entity, investor_name)
  # The LP contact, an approved investor access whose email the nudge form would prefill
  lp_user = User.create!(email:, password: "password", entity: investor.investor_entity, first_name: "Lp",
                         last_name: "Contact")
  InvestorAccess.create!(entity:, investor:, user: lp_user, email:, first_name: "Lp", last_name: "Contact",
                         approved: true)
  deal = cma_create_deal(entity, "Series A")
  @cma_deal_investors ||= {}
  @cma_deal_investors[investor_name] = FactoryBot.create(:deal_investor, deal:, entity:, investor:, status: "Active")
end

When('they open a new nudge for the deal investor {string}') do |investor_name|
  cma_request(:get, new_nudge_path(nudge: { item_type: "DealInvestor", item_id: @cma_deal_investors.fetch(investor_name).id }))
end

# ---- M15 boards and grid columns --------------------------------------------------------------

When('they create a board {string}') do |name|
  cma_request(:post, boards_path, { kanban_board: { name: } })
end

When('they create a board {string} for the firm {string}') do |name, firm_name|
  # The form's hidden entity_id, tampered to another firm
  cma_request(:post, boards_path, { kanban_board: { name:, entity_id: cma_firm(firm_name).id } })
end

Then('there is no board {string}') do |name|
  expect(KanbanBoard.where(name:)).not_to exist
end

Then('the board {string} belongs to {string}') do |name, firm_name|
  expect(KanbanBoard.where(name:).pluck(:entity_id)).to eq([cma_firm(firm_name).id])
end

When('they add the grid column {string} to the {string} form type of {string}') do |key, form_type_name, firm_name|
  form_type = FormType.find_by!(entity: cma_firm(firm_name), name: form_type_name)
  cma_request(:post, grid_view_preferences_path,
              { owner_type: "FormType", owner_id: form_type.id,
                grid_view_preference: { key:, label: key.humanize, data_type: "String" } })
end

When('they open Configure Grid for the {string} form type of {string}') do |form_type_name, firm_name|
  form_type = FormType.find_by!(entity: cma_firm(firm_name), name: form_type_name)
  cma_request(:get, configure_grids_grid_view_preferences_path(owner_type: "FormType", owner_id: form_type.id))
end

Then('the {string} form type of {string} has {int} grid column(s)') do |form_type_name, firm_name, count|
  form_type = FormType.find_by!(entity: cma_firm(firm_name), name: form_type_name)
  expect(GridViewPreference.where(owner: form_type).count).to eq(count)
end

# ---- M17 Permission ---------------------------------------------------------------------------

Given('{string} has a document {string}') do |firm_name, name|
  entity = cma_firm(firm_name)
  folder = FactoryBot.create(:folder, entity:, parent: cma_root_folder(entity), name: "#{name} Folder")
  uploader = User.with_role(:company_admin).find_by!(entity_id: entity.id)
  FactoryBot.create(:document, entity:, folder:, user: uploader, name:)
end

When('they grant {string} write on the document {string}') do |first_name, document_name|
  document = Document.find_by!(name: document_name)
  cma_request(:post, permissions_path,
              { permission: { email: cma_user(first_name).email, owner_id: document.id, owner_type: "Document",
                              permissions: %w[read write] } })
end

Given('{string} granted {string} read on the document {string}') do |grantor, grantee, document_name|
  document = Document.find_by!(name: document_name)
  @cma_permission = Permission.create!(email: cma_user(grantee).email, owner: document, entity: document.entity,
                                       granted_by: cma_user(grantor), permissions: %w[read])
end

When('they open that permission') do
  cma_request(:get, permission_path(@cma_permission))
end

Then('{string} has no permission on the document {string}') do |first_name, document_name|
  expect(Permission.where(owner: Document.find_by!(name: document_name), user: cma_user(first_name))).not_to exist
end

Then('{string} cannot change the document {string}') do |first_name, document_name|
  expect(DocumentPolicy.new(User.find(cma_user(first_name).id), Document.find_by!(name: document_name)).update?).to be false
end

Then('{string} can change the document {string}') do |first_name, document_name|
  expect(DocumentPolicy.new(User.find(cma_user(first_name).id), Document.find_by!(name: document_name)).update?).to be true
end

# ---- M18 task templates -----------------------------------------------------------------------

Given('there is a global {string} task template {string}') do |for_class, details|
  TaskTemplate.create!(for_class:, details:, due_in_days: 3, entity_id: nil)
end

Given('{string} has a {string} task template {string}') do |firm_name, for_class, details|
  TaskTemplate.create!(for_class:, details:, due_in_days: 3, entity: cma_firm(firm_name))
end

When('they create a {string} task template {string} for no firm') do |for_class, details|
  # entity_id left blank: a global template
  cma_request(:post, task_templates_path, { task_template: { for_class:, details:, due_in_days: 3, entity_id: "" } })
end

When('they create a {string} task template {string} for {string}') do |for_class, details, firm_name|
  cma_request(:post, task_templates_path,
              { task_template: { for_class:, details:, due_in_days: 3, entity_id: cma_firm(firm_name).id } })
end

When('they change the task template {string} to {string}') do |details, new_details|
  cma_request(:patch, task_template_path(TaskTemplate.find_by!(details:)), { task_template: { details: new_details } })
end

When('they open the task template {string}') do |details|
  cma_request(:get, task_template_path(TaskTemplate.find_by!(details:)))
end

Then('there is no task template {string}') do |details|
  expect(TaskTemplate.where(details:)).not_to exist
end

Then('the task template {string} is global') do |details|
  expect(TaskTemplate.find_by!(details:).entity_id).to be_nil
end

Then('the task template {string} belongs to {string}') do |details, firm_name|
  expect(TaskTemplate.find_by!(details:).entity_id).to eq(cma_firm(firm_name).id)
end

# WithNextSteps#generate_next_steps without saving: the details of the tasks it would create
Then('next steps for a {string} of {string} are {string}') do |for_class, firm_name, expected|
  record = for_class.constantize.new(entity_id: cma_firm(firm_name).id)
  expect(record.generate_next_steps(save_step: false).map(&:details).sort).to eq(expected.split(",").map(&:strip).sort)
end

Then('a task template with help link {string} is refused') do |link|
  template = TaskTemplate.new(for_class: "CapitalCall", details: "Read the guide", due_in_days: 1, help_link: link)
  expect(template).not_to be_valid
  expect(template.errors[:help_link]).to be_present
end

Then('a task template with help link {string} is accepted') do |link|
  expect(TaskTemplate.new(for_class: "CapitalCall", details: "Read the guide", due_in_days: 1, help_link: link)).to be_valid
end

# ---- M22 incoming email -----------------------------------------------------------------------

Given('{string} has an investor {string}') do |firm_name, name|
  cma_create_investor(cma_firm(firm_name), name)
end

Given('{string} has an incoming email {string} against the investor {string}') do |firm_name, subject, investor_name|
  IncomingEmail.create!(from: "sender@example.com", to: "inbox@example.com", subject:, body: "Hello",
                        owner: Investor.find_by!(investor_name:), entity: cma_firm(firm_name))
end

When('they file an email {string} against the investor {string} through the plain form') do |subject, investor_name|
  investor = Investor.find_by!(investor_name:)
  # The form's owner and entity_id, both pointing at the other firm
  cma_request(:post, incoming_emails_path,
              { incoming_email: { from: "sender@example.com", to: "inbox@example.com", subject:, body: "Hello",
                                  owner_type: "Investor", owner_id: investor.id, entity_id: investor.entity_id } })
end

When('they file an email {string} against the investor {string} from the investor page') do |subject, investor_name|
  investor = Investor.find_by!(investor_name:)
  cma_request(:post, incoming_emails_path(format: :json),
              { investor_id: investor.id,
                incoming_email: { from: "sender@example.com", to: "inbox@example.com", subject:, body: "Hello" } })
end

When('the email {string} is moved onto the investor {string}') do |subject, investor_name|
  @cma_email = IncomingEmail.find_by!(subject:)
  @cma_moved = @cma_email.update(owner: Investor.find_by!(investor_name:))
end

Then('the move is refused and {string} stays against the investor {string}') do |subject, investor_name|
  expect(@cma_moved).to be false
  expect(@cma_email.errors[:owner]).to include("must be in this record's firm")
  expect(IncomingEmail.find_by!(subject:).owner).to eq(Investor.find_by!(investor_name:))
end

Then('there is no incoming email {string}') do |subject|
  expect(IncomingEmail.where(subject:)).not_to exist
end

Then('the incoming email {string} is filed in {string} against the investor {string}') do |subject, firm_name, investor_name|
  email = IncomingEmail.find_by!(subject:)
  expect(email.entity_id).to eq(cma_firm(firm_name).id)
  expect(email.owner).to eq(Investor.find_by!(investor_name:))
end

# ---- M25 form type clone ----------------------------------------------------------------------

Given('{string} has a form type {string}') do |firm_name, name|
  FormType.create!(name:, entity: cma_firm(firm_name), tag: "Default")
end

When('they open the old clone address for the {string} form type of {string}') do |name, firm_name|
  form_type = FormType.find_by!(entity: cma_firm(firm_name), name:)
  # Literal path: the GET route went (the POST one shares the helper name)
  cma_request(:get, "/form_types/#{form_type.id}/clone")
end

When('they clone the {string} form type of {string}') do |name, firm_name|
  cma_request(:post, clone_form_type_path(FormType.find_by!(entity: cma_firm(firm_name), name:)))
end

Then('{string} has no {string} form type') do |firm_name, name|
  expect(FormType.where(entity: cma_firm(firm_name), name:)).not_to exist
end

Then('{string} has a {string} form type') do |firm_name, name|
  expect(FormType.where(entity: cma_firm(firm_name), name:)).to exist
end
