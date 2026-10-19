# Steps for the LP folio portfolio & company dashboard features.
# Worked examples: openspec/changes/lp-folio-portfolio-dashboard/business-rules.md

# The shared-setup formulas (#501–#507) by name, with the rule types the business rules give them
LP_FORMULA_RULE_TYPES = {
  "Allocated Portfolio Cost" => "AllocatePortfolioInvestment",
  "Allocated Portfolio FMV" => "AllocatePortfolioInvestment",
  "Allocated Portfolio Cost Proforma" => "AllocatePortfolioInvestment-Proforma",
  "Apportioned Deal Expense" => "AllocatePortfolioInvestment",
  "Portfolio FMV by API" => "AllocateAggregatePortfolios",
  "Company Fees" => "AllocateForPortfolioCompany-Folio",
  "Management Fee" => "AllocateAccountEntry-Name"
}.freeze

# Looks a formula up by name across the funds created in the scenario
def lp_formula(name)
  FundFormula.find_by!(name:)
end

Given('the fund has the LP allocation formulas') do
  LP_FORMULA_RULE_TYPES.each do |name, rule_type|
    FactoryBot.create(:fund_formula, fund: @fund, entity_id: @fund.entity_id, name:, rule_type:)
  end
end

Given('another fund {string} has the formula {string}') do |fund_name, formula_name|
  @other_fund = FactoryBot.create(:fund, entity_id: @fund.entity_id, name: fund_name, currency: @fund.currency)
  FactoryBot.create(:fund_formula, fund: @other_fund, entity_id: @fund.entity_id, name: formula_name, rule_type: "AllocatePortfolioInvestment")
end

Given('the fund LP portfolio view is {string}') do |view|
  @fund.update!(lp_portfolio_view: view)
end

Given('the fund LP portfolio view is {string} with allocation formula {string}') do |view, allocation|
  @fund.update!(lp_portfolio_view: view, lp_allocation_fund_formula: lp_formula(allocation))
end

Given('the fund LP portfolio view is {string} with allocation formula {string} and FMV formula {string}') do |view, allocation, fmv|
  @fund.update!(lp_portfolio_view: view, lp_allocation_fund_formula: lp_formula(allocation), lp_fmv_fund_formula: lp_formula(fmv))
end

# An LP investor and its folio in a fund. Investor.create! (not the :investor factory) avoids that factory's
# Entity.startups.sample defaults, as elsewhere in this suite.
# Named lp_folio_commitment: lp_fund_stats.rb has its own no-argument lp_commitment, and step files share one namespace
def lp_folio_commitment(fund, investor_name, folio_id)
  investor = Investor.find_or_create_by!(entity_id: fund.entity_id, investor_name:) do |inv|
    inv.primary_email = "#{investor_name.parameterize}@example.com"
    inv.category = "LP"
  end
  CapitalCommitment.find_by(fund:, folio_id:) ||
    FactoryBot.create(:capital_commitment, fund:, entity_id: fund.entity_id, investor:, folio_id:)
end

Given('the allocation formula {string} has a folio entry') do |name|
  commitment = lp_folio_commitment(@fund, "LP One", "F-001")
  FactoryBot.create(:account_entry, fund: @fund, entity_id: @fund.entity_id, capital_commitment: commitment,
                                    investor: commitment.investor, folio_id: commitment.folio_id,
                                    fund_formula: lp_formula(name), amount_cents: 100)
end

# Picks the dropdown option by its label and optional formulas, then saves the fund form
When('I set the LP portfolio view to {string} on the fund form and save') do |label|
  step %(I set the LP portfolio view to "#{label}" with allocation formula "" and FMV formula "" on the fund form and save)
end

When('I set the LP portfolio view to {string} with allocation formula {string} on the fund form and save') do |label, allocation|
  step %(I set the LP portfolio view to "#{label}" with allocation formula "#{allocation}" and FMV formula "" on the fund form and save)
end

When('I set the LP portfolio view to {string} with allocation formula {string} and FMV formula {string} on the fund form and save') do |label, allocation, fmv|
  open_fund_form_features(@fund)
  select(label, from: "fund_lp_portfolio_view")
  select(allocation, from: "fund_lp_allocation_fund_formula_id") if allocation.present?
  select(fmv, from: "fund_lp_fmv_fund_formula_id") if fmv.present?
  click_on("Save")
end

When('I open the LP portfolio view on the fund form') do
  open_fund_form_features(@fund)
end

When('I choose {string} in the LP portfolio view') do |label|
  select(label, from: "fund_lp_portfolio_view")
end

When('a fund {string} is uploaded with {string} = {string}') do |name, header, value|
  import_upload = OpenStruct.new(entity: @fund.entity, entity_id: @fund.entity_id, id: nil)
  ImportFund.new.save_row({ "Name" => name, "Currency" => @fund.currency, header => value }, import_upload, [])
  @fund = Fund.find_by!(name:)
end

When('a client sets the legacy show portfolios switch to {string}') do |value|
  @fund.reload.update!(show_portfolios: value == "true")
end

When('a fund {string} is created in the entity') do |name|
  @fund = FactoryBot.create(:fund, entity_id: @fund.entity_id, name:, currency: @fund.currency)
end

When('a request sets the fund {string} to the formula {string}') do |attribute, name|
  @fund.reload
  @fund.assign_attributes(attribute => lp_formula(name).id)
  @saved = @fund.save
end

Then('the fund LP portfolio view should be {string}') do |view|
  expect(@fund.reload.lp_portfolio_view).to eq(view.to_sym)
end

Then('the fund LP allocation formula should be {string}') do |name|
  expect(@fund.reload.lp_allocation_fund_formula&.name).to eq(name)
end

Then('the fund LP portfolio bits should include {string}') do |flags|
  flags.split(",").each { |f| expect(@fund.reload.features.set?(f.strip.to_sym)).to be(true), "#{f} not set" }
end

Then('the LP portfolio view on the form should show {string}') do |label|
  open_fund_form_features(@fund)
  expect(page).to have_select("fund_lp_portfolio_view", selected: label)
end

Then('the allocation formula picker should list only {string}') do |names|
  expect(page).to have_select("fund_lp_allocation_fund_formula_id", options: ["Choose a formula"] + names.split(",").map(&:strip))
end

Then('the allocation formula picker should be {string}') do |state|
  expect(page).to have_field("fund_lp_allocation_fund_formula_id", visible: state == "visible")
end

Then('the FMV formula picker should be {string}') do |state|
  expect(page).to have_field("fund_lp_fmv_fund_formula_id", visible: state == "visible")
end

Then('the LP portfolio view tooltip should read {string}') do |text|
  expect(page).to have_css("#lp_portfolio_view [data-bs-title=\"#{text}\"]")
end

Then('the fund save should be refused with {string}') do |message|
  expect(@saved).to be(false)
  expect(@fund.errors.full_messages).to include(message)
end

# ---------------------------------------------------------------------------------------------------------
# Holdings, LPs and folio entries for the shared setup (business-rules.md#shared-setup). Amounts are in ₹ Cr.
# ---------------------------------------------------------------------------------------------------------

CRORE_CENTS = 1_000_000_000 # ₹1 Cr in paise

def lp_fund(name)
  Fund.find_by!(name:)
end

def lp_portfolio_company(entity_id, name, tags = nil)
  company = Investor.find_or_create_by!(entity_id:, investor_name: name) do |inv|
    inv.primary_email = "#{name.parameterize}@example.com"
    inv.category = "Portfolio Company"
  end
  company.update!(tag_list: tags) if tags
  company
end

# The aggregated holding (fund × company × instrument)
def lp_holding(fund, company_name, instrument_name)
  AggregatePortfolioInvestment.joins(:investment_instrument)
                              .find_by!(fund:, portfolio_company_name: company_name, investment_instruments: { name: instrument_name })
end

# Creates each holding through PortfolioInvestmentCreate (as the existing portfolio steps do), split into the
# given number of equal purchases, then sets the holding's cost and FMV to the table's figures.
Given('the fund {string} holds:') do |fund_name, table|
  fund = lp_fund(fund_name)
  table.hashes.each do |row|
    company = lp_portfolio_company(fund.entity_id, row["company"], row["tags"])
    instrument = InvestmentInstrument.find_or_create_by!(entity_id: fund.entity_id, portfolio_company: company, name: row["instrument"]) do |ii|
      ii.category = "Unlisted"
      ii.sub_category = "Equity"
      ii.sector = "Tech"
      ii.currency = fund.currency
    end
    purchases = (row["purchases"] || 1).to_i
    purchases.times do |i|
      pi = FactoryBot.build(:portfolio_investment, entity: fund.entity, fund:, portfolio_company: company, investment_instrument: instrument,
                                                   quantity: 1000, investment_date: Date.new(2025, 1, 1) + i.months,
                                                   ex_expenses_base_amount_cents: (row["cost_cr"].to_d * CRORE_CENTS / purchases).round)
      expect(PortfolioInvestmentCreate.call(portfolio_investment: pi)).to be_success
    end
    lp_holding(fund, row["company"], row["instrument"]).update_columns(fmv_cents: row["fmv_cr"].to_d * CRORE_CENTS,
                                                                       cost_of_remaining_cents: row["cost_cr"].to_d * CRORE_CENTS)
  end
end

Given('there is a feeder fund {string} of {string}') do |name, master_name|
  master = lp_fund(master_name)
  FactoryBot.create(:fund, entity_id: master.entity_id, name:, currency: master.currency, master_fund: master)
end

Given('the fund {string} has the formula {string} of type {string}') do |fund_name, name, rule_type|
  fund = lp_fund(fund_name)
  FactoryBot.create(:fund_formula, fund:, entity_id: fund.entity_id, name:, rule_type:)
end

Given('the fund {string} LP portfolio view is {string} with allocation formula {string}') do |fund_name, view, allocation|
  lp_fund(fund_name).update!(lp_portfolio_view: view, lp_allocation_fund_formula: lp_formula(allocation))
end

Given('the fund {string} LP portfolio view is {string}') do |fund_name, view|
  lp_fund(fund_name).update!(lp_portfolio_view: view)
end

# An LP: their own investor entity and user, the Investor record in the fund manager's entity, an approved
# investor access, an access right on the fund and the folio (the access_rights.rb pattern)
def lp_investor(fm_entity_id, name)
  lp_entity = Entity.find_by(name:) || FactoryBot.create(:entity, entity_type: "Investor", name:)
  investor = Investor.find_or_create_by!(entity_id: fm_entity_id, investor_name: name) do |inv|
    # Investor#update_name finds its investor entity by primary email, so use the LP entity's
    inv.investor_entity_id = lp_entity.id
    inv.primary_email = lp_entity.primary_email
    inv.category = "LP"
  end
  user = User.find_by(entity_id: lp_entity.id) || FactoryBot.create(:user, entity: lp_entity, first_name: name.split.first)
  user.update!(curr_role: "investor")
  InvestorAccess.find_or_create_by!(investor:, email: user.email) do |ia|
    ia.entity_id = fm_entity_id
    ia.first_name = user.first_name
    ia.last_name = user.last_name
    ia.granter = user
    ia.approved = true
  end
  [investor, user]
end

def lp_grant_access(fund, investor)
  AccessRight.find_or_create_by!(entity_id: fund.entity_id, owner: fund, access_to_investor_id: investor.id) { |ar| ar.metadata = "Investor" }
end

Given('LP {string} has folio {string} in {string}') do |name, folio_id, fund_name|
  fund = lp_fund(fund_name)
  investor, = lp_investor(fund.entity_id, name)
  lp_grant_access(fund, investor)
  FactoryBot.create(:capital_commitment, fund:, entity_id: fund.entity_id, investor:, folio_id:)
end

Given('LP {string} has access to {string} and no folio') do |name, fund_name|
  fund = lp_fund(fund_name)
  investor, = lp_investor(fund.entity_id, name)
  lp_grant_access(fund, investor)
end

# Folio entries, PI-level by default; an aggregated-holding formula writes on the holding (E21)
Given('folio {string} has allocation entries:') do |folio_id, table|
  commitment = CapitalCommitment.find_by!(folio_id:)
  table.hashes.each do |row|
    formula = lp_formula(row["formula"])
    holding_fund = row["holding fund"].present? ? lp_fund(row["holding fund"]) : commitment.fund
    api = lp_holding(holding_fund, row["company"], row["instrument"])
    parent = formula.rule_type == "AllocateAggregatePortfolios" ? api : api.portfolio_investments.order(:id).to_a[(row["purchase"] || 1).to_i - 1]
    amount = lp_amount_cents(row["amount"])
    entry = FactoryBot.create(:account_entry, fund: commitment.fund, entity_id: commitment.entity_id, capital_commitment: commitment,
                                              investor: commitment.investor, folio_id:, fund_formula: formula, name: formula.name,
                                              parent:, amount_cents: amount, reporting_date: Date.parse(row["date"] || "30/09/2026"))
    entry.update_columns(deleted_at: Time.current) if row["deleted"] == "yes"
  end
end

# "2.50" = ₹2.50 Cr; "0.4 paise" = raw minor units; "120000 USD" = dollars
def lp_amount_cents(text)
  text = text.to_s
  return text.to_d if text.end_with?("paise")
  return text.to_d * 100 if text.end_with?("USD")

  text.to_d * CRORE_CENTS
end

def lp_sign_in(name)
  @fm_user ||= @user
  user = User.find_by!(entity_id: Entity.find_by!(name:).id)
  user.update!(curr_role: "investor")
  steps %(Given I log out) if page.driver.respond_to?(:reset!)
  log_in(user)
  @lp_user = user
end

When('LP {string} opens the portfolio of {string}') do |name, fund_name|
  lp_sign_in(name)
  visit(aggregate_portfolio_investments_path(fund_id: lp_fund(fund_name).id))
end

When('LP {string} opens the purchases list of {string}') do |name, fund_name|
  lp_sign_in(name)
  visit(portfolio_investments_path(fund_id: lp_fund(fund_name).id))
end

When('LP {string} opens the portfolio dashboard of {string}') do |name, fund_name|
  lp_sign_in(name)
  visit(dashboard_fund_path(lp_fund(fund_name), dashboard_name: "Portfolio Dashboard"))
end

When('LP {string} requests the holding {string} {string} of {string} directly') do |name, company, instrument, fund_name|
  lp_sign_in(name)
  fund = lp_fund(fund_name)
  visit(aggregate_portfolio_investments_path(fund_id: fund.id, portfolio_company_id: lp_portfolio_company(fund.entity_id, company).id))
  @direct_holding = lp_holding(fund, company, instrument)
end

When('the LP reloads the page') do
  visit(current_url)
end

Then('the LP should see the holdings {string}') do |names|
  names.split(",").map(&:strip).each { |company| expect(page).to have_content(company) }
end

Then('the LP should not see the holdings {string}') do |names|
  names.split(",").map(&:strip).each { |company| expect(page).to have_no_content(company) }
end

Then('the LP folio banner should read {string}') do |text|
  expect(page).to have_css("#lp_folio_banner", text:)
end

# The stats cards print the short unit label ("₹58.00 Cr"), so the expected text is built the same way
Then('the LP totals should show FMV {string} Cr for {string}') do |amount, fund_name|
  fund = lp_fund(fund_name)
  expected = ApplicationController.helpers.money_to_currency(Money.new(amount.to_d * CRORE_CENTS, fund.currency), { force_units: fund.default_currency_units }, short_units: true)
  expect(page).to have_content(expected)
end

Then('the LP portfolio dashboard should show only the holdings list') do
  expect(page).to have_css("[id^='portfolio_investments_']")
  %w[fmv_ holding_cost_ bought_ sold_ portfolio_irr_ portfolio_stats_].each do |prefix|
    expect(page).to have_no_css("[id^='#{prefix}']")
  end
end

Then('the LP portfolio dashboard should show the fund-wide charts') do
  expect(page).to have_css("[id^='portfolio_stats_']")
end

Then('the direct holding page should be refused') do
  expect(page).to have_no_content(@direct_holding.portfolio_company_name)
  # Holding addresses send LPs to the company's LP page, which refuses a company outside their visible set (X17)
  visit(aggregate_portfolio_investment_path(@direct_holding))
  expect(page).to have_content("You do not have access to this company.")
end

Given('folio {string} has an allocation-formula entry for {string} {string} of {string} dated today') do |folio_id, company, instrument, amount|
  commitment = CapitalCommitment.find_by!(folio_id:)
  formula = commitment.fund.lp_allocation_fund_formula
  api = lp_holding(commitment.fund, company, instrument)
  FactoryBot.create(:account_entry, fund: commitment.fund, entity_id: commitment.entity_id, capital_commitment: commitment,
                                    investor: commitment.investor, folio_id:, fund_formula: formula, name: formula.name,
                                    parent: api.portfolio_investments.first, amount_cents: amount.to_d * CRORE_CENTS,
                                    reporting_date: Time.zone.today)
end

Given('there is a feeder fund {string} of {string} in {string}') do |name, master_name, currency|
  master = lp_fund(master_name)
  FactoryBot.create(:fund, entity_id: master.entity_id, name:, currency:, master_fund: master)
end

Given('the fund {string} LP portfolio view is {string} with allocation formula {string} and FMV formula {string}') do |fund_name, view, allocation, fmv|
  lp_fund(fund_name).update!(lp_portfolio_view: view, lp_allocation_fund_formula: lp_formula(allocation), lp_fmv_fund_formula: lp_formula(fmv))
end

When('folio {string} entry {string} for {string} {string} purchase {int} changes to {string}') do |folio_id, formula, company, instrument, purchase, amount|
  commitment = CapitalCommitment.find_by!(folio_id:)
  pi = lp_holding(commitment.fund, company, instrument).portfolio_investments.order(:id).to_a[purchase - 1]
  AccountEntry.where(capital_commitment: commitment, fund_formula: lp_formula(formula), parent: pi)
              .update_all(amount_cents: lp_amount_cents(amount))
end

When('the formula {string} is renamed to {string}') do |name, new_name|
  lp_formula(name).update_columns(name: new_name)
end

When('the formula {string} is deleted') do |name|
  lp_formula(name).destroy
end

When('the fund team opens the fund page of {string}') do |fund_name|
  steps %(Given I log out)
  log_in(@fm_user || @user)
  visit(fund_path(lp_fund(fund_name)))
end

# Checks the holdings grid row for a company holds the LP's figures, formatted as the grid formats money
Then('the LP should see Your cost {string} and Your FMV {string} for {string}') do |cost, fmv, company|
  row = find(:xpath, "//tr[td[contains(normalize-space(.), '#{company}')]]", match: :first)
  [cost, fmv].each do |amount|
    expect(row).to have_content(amount == "—" ? "—" : lp_money(amount))
  end
end

Then('the LP should see Your multiple {string} for {string}') do |multiple, company|
  expect(find(:xpath, "//tr[td[contains(normalize-space(.), '#{company}')]]", match: :first)).to have_content(multiple)
end

Then('the LP should not see the Your columns') do
  expect(page).to have_no_content("Your Cost")
  expect(page).to have_no_css("#lp_own_share_note")
end

Then('the LP own share note should read {string}') do |text|
  expect(find("#lp_own_share_note")).to have_content(text)
end

Then('the LP own share totals should be cost {string} and FMV {string}') do |cost, fmv|
  note = find("#lp_own_share_note")
  expect(note).to have_content(lp_money(cost, force_units: true))
  expect(note).to have_content(lp_money(fmv, force_units: true))
end

# "₹2.50 Cr" / "$120,000" -> the app's formatting of that amount for the scenario's funds
def lp_money(text, force_units: false)
  if text.start_with?("$")
    money = Money.new(text.delete("$,").to_d * 100, "USD")
    units = force_units ? Fund.find_by(currency: "USD")&.default_currency_units : nil
  else
    money = Money.new(text.delete("₹ Cr,").to_d * CRORE_CENTS, "INR")
    units = force_units ? Fund.find_by(currency: "INR")&.default_currency_units : nil
  end
  ApplicationController.helpers.money_to_currency(money, { force_units: units }.compact)
end

When('folio {string} entry {string} for {string} dated {string} is deleted') do |folio_id, formula, _company, date|
  AccountEntry.where(capital_commitment: CapitalCommitment.find_by!(folio_id:), fund_formula: lp_formula(formula),
                     reporting_date: Date.parse(date)).update_all(deleted_at: Time.current)
end

# ---------------------------------------------------------------------------------------------------------
# Company sharing and LP layouts (box ⑤)
# ---------------------------------------------------------------------------------------------------------

def lp_company(name)
  Investor.find_by!(investor_name: name, category: "Portfolio Company")
end

Given('the company {string} is shown to LPs') do |name|
  lp_company(name).update!(show_to_lps: true)
end

Given('the company {string} is tagged {string}') do |name, tags|
  lp_company(name).update!(tag_list: tags)
end

# Layout rows: | widget | size | position | tags | enabled |
Given('the LP layout {string} has widgets:') do |layout, table|
  table.hashes.each_with_index do |row, i|
    DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: layout,
                            widget_name: row["widget"], size: row["size"].presence || "XL", position: (row["position"].presence || (i + 1)).to_i,
                            tags: row["widget"], tag_list: row["tags"].presence, enabled: row["enabled"] != "no", display_name: true,
                            metadata: row["metadata"].presence)
  end
end

Given('the layout {string} has the widget {string}') do |layout, widget|
  DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: layout,
                          widget_name: widget, size: "XL", tags: widget, enabled: true)
end

Given('the holding {string} {string} of {string} had Show Portfolio {string}') do |company, instrument, fund_name, value|
  lp_holding(lp_fund(fund_name), company, instrument).update_columns(show_portfolio: value == "on")
end

Given('the holding {string} {string} of {string} is deleted') do |company, instrument, fund_name|
  lp_holding(lp_fund(fund_name), company, instrument).update_columns(deleted_at: Time.current)
end

Given('the company {string} is deleted') do |name|
  lp_company(name).update_columns(deleted_at: Time.current)
end

When('I open the company page of {string}') do |name|
  visit(investor_path(lp_company(name)))
end

When('I open the LPs menu') do
  find("#lp_sharing_menu").click
end

When('I click Show to LPs') do
  # Show / Hide and Preview as LP sit in the company page's LPs menu
  find("#lp_sharing_menu").click
  click_on("Show to LPs")
end

# @rack_test scenarios: send the request directly, as a double click or a hand-made request would
When('I submit Show to LPs for {string} twice') do |company|
  2.times { page.driver.submit(:patch, lp_sharing_investor_path(lp_company(company), show_to_lps: true), {}) }
end

When('I hide the company from LPs and confirm') do
  find("#lp_sharing_menu").click
  click_on("Hide from LPs")
  within("#confirmModal") do
    expect(page).to have_content("LPs will no longer be able to open this company's page. Their portfolio list still shows the company.")
    click_on("Proceed")
  end
end

When('I set up the LP layout') do
  visit(dashboard_widgets_path)
  click_on("Set up LP layout")
end

When('I submit Set up LP layout twice') do
  2.times { page.driver.submit(:post, setup_lp_layout_dashboard_widgets_path, {}) }
end

When('I open the LP layout {string} in widget settings') do |layout|
  visit(dashboard_widgets_path(q: DashboardWidget.layout_filter(layout)))
end

When('I add a widget to the LP layout {string}') do |layout|
  visit(new_dashboard_widget_path(dashboard_widget: { dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: layout }))
end

When('I create a new LP layout for the tag {string}') do |tag|
  step %(I open the LP layout "LP" in widget settings)
  fill_in("tag", with: tag)
  click_on("New LP layout for a tag")
end

When('a request saves a {string} widget into the layout {string}') do |widget, layout|
  @widget = DashboardWidget.new(entity_id: @user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD,
                                name: layout, widget_name: widget, size: "XL", tags: widget)
  @saved = @widget.save
end

When('a request moves the Default {string} widget into the layout {string}') do |widget, layout|
  @widget = DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD,
                                    name: "Default", widget_name: widget, size: "XL", tags: widget)
  @saved = @widget.update(name: layout)
end

When('I remove the {string} widget from the LP layout {string}') do |widget, layout|
  DashboardWidget.find_by!(name: layout, widget_name: widget, entity_id: @user.entity_id).destroy!
end

When('the carry-over runs') do
  @carry_over = LpCompanySwitchCarryOver.call
end

When('{string} submits Show to LPs for {string} directly') do |who, company|
  steps %(Given I log out)
  log_in(who == "the LP" ? @lp_user : User.find_by!(first_name: who))
  page.driver.submit(:patch, lp_sharing_investor_path(lp_company(company), show_to_lps: true), {})
end

Then('the company {string} should be shown to LPs') do |name|
  expect(lp_company(name).reload.show_to_lps).to be(true)
end

Then('the company {string} should not be shown to LPs') do |name|
  expect(lp_company(name).reload.show_to_lps).to be(false)
end

Then('the carry-over should report {int} changed and {int} skipped') do |changed, skipped|
  expect(@carry_over.changed).to eq(changed)
  expect(@carry_over.skipped).to eq(skipped)
end

Then('the LP layout {string} should hold {string}') do |layout, widgets|
  names = DashboardWidget.where(entity_id: @user.entity_id, name: layout).order(:position).pluck(:widget_name)
  expect(names).to eq(widgets.split(",").map(&:strip))
end

Then('the widget save should be refused with {string}') do |message|
  expect(@saved).to be(false)
  expect(@widget.errors.full_messages).to include(message)
end

Then('the widget type list should offer only the LP-safe types') do
  options = JSON.parse(find("#widget_options_json", visible: false).value)[DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD]
  # The fund manager's LP-safe types: the KPI widgets only with the KPI module (E52, E97)
  expect(options).to match_array(DashboardWidget.lp_safe_widget_names(@user.entity.reload))
end

Then('the element {string} should have the tooltip {string}') do |text, tooltip|
  expect(page).to have_css("[data-bs-title=\"#{tooltip}\"]", text:)
end

When('I visit the widget settings') do
  visit(dashboard_widgets_path)
end

Given('there is a read-only employee {string} in the entity') do |first_name|
  FactoryBot.create(:user, entity_id: @user.entity_id, first_name:).add_role(:employee)
end

# ---------------------------------------------------------------------------------------------------------
# LP Company Dashboard (box ⑥) and its widget data (box ⑦)
# ---------------------------------------------------------------------------------------------------------

LP_FIXTURES = { "video" => "features/support/fixtures/founder_video.mp4", "pdf" => "public/sample_uploads/SignedDoc.pdf" }.freeze

Given('the company {string} has a {string} document named {string}') do |company, kind, name|
  investor = lp_company(company)
  Document.create!(entity_id: investor.entity_id, owner: investor, name:, user: @user, folder: investor.document_folder,
                   file: File.new(LP_FIXTURES.fetch(kind), "r"))
end

Given('the fund {string} has a {string} document named {string}') do |fund_name, kind, name|
  fund = lp_fund(fund_name)
  Document.create!(entity_id: fund.entity_id, owner: fund, name:, user: @user, folder: fund.document_folder,
                   file: File.new(LP_FIXTURES.fetch(kind), "r"))
end

# KPI reports for a company: | as_of | tag | kpi | value |
Given('the company {string} has KPIs:') do |company, table|
  investor = lp_company(company)
  table.hashes.each do |row|
    report = KpiReport.find_or_create_by!(entity_id: investor.entity_id, portfolio_company_id: investor.id, as_of: Date.parse(row["as_of"]),
                                          tag_list: row["tag"], period: "Quarter") { |r| r.user_id = @user.id }
    mapping = InvestorKpiMapping.find_or_create_by!(entity_id: investor.entity_id, investor:, standard_kpi_name: row["kpi"]) do |m|
      m.reported_kpi_name = row["kpi"]
      m.category = "Income Statement"
    end
    Kpi.create!(entity_id: investor.entity_id, kpi_report: report, portfolio_company_id: investor.id, investor_kpi_mapping: mapping,
                name: row["kpi"], value: row["value"].to_d)
  end
end

Given('the fund dashboard of {string} has an Embed Document widget named {string}') do |_fund_name, name|
  DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: DashboardWidget::FUND_DASHBOARD, name: "Default",
                          widget_name: "Embed Document", size: "XL", tags: "Founder Video", enabled: true, display_name: true,
                          metadata: "{name: '#{name}'}")
end

Given('the holding {string} {string} of {string} has a legacy widget {string}') do |company, instrument, fund_name, title|
  api = lp_holding(lp_fund(fund_name), company, instrument)
  CiWidget.create!(owner: api, entity_id: api.entity_id, title:)
end

When('LP {string} opens the company {string}') do |name, company|
  lp_sign_in(name)
  visit(lp_company_dashboard_path(lp_company(company)))
end

When('LP {string} opens the company {string} for {string}') do |name, company, fund_name|
  lp_sign_in(name)
  visit(lp_company_dashboard_path(lp_company(company), fund_id: lp_fund(fund_name).id))
end

When('LP {string} opens the old holding link of {string} {string} in {string}') do |name, company, instrument, fund_name|
  lp_sign_in(name)
  visit(aggregate_portfolio_investment_path(lp_holding(lp_fund(fund_name), company, instrument), preview: "true"))
end

When('LP {string} requests the preview of {string}') do |name, company|
  lp_sign_in(name)
  investor = Investor.find_by!(investor_name: name)
  visit(preview_lp_company_dashboard_path(lp_company(company), investor_id: investor.id))
end

When('LP {string} requests the internal page of {string}') do |name, company|
  lp_sign_in(name)
  visit(dashboard_investor_path(lp_company(company)))
end

When('the fund team previews {string} as {string} for {string}') do |company, lp_name, fund_name|
  steps %(Given I log out) if @lp_user
  log_in(@fm_user || @user)
  visit(investor_path(lp_company(company)))
  expect(page).to have_css("#lpPreviewModal", visible: :all)
  visit(preview_lp_company_dashboard_path(lp_company(company), investor_id: Investor.find_by!(investor_name: lp_name).id, fund_id: lp_fund(fund_name).id))
end

When('the fund team opens the holding {string} {string} of {string}') do |company, instrument, fund_name|
  steps %(Given I log out) if @lp_user
  log_in(@fm_user || @user)
  visit(aggregate_portfolio_investment_path(lp_holding(lp_fund(fund_name), company, instrument)))
end

When('the fund team opens the fund dashboard of {string}') do |fund_name|
  visit(dashboard_fund_path(lp_fund(fund_name), dashboard_name: DashboardWidget::FUND_DASHBOARD))
end

When('the LP switches the fund selector to {string}') do |fund_name|
  find("#lp_fund_selector button").click
  click_on(fund_name)
end

def lp_widget_css(widget_name)
  "[id^='#{widget_name.parameterize.underscore}_']"
end

Then('the LP company page should be open for {string}') do |company|
  expect(page).to have_css("#lp_company_dashboard h3", text: company)
end

Then('the LP company page should show the widgets {string}') do |names|
  names.split(",").map(&:strip).each { |name| expect(page).to have_css(lp_widget_css(name)) }
end

Then('the LP company page should not show the widgets {string}') do |names|
  names.split(",").map(&:strip).each { |name| expect(page).to have_no_css(lp_widget_css(name)) }
end

Then('the LP holdings card should list {string}') do |instruments|
  instruments.split(",").map(&:strip).each { |name| expect(find("#lp_holdings_card")).to have_content(name) }
end

Then('the LP holdings card should not list {string}') do |instruments|
  instruments.split(",").map(&:strip).each { |name| expect(find("#lp_holdings_card")).to have_no_content(name) }
end

Then('the LP holdings card should show Your cost {string} and Your FMV {string}') do |cost, fmv|
  card = find("#lp_holdings_card")
  expect(card).to have_content(lp_money(cost))
  expect(card).to have_content(lp_money(fmv))
end

Then('the LP company page should be refused') do
  expect(page).to have_css("#lp_company_refusal", text: "You do not have access to this company.")
  expect(page).to have_no_css("#lp_holdings_card")
end

Then('the LP company page should say it is not shared') do
  expect(page).to have_css("#lp_company_not_shared", text: "No company information has been shared yet.")
  expect(page).to have_no_css("#lp_holdings_card")
end

Then('a video should play inline') do
  expect(page).to have_css("video#document_video", visible: :all)
end

Then('the video should be the latest {string} document of {string}') do |name, company|
  latest = lp_company(company).documents.where(name:).order(id: :desc).first
  expect(page.html).to include(latest.file.id.to_s.split("/").last)
end

Then('the PDF viewer should be shown') do
  expect(page).to have_css("#pdf_viewer", visible: :all)
end

Then('the company page should have no internal controls') do
  expect(page).to have_no_css("#dashboardSelectorDropdown")
  expect(page).to have_no_link("Reports")
  expect(page).to have_no_content("Run Agent")
end

Then('the LP portfolio should link {string} and not {string}') do |linked, plain|
  expect(page).to have_link(linked)
  expect(page).to have_no_link(plain)
  expect(page).to have_content(plain)
end

Then('the KPIs widget should show {string} and not {string}') do |shown, hidden|
  expect(page).to have_css(".lp-kpis", text: shown)
  expect(page).to have_no_css(".lp-kpis", text: hidden)
end

Given('the LP layout widget {string} in {string} is disabled') do |widget, layout|
  DashboardWidget.where(entity_id: @user.entity_id, name: layout, widget_name: widget).update_all(enabled: false)
end

Given('every widget of the LP layout {string} is disabled') do |layout|
  DashboardWidget.where(entity_id: @user.entity_id, name: layout).update_all(enabled: false)
end

Given('the LP user of {string} is tagged {string}') do |name, tags|
  User.find_by!(entity_id: Entity.find_by!(name:).id).update!(tag_list: tags)
end

Given('there is an LP {string} of another fund manager') do |name|
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Northstar Partners")
  other_fund = FactoryBot.create(:fund, entity: other_entity, name: "Northstar Fund I", currency: "INR", show_portfolios: true)
  investor, = lp_investor(other_entity.id, name)
  lp_grant_access(other_fund, investor)
end

Then('a video should not play inline') do
  expect(page).to have_no_css("video#document_video", visible: :all)
end

Then('the LP totals should not show FMV {string} Cr for {string}') do |amount, fund_name|
  fund = lp_fund(fund_name)
  unexpected = ApplicationController.helpers.money_to_currency(Money.new(amount.to_d * CRORE_CENTS, fund.currency), { force_units: fund.default_currency_units }, short_units: true)
  expect(page).to have_no_content(unexpected)
end

# ---------------------------------------------------------------------------------------------------------
# LP assistant (box ⑦): the real LpChatProvider wiring builds RunQueryTool with the LP's visible holdings; the
# LLM is replaced by a fixed SQL query.
# ---------------------------------------------------------------------------------------------------------

LP_ASSISTANT_COMPANIES_SQL = "SELECT DISTINCT api.portfolio_company_name, api.id FROM aggregate_portfolio_investments api " \
                             "WHERE api.entity_id IN ({ENTITY_ID}) AND api.fund_id IN ({FUND_IDS}) AND api.id IN ({VISIBLE_API_IDS}) " \
                             "AND api.deleted_at IS NULL".freeze

def lp_assistant_query_tool(name)
  user = User.find_by!(entity_id: Entity.find_by!(name:).id)
  user.update!(curr_role: "investor")
  LpPortfolioVisibilityCache.reset
  support_agent = OpenStruct.new(entity_id: @user.entity_id, entity: @user.entity)
  LpChatProvider.new(support_agent:, target: nil, analyst: user).tools.find { |tool| tool.is_a?(RunQueryTool) }
end

When('LP {string} asks the assistant for their portfolio companies') do |name|
  @run_query_response = lp_assistant_query_tool(name).execute(sql: LP_ASSISTANT_COMPANIES_SQL)
end

When('the assistant runs a holdings query for LP {string} without the visible-holdings placeholder') do |name|
  sql = "SELECT api.portfolio_company_name FROM aggregate_portfolio_investments api " \
        "WHERE api.entity_id IN ({ENTITY_ID}) AND api.fund_id IN ({FUND_IDS})"
  @run_query_response = lp_assistant_query_tool(name).execute(sql:)
end

Then('the assistant answer should name {string}') do |names|
  names.split(",").map(&:strip).each { |company| expect(@run_query_response).to include(company) }
end

Then('the assistant answer should not name {string}') do |names|
  names.split(",").map(&:strip).each { |company| expect(@run_query_response).not_to include(company) }
end

Then('the holding page should have no Widgets or Track Record tab') do
  within(".api_details nav[role=tablist]") do
    expect(page).to have_no_link("Widgets")
    expect(page).to have_no_link("Track Record")
  end
end

# E95–E97, X20, X21 — switch off one of the fund manager's modules (test entities start with every module on)
Given('the fund manager does not have the {string} module') do |name|
  flag = { "fund portfolios" => :enable_fund_portfolios, "KPI" => :enable_kpis }.fetch(name)
  entity = @user.entity.reload
  entity.update!(permissions: entity.permissions.to_a - [flag])
end

Given('the fund has the feature {string} on') do |flag|
  @fund.reload.update!(features: @fund.features.to_a | [flag.to_sym])
end

When('I save the fund features') do
  open_fund_form_features(@fund)
  click_on("Save")
end

# @rack_test: the request a hand-made form post would send
When('a request saves the fund features {string} with the LP portfolio view {string}') do |flags, view|
  page.driver.submit(:patch, fund_path(@fund), { fund: { features: flags.split(",").map(&:strip), lp_portfolio_view: view } })
end

Then('the company page should have no LP sharing controls') do
  expect(page).to have_content(lp_company("Acme Robotics").investor_name)
  expect(page).to have_no_css("#lp_sharing_menu", visible: :all)
  expect(page).to have_no_css("#lp_sharing_notice", visible: :all)
  expect(page).to have_no_css("#lpPreviewModal", visible: :all)
end
