# Steps for the 2026-10 security review follow-ups F5 (features/security/security_review_2026_10_followups.feature):
# pre-existing bugs found during the review, fixed in the follow-up pass.
#   F5-1 / F5-2  interests#allocate and allocations#verify had no policy predicate (NoMethodError); now firm-only
#   F5-1X        offers#allocate / #allocation_form routes pointed at no action; removed
#   F5-3         a new board got its columns twice
#   F5-4         kyc_datas#fetch_ckyc_data route pointed at no action; removed
#   F5-5         LP assistant skills filtered owner_type 'PortfolioCompany'; real rows say 'Investor'
#   F5-6         RunQueryTool's appended LIMIT 100 was swallowed by a trailing comment
#   F5-7         the allocate_account_entries sample workbook still used custom_fields.send(...)
#   F5-8         Rack::Attack throttled the unrouted /oauth/introspect
#
# Reused steps:
#   security_h8_h11_h14_h15_h19_steps.rb — sec_party / sec_interest_of / sec_allocations, "the sale has allocations …",
#                                          "… has an unverified interest on the sale", "the interest of … has …"
#   security_c4_c7_h16_l10_steps.rb      — sr_request / sr_sign_in, "the address is not found"
#   tenant_isolation_batch1_steps.rb     — "I am denied access"
#   security_core_medium_a_steps.rb      — "the firm … with company admin …", "… is signed in", "they create a board …"
#   lp_portfolio_steps.rb                — the LP / folio / holdings setup, lp_assistant_query_tool(name),
#                                          "the assistant answer should (not) name …"

module SecurityFollowupsBHelpers
  # The SQL of the first ```sql block after the skill's "### Q: "<question>"" heading
  def f5_skill_example_sql(skill, question)
    text = Rails.root.join("app/packs/ai/lp_assistant/skills/#{skill}.md").read
    # The heading, then the next sql fence
    section = text.split(/^### Q: "#{Regexp.escape(question)}".*$/, 2).second
    expect(section).to be_present, "no example \"#{question}\" in the #{skill} skill"
    section[/```sql\n(.*?)```/m, 1]
  end

  # Runs the LP's assistant query and keeps the statement the database received
  def f5_run_and_keep_statement(name, sql)
    tool = lp_assistant_query_tool(name)
    @f5_statement = nil
    # The tool's own log label (RunQueryTool#run_read_only)
    keep = lambda do |*, payload|
      # Without ActiveRecord::QueryLogs' own /*line:…*/ tag, which the adapter adds after the tool
      @f5_statement = payload[:sql].gsub(%r{\s*/\*line:.*?\*/}m, "") if payload[:name] == "LP Assistant Query"
    end
    ActiveSupport::Notifications.subscribed(keep, "sql.active_record") do
      @run_query_response = tool.execute(sql:)
    end
    puts "\n####RunQueryTool response####\n#{@run_query_response}\n"
  end

  # Every action the app routes to `controller` ("kyc_datas", "offers")
  def f5_routed_actions(controller)
    Rails.application.routes.routes.filter_map { |route| route.defaults[:action] if route.defaults[:controller] == controller }.uniq
  end

  # The Formula column of a sample upload workbook (public/sample_uploads/<file>)
  def f5_workbook_formulas(file)
    sheet = Roo::Spreadsheet.open(Rails.root.join("public/sample_uploads", file).to_s).sheet(0)
    column = sheet.row(1).index("Formula") + 1
    (2..sheet.last_row).map { |row| sheet.cell(row, column).to_s }.compact_blank
  end

  # The fund's portfolio company by name (an investors row of the fund manager)
  def f5_portfolio_company(name)
    Investor.find_by!(entity_id: @user.entity_id, investor_name: name)
  end
end
World(SecurityFollowupsBHelpers)

# ---- F5-1 / F5-2 Allocate and verify -------------------------------------------------------------

When('{string} allocates their interest with {string}') do |label, spec|
  # The buyer, through the member route a crafted form would hit
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:patch, allocate_interest_path(sec_interests.fetch(label)), { interest: sec_fields(spec) })
end

When("the sale's company admin allocates the interest of {string} with {string}") do |label, spec|
  # The selling firm's admin, the one user who allocates
  sr_sign_in(@user)
  sr_request(:patch, allocate_interest_path(sec_interests.fetch(label)), { interest: sec_fields(spec) })
end

When("the sale's company admin patches the old allocate address of the seller's offer") do
  # No path helper exists any more: the address as an old link or a crafted request would send it
  sr_sign_in(@user)
  sr_request(:patch, "/offers/#{@offer.id}/allocate", { offer: { allocation_quantity: 1 } })
end

When('{string} verifies the allocation {string}') do |label, pair|
  # A seller or buyer of the allocation
  sr_sign_in(sec_parties.fetch(label)[:user])
  sr_request(:patch, verify_allocation_path(sec_allocations.fetch(pair)))
end

When("the sale's company admin verifies the allocation {string}") do |pair|
  sr_sign_in(@user)
  sr_request(:patch, verify_allocation_path(sec_allocations.fetch(pair)))
end

Then('the allocation {string} is verified') do |pair|
  expect(sec_allocations.fetch(pair).reload.verified).to be(true)
end

Then('the allocation {string} is not verified') do |pair|
  expect(sec_allocations.fetch(pair).reload.verified).to be(false)
end

# ---- F5-1X / F5-4 Dead routes --------------------------------------------------------------------

Then('the {string} routes have no {string} action') do |controller, actions|
  # None of the named actions is routed for the controller any more
  expect(f5_routed_actions(controller) & actions.split(",").map(&:strip)).to be_empty
end

Then('every {string} route points at an action of its controller') do |controller|
  # Drift guard: a route whose action the controller lacks only ever raises
  missing = f5_routed_actions(controller) - "#{controller.camelize}Controller".constantize.action_methods.to_a
  expect(missing).to be_empty
end

# ---- F5-3 Kanban board columns -------------------------------------------------------------------

Given('{string} boards start with the columns {string}') do |firm_name, columns|
  # The firm's kanban steps for a plain board (KanbanBoard#create_columns reads them)
  setting = cma_firm(firm_name).entity_setting
  setting.update!(kanban_steps: (setting.kanban_steps || {}).merge("KanbanBoard" => columns.split(",").map(&:strip)))
end

Then('the board {string} has the columns {string}') do |name, columns|
  # Each step once, in order
  expect(KanbanBoard.find_by!(name:).kanban_columns.pluck(:name)).to eq(columns.split(",").map(&:strip))
end

# ---- F5-5 / F5-6 LP assistant ----------------------------------------------------------------------

Given('the portfolio company {string} has a valuation of {string} crore on {string}') do |name, crore, date|
  # A valuation as the app stores one: owned by the company's investors row (owner_type "Investor")
  company = f5_portfolio_company(name)
  instrument = InvestmentInstrument.find_by!(entity_id: company.entity_id, portfolio_company: company)
  FactoryBot.create(:valuation, entity: company.entity, owner: company, investment_instrument: instrument,
                                valuation_date: Date.parse(date), valuation_cents: crore.to_d * CRORE_CENTS)
end

Given('the fund {string} has a latest {string} ratio {string} for the portfolio company {string}') do |fund_name, ratio, display_value, name|
  # A portfolio company ratio as FundRatiosJob writes it: owner_type "Investor", owner_id the company
  fund = lp_fund(fund_name)
  FundRatio.create!(entity_id: fund.entity_id, fund:, owner: f5_portfolio_company(name), name: ratio,
                    value: display_value.to_d, display_value:, end_date: Date.new(2025, 3, 31),
                    scenario: "Default", latest: true)
end

When('LP {string} runs the {string} skill example {string}') do |name, skill, question|
  # The example exactly as the skill documents it
  @run_query_response = lp_assistant_query_tool(name).execute(sql: f5_skill_example_sql(skill, question))
  puts "\n####RunQueryTool response (#{skill}: #{question})####\n#{@run_query_response}\n"
end

When('LP {string} runs the assistant query {string} and the statement is kept') do |name, sql|
  f5_run_and_keep_statement(name, sql)
end

Then('the statement the assistant ran ends with its own {string} line') do |clause|
  # The appended clause is the last line, alone, so nothing on the model's last line can reach it
  expect(@f5_statement).to be_present
  expect(@f5_statement.rstrip.lines.last.strip).to eq(clause)
end

Then('the statement the assistant ran ends with {string}') do |clause|
  expect(@f5_statement.rstrip).to end_with(clause)
end

Then('the statement the assistant ran has no comment and no other {string}') do |clause|
  # Comments are removed before running; the CTEs carry no LIMIT, so the clause appears once
  expect(@f5_statement).not_to match(%r{--|/\*})
  expect(@f5_statement.scan(/\b#{Regexp.escape(clause)}\b/i).size).to eq(1)
end

# ---- F5-7 Sample workbook ------------------------------------------------------------------------

Then('every formula in the sample workbook {string} passes the fund formula safety check') do |file|
  formulas = f5_workbook_formulas(file)
  expect(formulas).to be_present
  # FundFormula#formula_kosher? is the check a saved or imported formula goes through
  refused = formulas.reject do |text|
    formula = FundFormula.new(formula: text)
    formula.formula_kosher?
    formula.errors[:formula].empty?
  end
  expect(refused).to be_empty
  # And each is still valid Ruby, as the migration checks before storing a rewrite
  formulas.each { |text| expect { Parser::CurrentRuby.parse(text) }.not_to raise_error }
end

Then('{int} formulas in the sample workbook {string} read {string}') do |count, file, text|
  expect(f5_workbook_formulas(file).count { |formula| formula.include?(text) }).to eq(count)
end

# ---- F5-8 OAuth throttle ---------------------------------------------------------------------------

Then('every OAuth client path Rack::Attack throttles is routed') do
  # Each listed path is a real POST endpoint
  Rack::Attack::OAUTH_CLIENT_PATHS.each do |path|
    expect { Rails.application.routes.recognize_path(path, method: :post) }.not_to raise_error, "#{path} is not routed"
  end
end

Then('Rack::Attack does not list {string} as an OAuth client path') do |path|
  expect(Rack::Attack::OAUTH_CLIENT_PATHS).not_to include(path)
end
