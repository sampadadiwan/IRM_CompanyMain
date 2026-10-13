# Step definitions for the Validation Rule Engine feature.
# Reuses existing steps for user/entity/fund/investor/valuation/portfolio setup.
# Adds only the steps specific to rule evaluation and override management.

# ── Setup ─────────────────────────────────────────────────────────────────────

Given('the default validation rules are seeded') do
  ValidationRulesSeed.seed!
end

# Creates enabled=true overrides for all global default rules for @entity.
# Needed only for rules whose global enabled flag is false; rules with enabled=true fire without this step.
Given('the entity has opted in to all validation rules') do
  ValidationRulesSeed.enable_for_entity!(@entity)
end

# Opts @entity out of all global default rules by creating enabled=false overrides.
# Suppresses all rule firing regardless of global defaults — use this to test the
# "client wants the engine fully off" path.
Given('the entity has opted out of all validation rules') do
  ValidationRulesSeed.disable_for_entity!(@entity)
end

# Creates a portfolio investment linking the most recent portfolio company to @fund.
# Uses PortfolioInvestmentCreate so the aggregate is set up correctly.
# For cross-currency instruments, a bootstrap exchange rate dated 2020-01-01 is created
# so the service can proceed; the allocation run FX rule check (date-windowed) won't find it.
Given('there is a portfolio investment for the fund') do
  @portfolio_company    ||= @entity.investors.portfolio_companies.last
  @investment_instrument ||= @portfolio_company.investment_instruments.last

  # Provide a bootstrap exchange rate when the instrument currency differs from the fund's,
  # so PortfolioInvestmentCreate can pass its currency validation.
  if @investment_instrument.currency.present? && @investment_instrument.currency != @fund.currency
    ExchangeRate.find_or_create_by!(
      entity:  @entity,
      from:    @investment_instrument.currency,
      to:      @fund.currency,
      as_of:   Date.parse("2020-01-01")
    ) { |er| er.rate = 85.0 }
  end

  pi = FactoryBot.build(
    :portfolio_investment,
    entity:                @entity,
    fund:                  @fund,
    portfolio_company:     @portfolio_company,
    investment_instrument: @investment_instrument,
    quantity:              100,
    investment_date:       Date.parse("2020-01-01")
  )
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "Failed to create portfolio investment: #{pi.errors.full_messages}" if result.failure?
  @portfolio_investment = pi
end

# Creates a buy PI with investment_date one day after the 2026-06-30 end_date used in scenarios.
# Confirms the rule ignores companies whose first investment hasn't happened yet as of the reporting date.
Given('there is a portfolio investment for the fund dated after the end date') do
  @portfolio_company     ||= @entity.investors.portfolio_companies.last
  @investment_instrument ||= @portfolio_company.investment_instruments.last

  pi = FactoryBot.build(
    :portfolio_investment,
    entity:                @entity,
    fund:                  @fund,
    portfolio_company:     @portfolio_company,
    investment_instrument: @investment_instrument,
    quantity:              100,
    investment_date:       Date.parse("2026-07-01")
  )
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "Failed to create portfolio investment: #{pi.errors.full_messages}" if result.failure?
  @portfolio_investment = pi
end

# Creates a buy (qty=100, 2020-01-01) and a matching sell (qty=-100, 2022-01-01) so
# SUM(quantity) = 0 for the company as of any 2026 end_date.
# The sell is inserted directly to avoid attribution-job complexity — the rule only needs
# the quantity column for its HAVING SUM(quantity) > 0 check.
Given('there is a fully exited portfolio investment for the fund') do
  @portfolio_company     ||= @entity.investors.portfolio_companies.last
  @investment_instrument ||= @portfolio_company.investment_instruments.last

  buy_pi = FactoryBot.build(
    :portfolio_investment,
    entity:                @entity,
    fund:                  @fund,
    portfolio_company:     @portfolio_company,
    investment_instrument: @investment_instrument,
    quantity:              100,
    investment_date:       Date.parse("2020-01-01")
  )
  result = PortfolioInvestmentCreate.call(portfolio_investment: buy_pi)
  raise "Failed to create buy: #{buy_pi.errors.full_messages}" if result.failure?

  sell_pi = PortfolioInvestment.new(
    entity:                         @entity,
    fund:                           @fund,
    portfolio_company:              @portfolio_company,
    investment_instrument:          @investment_instrument,
    aggregate_portfolio_investment: buy_pi.aggregate_portfolio_investment,
    quantity:                       -100,
    investment_date:                Date.parse("2022-01-01"),
    ex_expenses_base_amount_cents:  0,
    excused_folio_ids:              []
  )
  sell_pi.save(validate: false)
  raise "Failed to save sell portfolio investment" unless sell_pi.persisted?
end

Given('there is an exchange rate {string} for the entity') do |args|
  attrs = args.split(";").map { |p| p.split("=") }.to_h
  ExchangeRate.create!(
    entity:  @entity,
    from:    attrs["from"],
    to:      attrs["to"],
    as_of:   Date.parse(attrs["as_of"]),
    rate:    attrs.fetch("rate", "85.0").to_d
  )
end

Given('there is an account entry {string} for the fund') do |args|
  attrs = args.split(";").map { |p| p.split("=") }.to_h
  AccountEntry.create!(
    entity:         @entity,
    fund:           @fund,
    name:           attrs["name"],
    reporting_date: Date.parse(attrs["reporting_date"]),
    entry_type:     attrs.fetch("entry_type", "Debit"),
    amount_cents:   attrs.fetch("amount_cents", 0).to_i
  )
end

# Creates a ValidationRuleOverride for the named global default rule.
# args format: "enabled=false" | "severity_override=blocker" |
#              "param_overrides=pct_threshold:20" | "message_override=Some text"
Given('there is a validation rule override for {string} with {string}') do |rule_name, args|
  rule = ValidationRule.find_by!(name: rule_name, entity_id: nil, is_default: true)
  attrs = args.split(";").map { |p| p.split("=", 2) }.to_h

  param_overrides = {}
  if attrs["param_overrides"]
    attrs["param_overrides"].split(",").each do |pair|
      k, v = pair.split(":")
      # "n_days:" — a field left blank on the override form
      param_overrides[k.strip] = v.to_s.strip
    end
  end

  override = ValidationRuleOverride.find_or_initialize_by(
    validation_rule: rule,
    entity:          @entity
  )
  override.enabled          = attrs.fetch("enabled", "true") != "false"
  override.severity_override = attrs["severity_override"].presence
  override.message_override  = attrs["message_override"].presence
  override.param_overrides   = param_overrides
  override.save!
end

# Creates a persisted CapitalCall for @fund. args is a JSON-ish hash of close_percentages,
# e.g. "{'First Close':'100'}".
Given('there is a capital call {string} for the fund') do |args|
  closes = JSON.parse(args.gsub("'", '"'))

  @capital_call = FactoryBot.create(:capital_call,
    entity:            @entity,
    fund:              @fund,
    close_percentages: closes,
    fund_closes:       closes.keys
  )
end

# ── CapitalRemittance setup helpers ──────────────────────────────────────────

# Creates a minimal CapitalRemittance (no generated document) and stores it as @capital_remittance.
Given('there is a capital remittance without a generated notice for the capital call') do
  investor_entity = FactoryBot.create(:entity)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity)
  @capital_remittance = create_rule_test_remittance(investor)
end

# Creates a CapitalRemittance with a generated-but-unapproved Document and stores it as @capital_remittance.
Given('there is a capital remittance with an unapproved generated notice for the capital call') do
  investor_entity = FactoryBot.create(:entity)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity)
  @capital_remittance = create_rule_test_remittance(investor)

  folder = FactoryBot.create(:folder, entity: @entity)
  FactoryBot.create(:document,
    entity:    @entity,
    user:      @user,
    folder:    folder,
    owner:     @capital_remittance,
    owner_tag: "Generated",
    approved:  false
  )
end

# Creates a CapitalRemittance with a generated AND approved Document and stores it as @capital_remittance.
Given('there is a capital remittance with an approved generated notice for the capital call') do
  investor_entity = FactoryBot.create(:entity)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity)
  @capital_remittance = create_rule_test_remittance(investor)

  folder = FactoryBot.create(:folder, entity: @entity)
  FactoryBot.create(:document,
    entity:    @entity,
    user:      @user,
    folder:    folder,
    owner:     @capital_remittance,
    owner_tag: "Generated",
    approved:  true
  )
end

# ── Rule evaluation (backend, no browser) ────────────────────────────────────

# Evaluates rules for a temporary (unsaved) Valuation built from key=value args.
When('the validation rules are evaluated for a Valuation with {string}') do |args|
  attrs = args.split(";").map { |p| p.split("=", 2) }.to_h

  @portfolio_company    ||= @entity.investors.portfolio_companies.last
  @investment_instrument ||= @portfolio_company&.investment_instruments&.last ||
                              FactoryBot.create(:investment_instrument, entity: @entity,
                                                portfolio_company: @portfolio_company)

  record = Valuation.new(
    entity:                @entity,
    owner:                 @portfolio_company,
    investment_instrument: @investment_instrument,
    valuation_date:        attrs["valuation_date"].present? ? Date.parse(attrs["valuation_date"]) : nil,
    per_share_value_cents: attrs["per_share_value_cents"].to_i
  )

  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: record, entity: @entity)
  end
end

# Evaluates rules for a temporary AllocationRun.
When('the validation rules are evaluated for an AllocationRun with {string}') do |args|
  attrs = args.split(";").map { |p| p.split("=", 2) }.to_h
  @fund ||= @entity.funds.last

  record = AllocationRun.new(
    entity:     @entity,
    fund:       @fund,
    start_date: attrs["start_date"].present? ? Date.parse(attrs["start_date"]) : nil,
    end_date:   attrs["end_date"].present?   ? Date.parse(attrs["end_date"])   : nil,
    locked:     attrs["locked"] == "true",
    user:       @user
  )

  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: record, entity: @entity)
  end
end

# Evaluates rules for a temporary FundRatio.
When('the validation rules are evaluated for a FundRatio with {string}') do |args|
  attrs = args.split(";").map { |p| p.split("=", 2) }.to_h
  @fund ||= @entity.funds.last

  record = FundRatio.new(
    entity:   @entity,
    fund:     @fund,
    end_date: attrs["end_date"].present? ? Date.parse(attrs["end_date"]) : nil,
    value:    attrs["value"].to_d
  )

  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: record, entity: @entity)
  end
end

# Evaluates rules for a persisted CapitalCall record (@capital_call set by a prior step).
# Unlike the other model steps (which build unsaved records), CapitalCall rules rely on
# DB-level associations (remittances and their documents) so the record must be persisted.
When('the validation rules are evaluated for the capital call') do
  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: @capital_call, entity: @entity)
  end
end

# Evaluates rules for a persisted CapitalRemittance record (@capital_remittance set by a prior step).
# Rules check only this remittance's documents, not the entire call.
When('the validation rules are evaluated for the capital remittance') do
  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: @capital_remittance, entity: @entity)
  end
end

# Creates a minimal CapitalRemittance (no generated document) linked to @capital_call,
# with its own commitment — see create_rule_test_remittance.
Given('the capital call has a remittance without a generated notice') do
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @entity)
  remittance = create_rule_test_remittance(investor)
end

# Creates a minimal CapitalRemittance plus a generated-but-unapproved Document.
Given('the capital call has a remittance with an unapproved generated notice') do
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @entity)
  remittance = create_rule_test_remittance(investor)

  folder = FactoryBot.create(:folder, entity: @entity)
  FactoryBot.create(:document,
    entity:    @entity,
    user:      @user,
    folder:    folder,
    owner:     remittance,
    owner_tag: "Generated",
    approved:  false
  )
end

# ── Notification-subscription fixtures (Question 6 proactive check) ─────────

# An investor with nobody subscribed to Capital Call notifications: a bare :investor factory
# record has no InvestorAccess at all.
def create_unsubscribed_investor(name)
  FactoryBot.create(:investor, entity: @entity, investor_entity: @entity, investor_name: name)
end

# An investor with one approved contact whose blank tag_list subscribes them to everything,
# including Capital Call. The investor must live in its OWN Investor-type entity, not the GP's:
# FundPolicy#show? admits an investor user only via permissioned_investor_non_advisor?, which
# requires curr_role "investor" (User#setup_defaults derives that from the entity type) AND that
# the user does not belong to the fund's entity. entity_type is pinned — the factory picks one at
# random and a "Group Company" draw would empty the policy scope.
def create_subscribed_investor(name)
  investor_entity = FactoryBot.create(:entity, entity_type: "Investor")
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: investor_entity, investor_name: name)

  # notification_users(fund) filters through Pundit's show? for the fund, so the user needs
  # enable_funds plus an AccessRight linking their investor to the fund — mirrors "the
  # remittances have proper notification users" in features/step_definitions/capital_call.rb.
  user = FactoryBot.create(:user, entity: investor_entity)
  user.permissions.set(:enable_funds)
  user.save!
  user.entity.permissions.set(:enable_funds)
  user.entity.save!
  AccessRight.create!(entity: @fund.entity, access_to_investor_id: investor.id, metadata: "investor", access_type: "Fund", owner: @fund) unless @fund.access_rights.exists?(access_to_investor_id: investor.id)
  # InvestorAccess#update_user resolves `user` from the email regardless of what is passed, but
  # pass the investor-entity user anyway so the fixture reads as it behaves.
  InvestorAccess.create!(email: user.email, investor: investor, approved: true, entity: investor.entity,
                          first_name: user.first_name, last_name: user.last_name, user: user, email_enabled: true)
  investor
end

# Builds a CapitalRemittance for @capital_call the way production data is shaped: every
# remittance hangs off a CapitalCommitment (CapitalRemittance belongs_to :capital_commitment,
# and a remittance without one cannot exist), so the commitment is created first and the
# remittance keyed to its folio. Both are saved with validate: false because the factories
# don't satisfy the full validation set (unit types, KYC, amounts) and none of the rule
# scenarios depend on those fields. skip_doc_gen: true marks the commitment as excluded from
# every send path, which the subscription rules must ignore.
def create_rule_test_remittance(investor, skip_doc_gen: false)
  commitment = FactoryBot.build(:capital_commitment, fund: @fund, entity: @entity, investor: investor, folio_id: "TEST-#{SecureRandom.hex(4)}")
  commitment.json_fields = { "skip_doc_gen" => "Yes" } if skip_doc_gen
  commitment.save(validate: false)

  remittance = FactoryBot.build(:capital_remittance,
    capital_call:       @capital_call,
    fund:               @fund,
    entity:             @entity,
    investor:           investor,
    capital_commitment: commitment,
    folio_id:           commitment.folio_id
  )
  remittance.save(validate: false)
  remittance
end

Given('the capital call has a remittance for an investor with no notification subscribers') do
  create_rule_test_remittance(create_unsubscribed_investor("Unsubscribed Investor"))
end

Given('the capital call has a remittance for an investor with a subscribed notification user') do
  create_rule_test_remittance(create_subscribed_investor("Subscribed Investor"))
end

# A skip_doc_gen commitment is excluded from every send path, so a missing subscription must
# not be reported for it. The remittance and its commitment are created unvalidated, like the
# other CapitalCall fixtures in this file.
Given('the capital call has a remittance for an unsubscribed investor whose commitment skips doc generation') do
  create_rule_test_remittance(create_unsubscribed_investor("Skipped Investor"), skip_doc_gen: true)
end

Given('there is a capital commitment for an investor with no notification subscribers') do
  investor = create_unsubscribed_investor("Unsubscribed Investor")
  @capital_commitment = FactoryBot.build(:capital_commitment, fund: @fund, entity: @entity, investor: investor, folio_id: "TEST-#{SecureRandom.hex(4)}")
  @capital_commitment.save(validate: false)
end

Given('there is a capital commitment for an investor with a subscribed notification user') do
  investor = create_subscribed_investor("Subscribed Investor")
  @capital_commitment = FactoryBot.build(:capital_commitment, fund: @fund, entity: @entity, investor: investor, folio_id: "TEST-#{SecureRandom.hex(4)}")
  @capital_commitment.save(validate: false)
end

Given('there is a capital commitment that skips doc generation for an investor with no notification subscribers') do
  investor = create_unsubscribed_investor("Skipped Investor")
  @capital_commitment = FactoryBot.build(:capital_commitment, fund: @fund, entity: @entity, investor: investor, folio_id: "TEST-#{SecureRandom.hex(4)}")
  @capital_commitment.json_fields = { "skip_doc_gen" => "Yes" }
  @capital_commitment.save(validate: false)
end

# Evaluates rules for a persisted CapitalCommitment (@capital_commitment set by a prior step).
When('the validation rules are evaluated for the capital commitment') do
  @rule_results = WithValidationRules.skip do
    ValidationRuleEvaluator.call(record: @capital_commitment, entity: @entity)
  end
end

# Creates a minimal CapitalRemittance plus a generated AND approved Document.
Given('the capital call has a remittance with an approved generated notice') do
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: @entity)
  remittance = create_rule_test_remittance(investor)

  folder = FactoryBot.create(:folder, entity: @entity)
  FactoryBot.create(:document,
    entity:    @entity,
    user:      @user,
    folder:    folder,
    owner:     remittance,
    owner_tag: "Generated",
    approved:  true
  )
end

# ── Rule result assertions ────────────────────────────────────────────────────

Then('the rule {string} fires as a {string}') do |rule_name, expected_severity|
  match = @rule_results.find { |r| r.rule.name == rule_name }
  expect(match).not_to be_nil,
    "Expected rule '#{rule_name}' to fire but it did not. " \
    "Rules that fired: #{@rule_results.map { |r| r.rule.name }.inspect}"
  expect(match.severity).to eq(expected_severity),
    "Expected '#{rule_name}' severity '#{expected_severity}' but got '#{match.severity}'"
end

Then('the rule {string} does not fire') do |rule_name|
  match = @rule_results.find { |r| r.rule.name == rule_name }
  expect(match).to be_nil,
    "Expected rule '#{rule_name}' NOT to fire but it did with message: #{match&.message}"
end

Then('the rule message includes {string}') do |expected_text|
  messages = @rule_results.map(&:message)
  expect(messages.any? { |m| m.include?(expected_text) }).to be(true),
    "Expected a rule message to include '#{expected_text}' but got: #{messages.inspect}"
end

Then('the rule message includes the portfolio company name') do
  @portfolio_company ||= @entity.investors.portfolio_companies.last
  steps %(Then the rule message includes "#{@portfolio_company.investor_name}")
end

# ── UI steps ─────────────────────────────────────────────────────────────────

When('I visit the new valuation page for the portfolio company') do
  @portfolio_company ||= @entity.investors.portfolio_companies.last
  visit new_valuation_path("valuation[owner_id]": @portfolio_company.id, "valuation[owner_type]": "Investor")
end

When('I fill the valuation form with date {string} and per_share_value {string}') do |date, value|
  @investment_instrument ||= @portfolio_company.investment_instruments.last
  if @investment_instrument
    # New-record form uses a Select2 multiple select (investment_instrument_ids[])
    container = find("select#valuation_investment_instrument_ids", visible: false)
                  .sibling(".select2-container")
    container.find(".select2-selection").click
    find(".select2-results__option", text: @investment_instrument.name, wait: 5).click
  end
  fill_in "valuation_valuation_date", with: date
  fill_in "valuation_per_share_value", with: value
end

When('I submit the valuation form') do
  click_on "Save"
end

When('I visit the generate fund ratios page for the fund') do
  @fund ||= @entity.funds.last
  visit generate_fund_ratios_fund_path(@fund)
end

When('I fill the fund ratios end date with {string}') do |date|
  fill_in "fund_end_date", with: date
end

When('I submit the fund ratios form') do
  click_on "Generate"
end

When('I visit the validation rule overrides page') do
  visit validation_rule_overrides_path
end

Then('the rule validation modal appears') do
  expect(page).to have_css("#ruleValidationModal", wait: 5)
end

Then('the modal shows a warning containing {string}') do |text|
  within("#ruleValidationModal") do
    expect(page).to have_content(text, wait: 5)
  end
end

Then('the modal has a {string} button') do |button_text|
  within("#ruleValidationModal") do
    expect(page).to have_button(button_text)
  end
end

Then('the modal does not have a {string} button') do |button_text|
  within("#ruleValidationModal") do
    expect(page).not_to have_button(button_text)
  end
end

When('I click {string} in the modal') do |button_text|
  within("#ruleValidationModal") do
    click_on button_text
  end
  sleep 1  # allow Turbo/form submission to complete
end

Then('the valuation is saved successfully') do
  expect(page).to have_content("Valuation was successfully created", wait: 5)
end

Then('I see the rule {string} listed') do |rule_display_name|
  expect(page).to have_content(rule_display_name)
end

When('I click {string} for the rule {string}') do |link_text, rule_display_name|
  row = find("tr, .rule-card", text: rule_display_name)
  within(row) { click_on link_text }
end

# The "Enable this rule" toggle is a CSS toggle switch — the actual checkbox is
# hidden (opacity:0) inside a <label>. Clicking the label fires the toggle.
When('I disable the rule enable toggle') do
  find("#override_enabled_toggle", visible: false).tap do |cb|
    page.execute_script("arguments[0].click()", cb.native)
  end
end


When('I fill in the param {string} with {string}') do |param_name, value|
  field = find("input[name*='param_overrides'][name*='#{param_name}']")
  field.fill_in with: value
end

When('I select {string} from the severity dropdown') do |option|
  select option, from: "validation_rule_override_severity_override"
end

When('I fill in the message override with {string}') do |message|
  fill_in "validation_rule_override_message_override", with: message
end


Then('I see {string}') do |text|
  expect(page).to have_content(text, wait: 5)
end

Then('the rule {string} is disabled for the entity') do |rule_name|
  rule     = ValidationRule.find_by!(name: rule_name, entity_id: nil, is_default: true)
  override = ValidationRuleOverride.find_by(validation_rule: rule, entity: @entity)
  expect(override).not_to be_nil
  expect(override.enabled).to be(false)
end

Then('the rule {string} has severity override {string} for the entity') do |rule_name, severity|
  rule     = ValidationRule.find_by!(name: rule_name, entity_id: nil, is_default: true)
  override = ValidationRuleOverride.find_by(validation_rule: rule, entity: @entity)
  expect(override).not_to be_nil
  expect(override.severity_override).to eq(severity)
end
