# Step definitions for the Validation Rule Engine feature.
# Reuses existing steps for user/entity/fund/investor/valuation/portfolio setup.
# Adds only the steps specific to rule evaluation and override management.

# ── Setup ─────────────────────────────────────────────────────────────────────

Given('the default validation rules are seeded') do
  ValidationRulesSeed.seed!
end

# Opts @entity in to all global default rules by creating enabled=true overrides.
# Rules are seeded disabled by default; call this in any scenario that expects rules to fire.
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
      param_overrides[k.strip] = v.strip
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
  fill_in "end_date", with: date
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
