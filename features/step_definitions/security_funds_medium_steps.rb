# frozen_string_literal: true

# Steps for features/security/security_review_2026_10_funds.feature (M8, M9, M10, M19, M20, M21, M23,
# M24, M26, N2, N3) and features/security/ci_widget_embeds.feature (L13).
# docs/security/security_review_2026_10.md — "Funds / KPI / portfolio — Medium and Low".
# Reused: entities, funds, users, roles, investor access and fund grants (access_rights_cache_steps.rb),
# "there is an account entry for the fund" and the allowed/denied assertions on @record
# (access_rights_models_steps.rb), "the fund {string} has a commitment" (fund_records_firm_policy_steps.rb)
# and "I log in with email {string}" (login.rb).

module SecurityFundsMediumHelpers
  # A docx every generator accepts, for template and plain documents alike
  SFM_DOCX = "public/sample_uploads/Purchase-Agreement-1.docx"

  def sfm_fund(name) = Fund.find_by!(name:)
  def sfm_entity(name) = Entity.find_by!(name:)
  def sfm_user(email) = User.find_by!(email:)

  # A document owned by `owner` in the owner's firm, uploaded by that firm's first user
  def sfm_document(owner:, name:, owner_tag: nil, template: false)
    doc = Document.new(entity_id: owner.entity_id, owner:, name:, owner_tag:, template:,
                       user: User.find_by(entity_id: owner.entity_id) || User.first)
    doc.file = File.open(SFM_DOCX, "rb")
    doc.save!
    doc
  end

  def sfm_documents
    @sfm_documents ||= {}
  end

  # Records the alerts the jobs broadcast, as [user_id, message]
  def sfm_capture_alerts
    @sfm_alerts = []
    allow(UserAlert).to receive(:new) do |**kwargs|
      @sfm_alerts << [kwargs[:user_id], kwargs[:message].to_s]
      double("UserAlert", broadcast: true)
    end
  end

  # The ratio maths is not under test: a stub keeps the run to its authorization and bookkeeping
  def sfm_stub_ratio_maths
    allow_any_instance_of(FundRatiosScenarioJob).to receive(:calc_fund_ratios).and_return(true)
    allow_any_instance_of(FundRatiosScenarioJob).to receive(:calc_portfolio_company_ratios).and_return(true)
  end

  def sfm_fund_ids(names) = names.split(",").map { |n| sfm_fund(n.strip).id }

  # A ratio run template of `entity`, built (not saved) so its validity can be asked
  def sfm_ratio_template(entity_name, fund_ids: [], anchor_fund: nil)
    entity = sfm_entity(entity_name)
    FundRatioRunTemplate.new(entity:, user: User.find_by!(entity_id: entity.id), name: "Template #{SecureRandom.hex(3)}",
                             fund_ids:, anchor_fund:, run_type: "cross-fund")
  end
end
World(SecurityFundsMediumHelpers)

# ---- Shared setup -------------------------------------------------------------------------------

Given('another firm {string} has a fund {string} and a company admin {string}') do |firm, fund_name, email|
  # Built by name so @entity / @fund from the Background stay the first firm's
  entity = FactoryBot.create(:entity, name: firm, entity_type: "Investment Fund")
  FactoryBot.create(:fund, entity:, name: fund_name)
  admin = FactoryBot.build(:user, entity:, email:, first_name: "Other", last_name: "Admin")
  admin.save!
  admin.add_role(:company_admin)
  admin.update!(curr_role: "company_admin")
  # Both firms get the KPI and portfolio features, so a refusal is the rule under test, never a flag
  flags = %i[enable_kpis enable_fund_portfolios]
  [entity, sfm_entity("Fund Entity")].each do |firm_entity|
    flags.each { |flag| firm_entity.permissions.set(flag) }
    firm_entity.save!
  end
end

Given('the fund {string} has a {string} named {string}') do |fund_name, owner_tag, name|
  sfm_documents[name] = sfm_document(owner: sfm_fund(fund_name), name:, owner_tag:, template: owner_tag != "Style")
end

Given('the fund {string} has a document {string}') do |fund_name, name|
  sfm_documents[name] = sfm_document(owner: sfm_fund(fund_name), name:)
end

Then('{string} was told {string}') do |email, text|
  user = sfm_user(email)
  messages = @sfm_alerts.select { |user_id, _| user_id == user.id }.map(&:last)
  expect(messages.join(" | ")).to include(text)
end

# ---- M8 -----------------------------------------------------------------------------------------

When('{string} runs cross-fund ratios on the funds {string}') do |email, fund_names|
  steps %(When "#{email}" runs cross-fund ratios on the funds "#{fund_names}" anchored on "Main Fund")
end

When('{string} runs cross-fund ratios on the funds {string} anchored on {string}') do |email, fund_names, anchor|
  sfm_capture_alerts
  sfm_stub_ratio_maths
  @sfm_runs_before = FundRatioRun.count
  # What funds#generate_fund_ratios queues (and a template trigger, which skips the controller check)
  FundRatiosScenarioJob.perform_now(sfm_fund(anchor).id, Time.zone.today, sfm_user(email).id,
                                    fund_ids: sfm_fund_ids(fund_names), type: "cross-fund")
end

Then('no fund ratio run was saved') do
  expect(FundRatioRun.count).to eq(@sfm_runs_before)
end

Then('a fund ratio run was saved for the funds {string}') do |fund_names|
  expect(FundRatioRun.all.map { |run| Array(run.fund_ids).map(&:to_i).sort }).to include(sfm_fund_ids(fund_names).sort)
end

Then('a ratio run template of {string} on the funds {string} is invalid') do |entity_name, fund_names|
  template = sfm_ratio_template(entity_name, fund_ids: sfm_fund_ids(fund_names))
  expect(template).not_to be_valid
  expect(template.errors[:fund_ids]).to be_present
end

Then('a ratio run template of {string} anchored on {string} is invalid') do |entity_name, fund_name|
  template = sfm_ratio_template(entity_name, anchor_fund: sfm_fund(fund_name))
  expect(template).not_to be_valid
  expect(template.errors[:anchor_fund]).to be_present
end

Then('a ratio run template of {string} on the funds {string} is valid') do |entity_name, fund_names|
  template = sfm_ratio_template(entity_name, fund_ids: sfm_fund_ids(fund_names))
  expect(template).to be_valid, template.errors.full_messages.join(", ")
end

Given('{string} has a stored ratio run template {string} on the funds {string}') do |entity_name, name, fund_names|
  template = sfm_ratio_template(entity_name, fund_ids: sfm_fund_ids(fund_names))
  template.name = name
  # A row stored before the M8 validation existed
  template.save!(validate: false)
end

When('{string} runs the ratio run templates {string} as a batch') do |email, names|
  sfm_capture_alerts
  sfm_stub_ratio_maths
  ids = names.split(",").map { |n| FundRatioRunTemplate.find_by!(name: n.strip).id }
  FundRatioRunTemplateBatchJob.perform_now(ids, Time.zone.today, sfm_user(email).id)
end

# ---- M9 -----------------------------------------------------------------------------------------

When('the commitment documents are generated with the template {string}') do |template_name|
  # Record what the generator would render, without rendering
  @sfm_rendered = []
  allow(CapitalCommitmentDocGenerator).to receive(:new) do |model, template, *_args, **_opts|
    @sfm_rendered << [model.id, template.id]
    double("CapitalCommitmentDocGenerator", generated_document: nil)
  end
  commitment = sfm_fund("Main Fund").capital_commitments.last
  job = CapitalCommitmentDocJob.new
  # What capital_commitments#generate_documentation queues, with the template id from the request
  job.perform(commitment.fund_id, commitment.id, sfm_user("admin@example.com").id, template_id: sfm_documents.fetch(template_name).id)
  # "the generation reports {string}" (H15, security_h8_h11_h14_h15_h19_steps.rb) reads @sec_job_errors
  @sfm_job_errors = @sec_job_errors = job.instance_variable_get(:@error_msg)
end

Then('no commitment document was rendered') do
  expect(@sfm_rendered).to be_empty
end

Given('{string} has an unverified KYC') do |investor_name|
  investor = Investor.find_by!(investor_name:)
  @sfm_kyc = FactoryBot.create(:investor_kyc, entity: investor.entity, investor:, kyc_type: "individual", verified: false)
end

When('the KYC documents are generated with the template {string}') do |template_name|
  job = KycDocGenJob.new
  # What investor_kycs#generate_docs queues
  job.perform(@sfm_kyc.id, [sfm_documents.fetch(template_name).id], Time.zone.today - 30, Time.zone.today,
              sfm_user("admin@example.com").id)
  # "the generation reports {string}" (H15, security_h8_h11_h14_h15_h19_steps.rb) reads @sec_job_errors
  @sfm_job_errors = @sec_job_errors = job.instance_variable_get(:@error_msg)
end

When('the KYC documents for no KYCs are generated for the entity {string} with the template {string}') do |entity_name, template_name|
  job = KycDocGenJob.new
  # What investor_kycs#generate_all_docs queues when the user's scoped search matched nothing
  job.perform([], [sfm_documents.fetch(template_name).id], Time.zone.today - 30, Time.zone.today,
              sfm_user("admin@example.com").id, entity_id: sfm_entity(entity_name).id)
  # "the generation reports {string}" (H15, security_h8_h11_h14_h15_h19_steps.rb) reads @sec_job_errors
  @sfm_job_errors = @sec_job_errors = job.instance_variable_get(:@error_msg)
end

Then('the generation does not report {string}') do |message|
  expect(Array(@sfm_job_errors).pluck(:msg)).not_to include(message)
end

# ---- M10 ----------------------------------------------------------------------------------------

When('I open the commitment report {string}') do |report|
  visit report_capital_commitment_path(sfm_fund("Main Fund").capital_commitments.last, report:)
end

When('I open the documents list with the template {string}') do |template|
  visit documents_path(template:)
end

When('I open the new access right form of the fund {string} with the form type {string}') do |fund_name, form_type|
  fund = sfm_fund(fund_name)
  visit new_access_right_path(access_right: { owner_id: fund.id, owner_type: "Fund", entity_id: fund.entity_id }, form_type:)
end

Then('the response is not found') do
  expect(page.status_code).to eq(404)
end

Then('the response is OK') do
  expect(page.status_code).to eq(200)
end

Then('the page shows {string}') do |text|
  expect(page).to have_content(text)
end

# ---- M19 ----------------------------------------------------------------------------------------

Given('{string} has a KPI report for the portfolio company {string} with a portco user {string}') do |entity_name, company, email|
  entity = sfm_entity(entity_name)
  # The portfolio company's own firm, with a user of its own (who uploads through the portco flow)
  company_entity = FactoryBot.create(:entity, name: company, entity_type: "Company")
  company_entity.permissions.set(:enable_kpis)
  company_entity.save!
  portco_user = FactoryBot.build(:user, entity: company_entity, email:, first_name: "Portco", last_name: "User")
  portco_user.save!
  portco_user.add_role(:employee)
  portfolio_company = FactoryBot.create(:investor, entity_id: entity.id, investor_entity_id: company_entity.id,
                                                   investor_name: company, category: "Portfolio Company")
  @record = KpiReport.create!(entity_id: entity.id, portfolio_company_id: portfolio_company.id, as_of: Time.zone.today,
                              tag_list: "Actual", user: sfm_user("admin@example.com"), enable_portco_upload: true)
end

Given('the record is the KPI report class') do
  @record = KpiReport
end

# ---- M20 ----------------------------------------------------------------------------------------

Given('{string} has a portfolio report template') do |entity_name|
  report = FactoryBot.create(:portfolio_report, entity: sfm_entity(entity_name), name: "Quarterly pack")
  @record = PortfolioReportTemplate.new(portfolio_report: report, name: "Board deck", output_format: "word")
end

Then('the portfolio report template with the style document {string} is invalid') do |doc_name|
  @record.style_document = sfm_documents.fetch(doc_name)
  expect(@record).not_to be_valid
  expect(@record.errors[:style_document]).to be_present
end

Then('the portfolio report template with the style document {string} is valid') do |doc_name|
  @record.style_document = sfm_documents.fetch(doc_name)
  expect(@record).to be_valid, @record.errors.full_messages.join(", ")
end

# ---- M21 ----------------------------------------------------------------------------------------

Given('{string} has an exchange rate {string} to {string}') do |entity_name, from, to|
  @record = ExchangeRate.new(entity_id: sfm_entity(entity_name).id, from:, to:, rate: 80, as_of: Time.zone.today)
end

Given('{string} has an exchange rate {string} to {string} for the fund {string}') do |entity_name, from, to, fund_name|
  @record = ExchangeRate.new(entity_id: sfm_entity(entity_name).id, from:, to:, rate: 80, as_of: Time.zone.today,
                             owner: sfm_fund(fund_name))
end

# ---- M23 ----------------------------------------------------------------------------------------

Given('there is a fund-level account entry for the fund') do
  # A fund-level entry: the investor association exists but is empty
  @record = FactoryBot.create(:account_entry, fund: @fund, entity: @fund.entity, investor: nil)
end

# ---- M24 ----------------------------------------------------------------------------------------

Given('the fund {string} has a formula {string}') do |fund_name, name|
  fund = sfm_fund(fund_name)
  FactoryBot.create(:fund_formula, fund:, entity_id: fund.entity_id, name:)
end

When('the formula {string} is moved to the fund {string}') do |name, fund_name|
  formula = FundFormula.find_by!(name:)
  # What a PATCH carrying another fund_id would assign
  formula.update(fund_id: sfm_fund(fund_name).id)
end

Then('the formula {string} is on the fund {string}') do |name, fund_name|
  expect(FundFormula.find_by!(name:).reload.fund_id).to eq(sfm_fund(fund_name).id)
end

Then('a new formula of {string} on the fund {string} is invalid') do |entity_name, fund_name|
  formula = FactoryBot.build(:fund_formula, entity_id: sfm_entity(entity_name).id, fund: sfm_fund(fund_name))
  expect(formula).not_to be_valid
  expect(formula.errors[:fund]).to be_present
end

Then('a new formula of {string} on the fund {string} is valid') do |entity_name, fund_name|
  formula = FactoryBot.build(:fund_formula, entity_id: sfm_entity(entity_name).id, fund: sfm_fund(fund_name))
  expect(formula).to be_valid, formula.errors.full_messages.join(", ")
end

# ---- M26 ----------------------------------------------------------------------------------------

Given('there is an aggregate portfolio investment for the fund') do
  # Built, not saved: the policy reads only its fund and firm
  @record = AggregatePortfolioInvestment.new(fund: @fund, entity_id: @fund.entity_id)
end

Given('there is a signer row on the document {string}') do |doc_name|
  document = sfm_documents.fetch(doc_name)
  @record = ESignature.new(entity_id: document.entity_id, document:, email: "signer@example.com", position: 1)
end

# ---- N2 -----------------------------------------------------------------------------------------

module SecurityFundsMediumHelpers
  # Stands in for the commitment: records the name each roll-up helper is called with
  class RollupProbe
    attr_reader :names

    def initialize = @names = []

    %i[quarterly year_to_date since_inception].each do |helper|
      define_method(helper) do |name, *_rest|
        @names << name
        0
      end
    end
  end

  # The operation's roll-up builder, without running an allocation
  def sfm_rollup_formulas(name, helper: :quarterly)
    operation = AccountEntryAllocation::CreateAccountEntry.allocate
    operation.instance_variable_set(:@variable_name, "carry")
    capital_commitment = RollupProbe.new
    carry = 5
    bdg = binding
    evaluated, stored = operation.rollup_formulas(helper, FundFormula.new(name:), bdg)
    [evaluated, stored, bdg, capital_commitment, carry]
  end
end

Then('the roll-up formulas for the formula name {string} pass that exact name') do |name|
  evaluated, stored, bdg, probe, carry = sfm_rollup_formulas(name)
  # The evaluated text never holds the name itself
  expect(evaluated).not_to include(name)
  expect(eval(evaluated, bdg)).to eq(carry) # rubocop:disable Security/Eval
  # The stored text is a safe literal: re-evaluated later, it passes the same name
  expect(eval(stored, bdg)).to eq(carry) # rubocop:disable Security/Eval
  expect(probe.names).to eq([name, name])
end

Then('the stored roll-up text for the formula name {string} is {string}') do |name, text|
  _evaluated, stored, = sfm_rollup_formulas(name)
  expect(stored).to eq(text)
end

# ---- N3 -----------------------------------------------------------------------------------------

Given('the fund {string} has a formula {string} described as {string}') do |fund_name, name, description|
  fund = sfm_fund(fund_name)
  formula = FactoryBot.create(:fund_formula, fund:, entity_id: fund.entity_id, name:)
  # ai_description is what makes a formula an example
  formula.update_columns(ai_description: description, description:)
end

When('{string} asks the formula generator for {string}') do |email, name|
  @sfm_prompt = nil
  allow(LlmService).to receive(:chat) do |prompt:, **|
    @sfm_prompt = prompt
    "1 + 1"
  end
  FundFormulaGenerator.call(name:, rule_type: "GenerateAccountEntry", entry_type: "Test", description: "A test formula",
                            entity_id: sfm_user(email).entity_id)
end

Then('the generator prompt includes {string}') do |text|
  expect(@sfm_prompt).to include(text)
end

Then('the generator prompt does not include {string}') do |text|
  expect(@sfm_prompt).not_to include(text)
end

# ---- L13 (features/security/ci_widget_embeds.feature) -------------------------------------------

Given('there is a widget firm {string}') do |name|
  @sfm_widget_entity = FactoryBot.create(:entity, name:, entity_type: "Investment Fund")
end

module SecurityFundsMediumHelpers
  # Built, not saved: validity and rendering need no row (a stored legacy value renders the same way)
  def sfm_widget(embed_script: nil)
    CiWidget.new(title: "Intro video", entity: @sfm_widget_entity, owner: @sfm_widget_entity, embed_script:)
  end
end

Then('the embed {string} is accepted') do |code|
  widget = sfm_widget(embed_script: code)
  expect(widget).to be_valid, widget.errors.full_messages.join(", ")
end

Then('the embed {string} is refused') do |code|
  widget = sfm_widget(embed_script: code)
  expect(widget).not_to be_valid
  expect(widget.errors[:embed_script]).to be_present
end

When('a widget stored with the embed {string} is shown') do |code|
  @sfm_html = ApplicationController.helpers.ci_widget_embed(sfm_widget(embed_script: code)).to_s
end

When('a widget with the text {string} is shown') do |details|
  @sfm_html = ApplicationController.helpers.ci_widget_rich_text(details).to_s
end

Then('nothing is rendered for the embed') do
  expect(@sfm_html).to be_blank
end

Then('the page gets a sandboxed player for {string}') do |src|
  fragment = Nokogiri::HTML5.fragment(@sfm_html)
  iframes = fragment.css("iframe")
  expect(iframes.size).to eq(1)
  expect(iframes.first["src"]).to eq(src)
  expect(iframes.first["sandbox"]).to be_present
  expect(iframes.first["loading"]).to eq("lazy")
end

Then('the rendered HTML does not contain {string}') do |text|
  expect(@sfm_html).not_to include(text)
end

Then('the rendered HTML contains {string}') do |text|
  expect(@sfm_html).to include(text)
end
