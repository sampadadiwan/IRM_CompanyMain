# Step definitions shared by access_rights_fund_models.feature
# and access_rights_core_models.feature.
#
# Conventions:
#   @record  - the most recently created fund-child or core record under test
#   @fund    - the current fund (may be overwritten by later fund creation steps)
#   @funds   - hash of fund_name => Fund for named lookups
#   @io      - the current InvestmentOpportunity

# ---------------------------------------------------------------------------
# Fund flag setters
# ---------------------------------------------------------------------------

# Enables the show_fund_ratios flag so investors can see FundRatio records.
When('the fund has show_fund_ratios enabled') do
  @fund.update!(show_fund_ratios: true)
end

# Disables the show_fund_units flag; used to verify that investors are blocked.
When('the fund has show_fund_units disabled') do
  @fund.update!(show_fund_units: false)
end

# Enables the show_portfolios flag so investors can see PortfolioInvestment records.
When('the fund has show_portfolios enabled') do
  @fund.update!(show_portfolios: true)
end

# ---------------------------------------------------------------------------
# Fund child record creation (all set @record used by generic assertions below)
# ---------------------------------------------------------------------------

# CapitalCall — belongs directly to fund; no sub-dependencies needed.
# Renamed to avoid conflict with features/ai/support_agents/call_notice_agent_steps.rb.
Given('there is a capital call record for the fund') do
  @record = FactoryBot.create(:capital_call, fund: @fund, entity: @fund.entity)
end

# CapitalDistribution — belongs directly to fund.
Given('there is a capital distribution for the fund') do
  @record = FactoryBot.create(:capital_distribution, fund: @fund, entity: @fund.entity)
end

# FundReport — no FactoryBot factory exists; build it directly from attributes.
Given('there is a fund report for the fund') do
  @record = FundReport.create!(fund: @fund, entity: @fund.entity, name: 'Test Report')
end

# CapitalRemittance — requires a CapitalCommitment (monetize lambda calls capital_commitment.folio_currency),
# a CapitalCall, folio_id (presence: true, unique per capital_call), and folio_committed_amount_cents > 0.
Given('there is a capital remittance for the fund') do
  investor    = @investor || @fund.investors.first
  commitment  = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor: investor)
  capital_call = FactoryBot.create(:capital_call, fund: @fund, entity: @fund.entity)
  @record = FactoryBot.create(:capital_remittance,
    fund:                         @fund,
    entity:                       @fund.entity,
    capital_call:                 capital_call,
    capital_commitment:           commitment,
    investor:                     investor,
    folio_id:                     SecureRandom.hex(8),
    folio_committed_amount_cents: 10_000_000)
end

# CapitalRemittancePayment — depends on a fully valid CapitalRemittance (see above).
Given('there is a capital remittance payment for the fund') do
  investor     = @investor || @fund.investors.first
  commitment   = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor: investor)
  capital_call = FactoryBot.create(:capital_call, fund: @fund, entity: @fund.entity)
  capital_remittance = FactoryBot.create(:capital_remittance,
    fund:                         @fund,
    entity:                       @fund.entity,
    capital_call:                 capital_call,
    capital_commitment:           commitment,
    investor:                     investor,
    folio_id:                     SecureRandom.hex(8),
    folio_committed_amount_cents: 10_000_000)
  @record = FactoryBot.create(:capital_remittance_payment,
    fund:               @fund,
    entity:             @fund.entity,
    capital_remittance: capital_remittance)
end

# CapitalDistributionPayment — two tricky constraints:
# 1. before_validation :ensure_commitment overwrites capital_commitment via
#    fund.capital_commitments.where(investor_id:, folio_id:) — so folio_id must match the commitment.
# 2. CapitalDistribution has after_create_commit :generate_distribution_payments (default true)
#    which runs inline in test (queue_adapter :inline) and auto-creates a payment for every
#    fund commitment, consuming the folio_id before we can.  Pass generate_payments: false to
#    suppress the job so our manual payment is the first and only one for this folio_id.
Given('there is a capital distribution payment for the fund') do
  investor    = @investor || @fund.investors.first
  folio_id    = "cdp-#{SecureRandom.hex(6)}"
  # Commitment with same folio_id so ensure_commitment callback resolves it on the payment
  FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity,
    investor: investor, folio_id: folio_id)
  # generate_payments:false prevents inline CapitalDistributionJob from consuming our folio_id
  capital_distribution = FactoryBot.create(:capital_distribution, fund: @fund, entity: @fund.entity,
    generate_payments: false)
  @record = FactoryBot.create(:capital_distribution_payment,
    fund:                 @fund,
    entity:               @fund.entity,
    capital_distribution: capital_distribution,
    investor:             investor,
    folio_id:             folio_id)
end

# AccountEntry — include investor so permissioned_investor? can check investor_entity_id.
# Without investor, the entity-scope check record.investor.investor_entity_id crashes on nil.
Given('there is an account entry for the fund') do
  @record = FactoryBot.create(:account_entry, fund: @fund, entity: @fund.entity,
    investor: @investor || @fund.investors.first)
end

# CommitmentAdjustment — requires a CapitalCommitment and as_of date.
# validate_as_of checks as_of >= capital_commitment.commitment_date; nil as_of crashes the method.
# folio_amount_cents defaults to 0.0 (schema default) which passes presence: true.
Given('there is a commitment adjustment for the fund') do
  investor   = @investor || @fund.investors.first
  commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor: investor)
  @record = FactoryBot.create(:commitment_adjustment,
    fund:               @fund,
    entity:             @fund.entity,
    capital_commitment: commitment,
    adjustment_type:    'Top Up',
    as_of:              commitment.commitment_date)
end

# PortfolioScenario — no factory; build directly.
# user is the currently set @target_user, or fall back to any fund employee.
Given('there is a portfolio scenario for the fund') do
  user    = @target_user || @fund.entity.employees.first
  @record = PortfolioScenario.create!(
    fund:   @fund,
    entity: @fund.entity,
    user:   user,
    name:   'Test Scenario')
end

# ExcusedInvestor — the factory has a stale folio_id attribute that no longer exists on the model.
# Create directly: schema requires capital_commitment_id, entity_id, fund_id (all null: false).
Given('there is an excused investor for the fund') do
  investor   = @investor || @fund.investors.first
  commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor: investor)
  @record    = ExcusedInvestor.new(fund: @fund, entity: @fund.entity, capital_commitment: commitment)
  @record.save!(validate: false)
end

# FundRatio — belongs to fund and entity.
Given('there is a fund ratio for the fund') do
  @record = FactoryBot.create(:fund_ratio, fund: @fund, entity: @fund.entity)
end

# FundUnit — schema has capital_commitment_id, entity_id, investor_id (all null: false).
# Factory defaults all three to nil; must supply them explicitly.
Given('there is a fund unit for the fund') do
  investor   = @investor || @fund.investors.first
  commitment = FactoryBot.create(:capital_commitment, fund: @fund, entity: @fund.entity, investor: investor)
  @record = FactoryBot.create(:fund_unit,
    fund:               @fund,
    entity:             @fund.entity,
    investor:           investor,
    capital_commitment: commitment)
end

# PortfolioInvestment — renamed to avoid conflict with validation_rules.rb step of same name.
# Bypasses FactoryBot and complex validations; creates directly with save!(validate: false).
# InvestmentInstrument.belongs_to :portfolio_company has no optional: true, so portfolio_company
# must be created FIRST and passed to the instrument factory.
Given('there is a portfolio investment record for the fund') do
  # portfolio_company must exist before instrument (belongs_to :portfolio_company without optional:true)
  pc_entity = Entity.create!(
    name:          "PC Entity #{SecureRandom.hex(4)}",
    entity_type:   'Investor',
    primary_email: "pc#{SecureRandom.hex(4)}@example.com")
  portfolio_company = Investor.new(
    entity:          @fund.entity,
    investor_entity: pc_entity,
    investor_name:   pc_entity.name,
    category:        'Portfolio Company')
  portfolio_company.save!(validate: false)
  instrument = FactoryBot.create(:investment_instrument,
    entity:            @fund.entity,
    portfolio_company: portfolio_company)
  aggregate = AggregatePortfolioInvestment.new(
    fund:                  @fund,
    entity:                @fund.entity,
    portfolio_company:     portfolio_company,
    investment_instrument: instrument)
  aggregate.save!(validate: false)
  @record = PortfolioInvestment.new(
    fund:                           @fund,
    entity:                         @fund.entity,
    investment_instrument:          instrument,
    portfolio_company:              portfolio_company,
    aggregate_portfolio_investment: aggregate,
    amount_cents:                   10_000_000,
    investment_date:                Date.today - 1.month,
    quantity:                       100,
    sub_category:                   'Equity',
    category:                       'Unlisted',
    excused_folio_ids:              [])
  @record.save!(validate: false)
end

# ---------------------------------------------------------------------------
# InvestmentOpportunity — model_with_access_rights = self (not a fund)
# ---------------------------------------------------------------------------

# Creates an InvestmentOpportunity in the fund entity; stores in @io and @record.
Given('there is an investment opportunity') do
  @io = FactoryBot.create(:investment_opportunity, entity: @fund.entity)
  @record = @io
end

# Grants an employee AR directly on the InvestmentOpportunity (not the Fund).
When('I grant {string} access to the investment opportunity for user {string}') do |perms, email|
  user = User.find_by!(email: email)
  ar   = AccessRight.new(owner: @io, entity: @io.entity, user_id: user.id)
  perms.split(',').each { |p| ar.permissions.set(p.strip.to_sym) }
  ar.save!
end

# Grants an investor AR directly on the InvestmentOpportunity.
When('I grant {string} access to the investment opportunity for investor {string}') do |perms, investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  ar       = AccessRight.new(owner: @io, entity: @io.entity, access_to_investor_id: investor.id)
  perms.split(',').each { |p| ar.permissions.set(p.strip.to_sym) }
  ar.save!
end

# ---------------------------------------------------------------------------
# ExpressionOfInterest — model_with_access_rights = investment_opportunity
# ---------------------------------------------------------------------------

# Creates an ExpressionOfInterest linked to @io; stores in @record.
# Uses @investor if set; otherwise picks the first investor in the entity.
Given('there is an expression of interest for the investment opportunity') do
  investor = @investor || @io.entity.investors.first
  eoi_entity = investor.investor_entity
  # eoi_entity_id is not null; user must belong to the eoi_entity
  eoi_user = eoi_entity.employees.first || User.find_by(email: 'investor@example.com') ||
             FactoryBot.create(:user, entity: eoi_entity)
  # amount must be strictly > investment_opportunity.min_ticket_size (factory default: 1,000,000 rupees).
  # 110_000_000 paise = 1,100,000 rupees, which clears the minimum and stays below fund_raise_amount.
  @record = ExpressionOfInterest.create!(
    investment_opportunity: @io,
    entity:                 @io.entity,
    investor:               investor,
    eoi_entity:             eoi_entity,
    user:                   eoi_user,
    amount_cents:           110_000_000,
    approved:               false,
    verified:               false)
end

# ---------------------------------------------------------------------------
# Core model record creation (Investor, InvestorKyc, Document, Folder, Valuation, Task)
# ---------------------------------------------------------------------------

# Creates an InvestorKyc for the named investor; stores in @kyc_record.
Given('there is a kyc for investor {string}') do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name)
  @kyc_record = FactoryBot.create(:investor_kyc, entity: investor.entity, investor: investor)
end

# Creates a Folder in the named entity; stores in @folder_record.
Given('there is a folder {string} for the entity {string}') do |kv, entity_kv|
  name   = kv.split('=').last
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  @folder_record = Folder.create!(name: name, entity: entity)
end

# Creates a system Folder (folder_type: :system) that cannot be updated per FolderPolicy.
Given('there is a system folder {string} for the entity {string}') do |kv, entity_kv|
  name   = kv.split('=').last
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  # system? is derived from the folder_type enum; FolderPolicy.update? requires !system?
  @folder_record = Folder.create!(name: name, entity: entity, folder_type: :system)
end

# Creates a Document inside the named folder; stores in @doc_record.
# folder_name may arrive as "name=Reports" (key=value) — extract the value portion.
Given('there is a document in the folder {string}') do |folder_name|
  name   = folder_name.include?('=') ? folder_name.split('=').last : folder_name
  folder = Folder.find_by!(name: name)
  user   = folder.entity.employees.first
  @doc_record = Document.create!(
    name:   'Test Document',
    text:   'Sample text',
    entity: folder.entity,
    folder: folder,
    user:   user,
    file:   File.new('public/img/whatsappQR.png', 'r'))
end

# Creates a Document with public_visibility=true; visible regardless of entity.
# Same key=value parsing for folder_name.
Given('there is a public document in the folder {string}') do |folder_name|
  name   = folder_name.include?('=') ? folder_name.split('=').last : folder_name
  folder = Folder.find_by!(name: name)
  user   = folder.entity.employees.first
  @doc_record = Document.create!(
    name:              'Public Document',
    text:              'Public sample text',
    entity:            folder.entity,
    folder:            folder,
    user:              user,
    public_visibility: true,
    file:              File.new('public/img/whatsappQR.png', 'r'))
end

# Creates a Valuation owned by the most recently created fund (@fund).
# Valuation.belongs_to :investment_instrument is not optional (migration comment removed it);
# bypass with save!(validate: false) since the policy test only needs a persisted record.
Given('there is a valuation for the fund') do
  # currency is a computed method (no DB column); owner.currency provides it at runtime
  @valuation_record = Valuation.new(
    owner:                  @fund,
    entity:                 @fund.entity,
    category:               'Unlisted',
    sub_category:           'Equity',
    valuation_date:         Date.today - 1.month,
    valuation_cents:        100_000_000,
    per_share_value_cents:  100_000)
  @valuation_record.save!(validate: false)
end

# Creates a Task whose for_entity is the named entity and assigns it to the given user.
Given('there is a task for the entity {string} assigned to {string}') do |entity_kv, email|
  entity    = Entity.find_by!(name: entity_kv.split('=').last)
  user      = User.find_by!(email: email)
  # for_entity_id is checked in TaskPolicy.create? for non-employee users
  @task_record = Task.create!(
    details:     'Test task',
    entity:      entity,
    for_entity:  entity,
    user:        user,
    assigned_to: user,
    for_support: false,
    completed:   false)
end

# ---------------------------------------------------------------------------
# Generic policy assertions — @record (@fund child models)
# ---------------------------------------------------------------------------

# Asserts that the user is ALLOWED the named action(s) on @record.
Then('the user {string} should be allowed {string} on the record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on #{@record.class.name} but was denied"
  end
end

# Asserts that the user is DENIED the named action(s) on @record.
Then('the user {string} should be denied {string} on the record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on #{@record.class.name} but was allowed"
  end
end

# ---------------------------------------------------------------------------
# Core model policy assertions — typed record variables
# ---------------------------------------------------------------------------

# Asserts allowed on @investor (last investor created via the standard step).
Then('the user {string} should be allowed {string} on the investor record') do |email, actions|
  user = User.find_by!(email: email)
  # @investor is set by the 'there is an investor' step in access_rights_cache_steps.rb
  actions.split(',').each do |action|
    result = Pundit.policy(user, @investor).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on investor #{@investor.investor_name} but was denied"
  end
end

# Asserts denied on @investor.
Then('the user {string} should be denied {string} on the investor record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @investor).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on investor #{@investor.investor_name} but was allowed"
  end
end

# Asserts allowed on @kyc_record.
Then('the user {string} should be allowed {string} on the kyc record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @kyc_record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on InvestorKyc but was denied"
  end
end

# Asserts denied on @kyc_record.
Then('the user {string} should be denied {string} on the kyc record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @kyc_record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on InvestorKyc but was allowed"
  end
end

# Asserts allowed on @doc_record.
Then('the user {string} should be allowed {string} on the document record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @doc_record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on Document but was denied"
  end
end

# Asserts denied on @doc_record.
Then('the user {string} should be denied {string} on the document record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @doc_record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on Document but was allowed"
  end
end

# Asserts allowed on @folder_record.
Then('the user {string} should be allowed {string} on the folder record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @folder_record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on Folder but was denied"
  end
end

# Asserts denied on @folder_record.
Then('the user {string} should be denied {string} on the folder record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @folder_record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on Folder but was allowed"
  end
end

# Asserts allowed on @valuation_record.
Then('the user {string} should be allowed {string} on the valuation record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @valuation_record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on Valuation but was denied"
  end
end

# Asserts denied on @valuation_record.
Then('the user {string} should be denied {string} on the valuation record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @valuation_record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on Valuation but was allowed"
  end
end

# Asserts allowed on @task_record.
Then('the user {string} should be allowed {string} on the task record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @task_record).send("#{action.strip}?")
    expect(result).to be_truthy,
      "expected #{email} to be allowed #{action} on Task but was denied"
  end
end

# Asserts denied on @task_record.
Then('the user {string} should be denied {string} on the task record') do |email, actions|
  user = User.find_by!(email: email)
  actions.split(',').each do |action|
    result = Pundit.policy(user, @task_record).send("#{action.strip}?")
    expect(result).to be_falsey,
      "expected #{email} to be denied #{action} on Task but was allowed"
  end
end
