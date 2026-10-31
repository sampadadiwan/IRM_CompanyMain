# Steps for the 2026-10 security review items M27 (template rendering), M28 (child ids), L1 (direct-upload
# endpoint), L6 (ActionCable identification), L11 (blog / deal activity scope) and L12 (small lookups).
# Design and worked examples: docs/security/security_review_2026_10.md ("Core / misc — Medium and Low").
#
# Reused from elsewhere:
#   features/common.rb                       — "there is a user … for an entity …", "the user has role …",
#                                              "the user has curr role …"
#   login.rb                                 — "Im logged in as a user … for an entity …"
#   investor.rb                              — "there is an existing portfolio company …"
#   portco_kpi_upload_steps.rb               — "a KpiReport … exists for the portfolio company …"
#   security_c4_c7_h16_l10_steps.rb          — sr_request / sr_sign_in, "the address is not found",
#                                              "I am signed in as a company admin of another firm …"
#   tenant_isolation_batch1_steps.rb         — "I am denied access"
#
# Requests go through the rack_test driver as the signed-in user, the way a crafted URL or form would.

# ActionCable::Connection::TestConnection, for building a connection outside a Rails test case (L6)
require "action_cable/connection/test_case"

module SecurityCoreMediumBHelpers
  # Another firm, created once per name
  def cmb_firm(name)
    Entity.find_by(name:) || FactoryBot.create(:entity, name:, entity_type: "Investment Fund")
  end

  # A stakeholder of `entity`, linked to an LP firm of its own
  def cmb_stakeholder(entity, name)
    lp_entity = Entity.find_by(name:) || FactoryBot.create(:entity, name:, entity_type: "Investor")
    FactoryBot.create(:investor, entity_id: entity.id, investor_entity_id: lp_entity.id, investor_name: name, category: "LP")
  end

  def cmb_investor(name)
    Investor.find_by!(investor_name: name)
  end

  # A fund of `entity`, created once per name
  def cmb_fund(entity, name)
    Fund.find_by(entity_id: entity.id, name:) || FactoryBot.create(:fund, entity:, name:)
  end

  # A user of `entity`, created once per first name
  def cmb_user(entity, first_name)
    User.find_by(entity_id: entity.id, first_name:) || FactoryBot.create(:user, entity:, first_name:)
  end

  def cmb_user_named(first_name)
    User.find_by!(first_name:)
  end

  # A document uploaded with `owner` (nil: into the firm's root folder, so it has no owner)
  def cmb_document(name, owner: nil)
    attrs = { name:, user: @user, entity: @entity, file: Rails.public_path.join("img/whatsappQR.png").open("rb") }
    attrs[owner ? :owner : :folder] = owner || @entity.reload.root_folder
    Document.create!(attrs)
  end

  # A KYC of my firm for `investor`
  def cmb_kyc(investor)
    FactoryBot.create(:investor_kyc, entity: @entity, investor:, kyc_type: "individual", verified: false)
  end

  # Saves `record` and keeps the outcome for the "is refused" / "is saved" steps
  def cmb_save(record)
    @cmb_record = record
    @cmb_saved = record.save
  end

  def cmb_expect_refused(message)
    expect(@cmb_saved).to be(false)
    expect(@cmb_record.errors.full_messages).to include(message)
  end

  # ---- M27 ----------------------------------------------------------------------------------------

  # A one-paragraph .docx whose only content is the Sablon merge field `field` (e.g. "=investor.destroy"),
  # built at runtime so the scenario shows exactly what the template says
  def m27_docx(path, field)
    document = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:fldSimple w:instr=" MERGEFIELD #{field} \\* MERGEFORMAT "><w:r><w:t>«#{field}»</w:t></w:r></w:fldSimple></w:p></w:body></w:document>
    XML
    entries = {
      "[Content_Types].xml" => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
      "_rels/.rels" => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      "word/_rels/document.xml.rels" => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>',
      "word/document.xml" => document
    }
    Zip::OutputStream.open(path) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    path
  end

  # Runs the real mail merge (DocumentGeneratorBase#convert, no PDF step) with the stakeholder as
  # `investor`, decorated the way doc generators decorate it. Keeps the error or the merged text.
  def m27_generate(field)
    dir = Rails.root.join("tmp", "m27", SecureRandom.hex(6)).to_s
    (@m27_dirs ||= []) << dir
    FileUtils.mkdir_p(dir)
    template = Sablon.template(m27_docx(File.join(dir, "template.docx"), field))
    output = File.join(dir, "generated")
    generator = Class.new { include DocumentGeneratorBase }.new
    @m27_error = nil
    generator.convert(template, { "investor" => TemplateDecorator.decorate(@cmb_investor.reload) }, output, to_pdf: false)
    @m27_text = Zip::File.open("#{output}.docx") do |zip|
      Nokogiri::XML(zip.read("word/document.xml")).remove_namespaces!.xpath("//t").map(&:text).join
    end
  rescue StandardError => e
    @m27_error = e
  end

  # ---- L1 / L6 ------------------------------------------------------------------------------------

  # A live-update connection built from a bare Rack env: `warden_user` stands in for Devise's session
  # user, `session` for the cookie session that a magic-link visit writes
  # (built the way ActionCable::Connection::TestCase#connect builds its connection)
  def l6_connect(warden_user: nil, session: {})
    warden = Struct.new(:signed_in) { def user(_scope = nil) = signed_in }.new(warden_user)
    request = ActionDispatch::TestRequest.create("PATH_INFO" => "/cable", "warden" => warden)
    request.session = session.with_indifferent_access
    connection = ApplicationCable::Connection.allocate
    connection.singleton_class.include(ActionCable::Connection::TestConnection)
    connection.send(:initialize, request)
    connection.connect
    @l6_rejected = false
    @l6_user = connection.current_user
  rescue ActionCable::Connection::Authorization::UnauthorizedError
    @l6_rejected = true
    @l6_user = nil
  end

  # ---- L11 / L12 ----------------------------------------------------------------------------------

  # A deal of `entity` with one template step, through CreateDeal as the app creates deals
  def cmb_deal(entity, name, step_title: nil, clone_from: nil)
    deal = Deal.new(name:, amount_cents: 500_000, status: "Open", currency: entity.currency, entity_id: entity.id,
                    clone_from_id: clone_from&.id)
    # No default steps, except when cloning: the cloned deal's steps are what is under test
    deal.skip_templates = "1" unless clone_from
    result = CreateDeal.call(deal:)
    # One template step, once the deal exists
    DealActivity.create!(deal:, entity_id: entity.id, title: step_title, days: 2, sequence: 1) if step_title && result.success?
    [deal, result]
  end

  # A formula call fee of `fund` (call fees hang off a capital call of the fund)
  def cmb_fee_formula(fund, name)
    call = FactoryBot.create(:capital_call, fund:, entity: fund.entity)
    CallFee.create!(name:, entity: fund.entity, fund:, capital_call: call, start_date: Time.zone.today - 1.year,
                    end_date: Time.zone.today + 1.year, fee_type: "Other Fees", formula: true, notes: "0")
  end

  # A report template of `entity`'s portfolio report
  def cmb_report_template(entity, name)
    report = PortfolioReport.create!(entity:, name: "#{name} Report")
    PortfolioReportTemplate.create!(portfolio_report: report, name:, output_format: "word")
  end

  def cmb_report_draft(company, template)
    PortfolioReportDraft.new(portfolio_company: company, portfolio_report: template.portfolio_report,
                             portfolio_report_template: template, user: @user, start_date: Date.new(2026, 1, 1),
                             end_date: Date.new(2026, 3, 31), kpi_period_type: "Quarter", kpi_tag: "Actual", n_periods: 4)
  end
end
World(SecurityCoreMediumBHelpers)

After do
  # Undo any "N hours pass", and drop the generated M27 files
  travel_back
  Array(@m27_dirs).each { |dir| FileUtils.rm_rf(dir) }
end

# ---- Shared ---------------------------------------------------------------------------------------

Given('the firm {string} has a fund {string}') do |firm, fund|
  cmb_fund(cmb_firm(firm), fund)
end

Given('my firm has a fund {string}') do |fund|
  cmb_fund(@entity, fund)
end

Given('the firm {string} has the stakeholder {string}') do |firm, name|
  cmb_stakeholder(cmb_firm(firm), name)
end

Given('my firm has the stakeholders {string} and {string}') do |first, second|
  [first, second].each { |name| cmb_stakeholder(@entity, name) }
end

Given('the firm {string} has the user {string}') do |firm, first_name|
  cmb_user(cmb_firm(firm), first_name)
end

Given('my firm has the user {string}') do |first_name|
  cmb_user(@entity, first_name)
end

Given('I am not signed in') do
  Capybara.reset_sessions!
end

Given('{int} hour(s) pass(es)') do |hours|
  travel hours.hours
end

# ---- M27 ------------------------------------------------------------------------------------------

Given('my firm has the stakeholder {string} for document generation') do |name|
  @cmb_investor = cmb_stakeholder(@entity, name)
  @m27_updated_at = @cmb_investor.reload.updated_at
end

When('a template with the merge field {string} is generated for the stakeholder') do |field|
  # Later than the stakeholder's own timestamp, so a touch would show
  travel 1.minute
  m27_generate(field)
end

Then('the generation fails with {string}') do |message|
  expect(@m27_error).to be_present
  expect(@m27_error.message).to include(message)
end

Then('the stakeholder {string} still exists') do |name|
  expect(Investor.where(investor_name: name, deleted_at: nil)).to exist
end

Then('the stakeholder {string} was not updated') do |name|
  expect(cmb_investor(name).updated_at).to eq(@m27_updated_at)
end

Then('the generated document reads {string}') do |text|
  expect(@m27_error).to be_nil
  expect(@m27_text).to include(text)
end

# ---- M28 ------------------------------------------------------------------------------------------

Given('my firm has a fund {string} with the document {string}') do |fund, document|
  cmb_document(document, owner: cmb_fund(@entity, fund))
end

Given('my firm has the ownerless document {string}') do |document|
  expect(cmb_document(document).owner).to be_nil
end

When('I change the owner of the document {string} to the fund {string}') do |document, fund|
  doc = Document.find_by!(name: document)
  target = Fund.find_by!(name: fund)
  # documents#update with owner_type / owner_id in the form, as a crafted request would send them
  sr_request(:patch, document_path(doc), document: { owner_type: "Fund", owner_id: target.id })
end

Then('the document {string} is still owned by the fund {string}') do |document, fund|
  expect(Document.find_by!(name: document).owner).to eq(Fund.find_by!(name: fund))
end

Then('the document {string} has no owner') do |document|
  expect(Document.find_by!(name: document).owner).to be_nil
end

When('a KYC of my firm is saved for the stakeholder {string}') do |name|
  cmb_save(FactoryBot.build(:investor_kyc, entity: @entity, investor: cmb_investor(name), kyc_type: "individual", verified: false))
end

Then('the KYC is refused with {string}') do |message|
  cmb_expect_refused(message)
end

Given('my firm has a KYC for the stakeholder {string}') do |name|
  @cmb_kyc = cmb_kyc(cmb_investor(name))
end

When('the KYC is moved to the stakeholder {string}') do |name|
  @cmb_kyc.investor = cmb_investor(name)
  cmb_save(@cmb_kyc)
end

Then('the KYC still belongs to the stakeholder {string}') do |name|
  expect(InvestorKyc.find(@cmb_kyc.id).investor).to eq(cmb_investor(name))
end

When("the KYC's full name is changed to {string}") do |full_name|
  @cmb_kyc.reload.full_name = full_name
  cmb_save(@cmb_kyc)
end

Then('the KYC is saved') do
  expect(@cmb_saved).to be(true), @cmb_record.errors.full_messages.join(", ")
end

Then('the KYC form fields for me do not include {string}') do |fields|
  permitted = InvestorKycPolicy.new(@user, InvestorKyc).permitted_attributes
  fields.split(",").map(&:strip).each { |field| expect(permitted).not_to include(field.to_sym) }
end

Then('the KYC form fields for me include {string}') do |fields|
  permitted = InvestorKycPolicy.new(@user, InvestorKyc).permitted_attributes
  fields.split(",").map(&:strip).each { |field| expect(permitted).to include(field.to_sym) }
end

When('a task of my firm is assigned to {string}') do |first_name|
  cmb_save(Task.new(entity: @entity, details: "Chase the KYC", user: @user, assigned_to: cmb_user_named(first_name)))
end

Then('the task is refused with {string}') do |message|
  cmb_expect_refused(message)
end

Then('the task is saved') do
  expect(@cmb_saved).to be(true), @cmb_record.errors.full_messages.join(", ")
end

Given('a task of my firm was assigned to {string} before the check existed') do |first_name|
  # Legacy row: written past validations, as the 17 cross-firm assignees in prod were
  @cmb_task = Task.new(entity: @entity, details: "Chase the KYC", user: @user, assigned_to: cmb_user_named(first_name))
  @cmb_task.save!(validate: false)
end

When("the task's details are changed to {string}") do |details|
  @cmb_task.reload.details = details
  cmb_save(@cmb_task)
end

When('the fund {string} is granted to the stakeholder {string}') do |fund, name|
  cmb_save(AccessRight.new(owner: Fund.find_by!(name: fund), entity: @entity, access_type: "Fund",
                           investor: cmb_investor(name), notify: false))
end

When('the fund {string} is granted to the user {string}') do |fund, first_name|
  cmb_save(AccessRight.new(owner: Fund.find_by!(name: fund), entity: @entity, access_type: "Fund",
                           user_id: cmb_user_named(first_name).id, notify: false))
end

Then('the access right is refused with {string}') do |message|
  cmb_expect_refused(message)
end

Then('the access right is saved') do
  expect(@cmb_saved).to be(true), @cmb_record.errors.full_messages.join(", ")
end

# ---- L1 -------------------------------------------------------------------------------------------

Given("{string} opens the KPI report's magic link without signing in") do |first_name|
  # A fresh, signed-out browser session opening the emailed link (this is what remembers the visit)
  Capybara.reset_sessions!
  signed_id = KpiReport.signed_id_for_user(@kpi_report, cmb_user_named(first_name))
  sr_request(:get, edit_kpi_report_path(id: :shared, signed_id:))
  expect(@sr_status).to eq(200)
end

When('a file is posted to the upload endpoint') do
  # What Uppy sends to Shrine's upload endpoint (test and development mount /upload)
  file = Rack::Test::UploadedFile.new(Rails.public_path.join("img/whatsappQR.png"), "image/png")
  sr_request(:post, "/upload", file:)
end

Then('the upload is stored') do
  expect(@sr_status).to eq(200)
  expect(JSON.parse(@sr_body)).to include("id", "storage" => "cache")
end

# ---- L6 -------------------------------------------------------------------------------------------

When('a live-update socket connects with no user') do
  l6_connect
end

When('a live-update socket connects signed in as {string}') do |first_name|
  l6_connect(warden_user: cmb_user_named(first_name))
end

When('a live-update socket connects from a magic-link visit by {string} {int} hours ago') do |first_name, hours|
  l6_connect(session: { UploadAccess::SESSION_USER_KEY => cmb_user_named(first_name).id,
                        UploadAccess::SESSION_AT_KEY => hours.hours.ago.to_i })
end

When('a live-update socket connects from a magic-link visit by {string} {int} minutes ago') do |first_name, minutes|
  l6_connect(session: { UploadAccess::SESSION_USER_KEY => cmb_user_named(first_name).id,
                        UploadAccess::SESSION_AT_KEY => minutes.minutes.ago.to_i })
end

Then('the socket is refused') do
  expect(@l6_rejected).to be(true)
end

Then('the socket belongs to {string}') do |first_name|
  expect(@l6_rejected).to be(false)
  expect(@l6_user).to eq(cmb_user_named(first_name))
end

Given('live-update disconnects are recorded') do
  @l6_disconnects = Hash.new(0)
  disconnects = @l6_disconnects
  # Each where(current_user:) ... disconnect is counted per user instead of going out on pub/sub
  allow(ActionCable.server.remote_connections).to receive(:where) do |identifiers|
    double("remote connection", disconnect: (disconnects[identifiers[:current_user].id] += 1))
  end
end

When('{string} sets a new password on their profile') do |first_name|
  user = cmb_user_named(first_name)
  user.update!(password: "N3w-Passw0rd!", password_confirmation: "N3w-Passw0rd!")
end

When('{string} is deactivated through their user record') do |first_name|
  cmb_user_named(first_name).update!(active: false)
end

Then('the sockets of {string} were disconnected {int} time(s)') do |first_name, count|
  expect(@l6_disconnects[cmb_user_named(first_name).id]).to eq(count)
end

# ---- L11 ------------------------------------------------------------------------------------------

When('I post a new blog {string}') do |title|
  sr_request(:post, blogs_path, blog: { title:, content: "Notes for LPs" })
end

Then('there is no blog {string}') do |title|
  expect(Blog.where(title:)).not_to exist
end

Then('there is a blog {string}') do |title|
  expect(Blog.where(title:)).to exist
end

Given('my firm has the deals {string} and {string} each with the step {string}') do |first, second, step|
  [first, second].each { |name| cmb_deal(@entity, name, step_title: "#{step} #{name}") }
end

Given('my firm has the employee {string} with access to the deal {string} only') do |first_name, deal|
  employee = cmb_user(@entity, first_name)
  # A user grant on that one deal, as the deal's access screen gives
  AccessRight.create!(owner: Deal.find_by!(name: deal), entity: @entity, access_type: "Deal", user_id: employee.id, notify: false)
end

Given('my firm has the employee {string} with access to nothing') do |first_name|
  cmb_user(@entity, first_name)
end

Then('the deal activities {string} lists are those of the deal {string} only') do |first_name, deal|
  listed = DealActivityPolicy::Scope.new(cmb_user_named(first_name), DealActivity).resolve
  expect(listed.map(&:deal_id).uniq).to eq([Deal.find_by!(name: deal).id])
end

Then('the deal activities the user lists are those of the deals {string}') do |deals|
  listed = DealActivityPolicy::Scope.new(@user.reload, DealActivity).resolve
  expect(listed.map(&:deal_id).uniq.sort).to eq(Deal.where(name: deals.split(",").map(&:strip)).pluck(:id).sort)
end

Given('{string} is signed in for the deal activity search') do |first_name|
  sr_sign_in(cmb_user_named(first_name))
end

When('they search deal activities for {string}') do |query|
  sr_request(:get, search_deal_activities_path(query:))
end

Then('the search lists the step of the deal {string} but not the deal {string}') do |shown, hidden|
  expect(@sr_status).to eq(200)
  expect(@sr_body).to include("Term sheet #{shown}")
  expect(@sr_body).not_to include("Term sheet #{hidden}")
end

# ---- L12 ------------------------------------------------------------------------------------------

Given('the firm {string} has a deal {string} with the step {string}') do |firm, deal, step|
  cmb_deal(cmb_firm(firm), deal, step_title: step)
end

When('my firm creates a deal {string} cloned from the deal {string}') do |name, source|
  @cmb_deal, @cmb_deal_result = cmb_deal(@entity, name, clone_from: Deal.find_by!(name: source))
end

Then('the deal is refused with {string}') do |message|
  expect(@cmb_deal_result.success?).to be(false)
  expect(@cmb_deal.errors.full_messages).to include(message)
end

Then('no deal step {string} exists in my firm') do |title|
  expect(DealActivity.where(entity_id: @entity.id, title:)).not_to exist
end

Then('the deal {string} has the step {string}') do |deal, title|
  expect(DealActivity.where(deal: Deal.find_by!(name: deal), title:)).to exist
end

Given('my firm has a fund {string} with the fee formula {string}') do |fund, fee|
  cmb_fee_formula(cmb_fund(@entity, fund), fee)
end

Given('the firm {string} has a fund {string} with the fee formula {string}') do |firm, fund, fee|
  cmb_fee_formula(cmb_fund(cmb_firm(firm), fund), fee)
end

When('a capital call of the fund {string} selects the fee formula {string}') do |fund, fee|
  fund = Fund.find_by!(name: fund)
  @cmb_call = FactoryBot.build(:capital_call, fund:, entity: fund.entity, fee_formula_ids: [CallFee.find_by!(name: fee).id.to_s])
  @cmb_call.valid?
end

Then('the capital call is refused with {string}') do |message|
  expect(@cmb_call.errors.full_messages).to include(message)
end

Then('the capital call accepts the fee formulas') do
  expect(@cmb_call.errors[:fee_formula_ids]).to be_empty
end

Then('a capital call of the fund {string} storing the fee formula {string} does not apply it') do |fund, fee|
  fund = Fund.find_by!(name: fund)
  # A legacy row whose stored ids name another firm's fee: the lookup itself is scoped to the call's firm
  call = FactoryBot.build(:capital_call, fund:, entity: fund.entity, fee_formula_ids: [CallFee.find_by!(name: fee).id.to_s])
  expect(call.fee_formulas).to be_empty
end

Given('the formula generator is stubbed') do
  @cmb_generator_calls = 0
  calls = -> { @cmb_generator_calls += 1 }
  allow(FundFormulaGenerator).to receive(:call) do |*|
    calls.call
    "commitment_amount * 0.02"
  end
end

When('I ask the formula generator for {string}') do |description|
  sr_request(:get, generate_formula_fund_formulas_path(format: :turbo_stream, name: "Mgmt Fee", rule_type: "GenerateCustomField",
                                                       description:))
end

Then('the formula generator was called {int} time(s)') do |count|
  expect(@cmb_generator_calls).to eq(count)
end

When('they generate KPI mappings for the portfolio company {string}') do |name|
  sr_request(:post, generate_investor_kpi_mappings_path(investor_id: cmb_investor(name).id))
end

Then('the portfolio company {string} has no KPI mappings') do |name|
  expect(InvestorKpiMapping.where(investor: cmb_investor(name))).not_to exist
end

Then('the user may generate KPI mappings for the portfolio company {string}') do |name|
  mapping = InvestorKpiMapping.new(entity_id: @entity.id, investor: cmb_investor(name))
  expect(InvestorKpiMappingPolicy.new(@user.reload, mapping).generate?).to be(true)
end

Then('{string} may not generate KPI mappings for the portfolio company {string}') do |first_name, name|
  mapping = InvestorKpiMapping.new(entity_id: @entity.id, investor: cmb_investor(name))
  expect(InvestorKpiMappingPolicy.new(cmb_user_named(first_name), mapping).generate?).to be(false)
end

Given('my firm has the workflow template {string}') do |name|
  WorkflowTemplate.create!(entity: @entity, name:, workflowable_type: "InvestorKyc")
end

When('they open the new auto-assignment rule page of the template {string}') do |name|
  sr_request(:get, new_workflow_template_workflow_auto_assignment_rule_path(WorkflowTemplate.find_by!(name:)))
end

Then('a rule of the firm {string} for the template {string} is refused with {string}') do |firm, name, message|
  rule = WorkflowAutoAssignmentRule.new(entity: cmb_firm(firm), workflow_template: WorkflowTemplate.find_by!(name:),
                                        workflowable_type: "InvestorKyc", priority: 0)
  expect(rule).not_to be_valid
  expect(rule.errors.full_messages).to include(message)
end

Then('a rule of my firm for the template {string} saves') do |name|
  rule = WorkflowAutoAssignmentRule.new(entity: @entity, workflow_template: WorkflowTemplate.find_by!(name:),
                                        workflowable_type: "InvestorKyc", priority: 0)
  expect(rule.save).to be(true), rule.errors.full_messages.join(", ")
end

Given('the firm {string} has the portfolio report template {string}') do |firm, name|
  cmb_report_template(cmb_firm(firm), name)
end

Given('my firm has the portfolio report template {string}') do |name|
  cmb_report_template(@entity, name)
end

When('I generate a report for {string} with the template {string}') do |company, template|
  allow(PortfolioReportDraftJob).to receive(:perform_later)
  sr_request(:post, generate_reports_investor_path(cmb_investor(company)),
             portfolio_report_template_id: PortfolioReportTemplate.find_by!(name: template).id,
             start_date: "2026-01-01", end_date: "2026-03-31", kpi_period_type: "Quarter", kpi_tag: "Actual", n_periods: 4)
end

Then('no report draft exists for {string}') do |company|
  expect(PortfolioReportDraft.where(portfolio_company: cmb_investor(company))).not_to exist
end

Then('a report draft for {string} with the template {string} is refused') do |company, template|
  draft = cmb_report_draft(cmb_investor(company), PortfolioReportTemplate.find_by!(name: template))
  expect(draft).not_to be_valid
  expect(draft.errors[:portfolio_company]).to include("must be in this portfolio report's firm")
end

Then('a report draft for {string} with the template {string} is valid') do |company, template|
  draft = cmb_report_draft(cmb_investor(company), PortfolioReportTemplate.find_by!(name: template))
  expect(draft).to be_valid, draft.errors.full_messages.join(", ")
end

Given('my firm has the stakeholder firm {string}') do |name|
  cmb_stakeholder(@entity, name)
end

Given('the firm {string} has no link to my firm') do |name|
  cmb_firm(name)
end

Given('the firm search index finds {string}') do |names|
  hits = names.split(",").map { |name| Entity.find_by!(name: name.strip) }
  # Elasticsearch is bypassed in tests: the index answers with every named firm, linked or not, so the
  # scenario shows the controller's own restriction to the firm's linked stakeholders
  chain = double("EntityIndex query")
  allow(chain).to receive_messages(query: chain, objects: hits)
  allow(EntityIndex).to receive(:filter).and_return(chain)
end

When('I search firms for {string}') do |term|
  sr_request(:get, "/entities/search.json", term:)
end

Then('the firm search lists {string} but not {string}') do |shown, hidden|
  expect(@sr_status).to eq(200)
  names = JSON.parse(@sr_body).pluck("name")
  expect(names).to include(shown)
  expect(names).not_to include(hidden)
end
