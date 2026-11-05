# frozen_string_literal: true

# Steps for features/security/mcp_tenant_isolation.feature.
#
# Why the tools are called as classes, not through POST /mcp: McpController#create authenticates the
# bearer token, applies entity governance, and then calls exactly `Tool.call(server_context: { user:,
# entity: }, **args)`. Token and governance checks have their own features. This feature is about the
# step after that: which rows a tool hands back. Calling the class keeps each scenario about that
# one question, and keeps the setup to two firms instead of OAuth clients, tokens and grants.

module McpIsolationHelpers
  # Firms built by "a fund firm ... with the fund ... and LPs ...", by name:
  #   { entity:, admin:, fund:, document:, portfolio_company: }
  def mcp_firms
    @mcp_firms ||= {}
  end

  def mcp_tool_klass(tool_name)
    "#{tool_name.camelize}Tool".constantize
  end

  # Calls a tool the way McpController does and parses the JSON text it returns.
  def call_mcp_tool(tool_name, **args)
    response = mcp_tool_klass(tool_name).call(server_context: { user: @mcp_user, entity: @mcp_user.entity }, **args)
    @mcp_answer = JSON.parse(response.content.first[:text])
  end

  # The model a list tool reads, from the tool's ontology file (the same source the tool uses).
  def mcp_tool_model(tool_name)
    McpOntology.tool(tool_name).entity.model_name.constantize
  end

  # Ids of the rows a list tool returned. Fails loudly on an error answer, which would otherwise
  # make every "no foreign rows" check pass by returning nothing.
  def mcp_row_ids
    expect(@mcp_answer).to be_an(Array), "Expected rows from #{@mcp_tool}, got: #{@mcp_answer.inspect[0, 300]}"
    @mcp_answer.map { |row| row.fetch("id") }
  end

  # The investor of a firm's fund with this name, and its user.
  def investor_named(name)
    Investor.find_by!(investor_name: name)
  end

  def lp_user_of(name)
    InvestorAccess.where(investor: investor_named(name)).first!.user
  end

  # The text that identifies each record type in an MCP answer. All names are unique in this feature.
  def identifying_text(firm_name, record)
    firm = mcp_firms.fetch(firm_name)
    case record
    when "fund" then firm[:fund].name
    when "commitment" then firm[:fund].capital_commitments.first!.investor_name
    when "document" then firm[:document].name
    when "portfolio company" then firm[:portfolio_company].investor_name
    end
  end

  def record_id(firm_name, record)
    firm = mcp_firms.fetch(firm_name)
    case record
    when "fund" then { fund_id: firm[:fund].id }
    when "commitment" then { commitment_id: firm[:fund].capital_commitments.first!.id }
    when "document" then { document_id: firm[:document].id }
    when "portfolio company" then { portfolio_company_id: firm[:portfolio_company].id }
    end
  end
end
World(McpIsolationHelpers)

# ---- Setup --------------------------------------------------------------------------------------

# Builds one complete fund firm with the app's own setup steps, so both firms in the feature have the
# same kinds of rows: commitments, a call (whose remittances are generated inline), a distribution,
# fund and folio account entries, a fund document and a portfolio company.
Given("a fund firm {string} with the fund {string} and LPs {string}") do |firm_name, fund_name, lp_names|
  investor_steps = lp_names.split(",").map(&:strip).map do |lp|
    %(Given there is an existing investor "investor_name=#{lp}" with "1" users)
  end.join("\n")
  steps %(
    Given there is a user "first_name=Admin" for an entity "name=#{firm_name};entity_type=Investment Fund;enable_funds=true"
    And the user has role "company_admin"
    And there is a fund "name=#{fund_name};currency=INR" for the entity
    #{investor_steps}
    And the investors are added to the fund
    And there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And there is a capital call "percentage_called=20"
    And there is a capital distribution "title=#{firm_name} Q1 Distribution"
  )

  # Account entries: one per folio plus one fund-level entry (no commitment), the two shapes the
  # ledger has.
  @fund.capital_commitments.each do |commitment|
    FactoryBot.create(:account_entry, entity: @entity, fund: @fund, capital_commitment: commitment,
                                      investor: commitment.investor, folio_id: commitment.folio_id,
                                      reporting_date: Time.zone.today, entry_type: "Expense", name: "Management Fee")
  end
  FactoryBot.create(:account_entry, entity: @entity, fund: @fund, reporting_date: Time.zone.today,
                                    folio_id: nil, entry_type: "Expense", name: "Audit Fee")

  # A fund document with a name unique to this firm, for the by-id and by-name lookups.
  folder = Folder.where(entity: @entity).first || FactoryBot.create(:folder, entity: @entity)
  document = FactoryBot.create(:document, entity: @entity, folder:, owner: @fund, user: @user,
                                          name: "#{firm_name} side letter")

  # A portfolio company, created after the commitments so it gets no folio.
  # (Same argument shape as the 67 existing uses: the entity name becomes the investor_name.)
  steps %(Given there is an existing portfolio company "name=#{firm_name} Portco;category=Portfolio Company")

  mcp_firms[firm_name] = { entity: @entity, admin: @user, fund: @fund, document:, portfolio_company: @portfolio_company }
end

Given("I act over MCP as Artha's company admin") do
  @mcp_user = mcp_firms.fetch("Artha")[:admin]
end

Given("I act over MCP as the LP user of {string}") do |lp_name|
  @mcp_user = lp_user_of(lp_name)
  # Investor users act in the investor role; set it as the KYC magic-link steps do.
  @mcp_user.update!(curr_role: "investor") unless @mcp_user.curr_role == "investor"
end

# ---- Calls --------------------------------------------------------------------------------------

# Asks for every fund in the system, the caller's AND the other firm's, by id. That is what an
# attacker would actually send: list tools over large tables (remittances, …) reject a call with no
# filter at all, and a fund_ids filter naming another firm's fund is the obvious way to reach its rows.
# Tools without a fund_ids argument (list_funds, list_portfolio_companies) are called unfiltered.
When("I call the {string} MCP tool for every fund, mine and Zeta's") do |tool_name|
  @mcp_tool = tool_name
  takes_fund_ids = mcp_tool_klass(tool_name).method(:call).parameters.any? { |_kind, name| name == :fund_ids }
  args = takes_fund_ids ? { fund_ids: mcp_firms.values.map { |firm| firm[:fund].id } } : {}
  call_mcp_tool(tool_name, **args)
end

When("I call the {string} MCP tool for Zeta Capital's {}") do |tool_name, record|
  call_mcp_tool(tool_name, **record_id("Zeta Capital", record))
end

When("I call the {string} MCP tool for Artha's {}") do |tool_name, record|
  call_mcp_tool(tool_name, **record_id("Artha", record))
end

When("I call get_document by the name of Zeta Capital's document") do
  call_mcp_tool("get_document", name: mcp_firms.fetch("Zeta Capital")[:document].name)
end

When("I count account entries over MCP") do
  call_mcp_tool("list_account_entries", aggregate: "count")
end

When("I call get_commitment_details for {word}'s commitment") do |lp_name|
  commitment = CapitalCommitment.find_by!(investor: investor_named(lp_name))
  call_mcp_tool("get_commitment_details", commitment_id: commitment.id)
end

# ---- Assertions ---------------------------------------------------------------------------------

Then("every row it returns belongs to {string}") do |firm_name|
  model = mcp_tool_model(@mcp_tool)
  foreign = model.where(id: mcp_row_ids).where.not(entity_id: mcp_firms.fetch(firm_name)[:entity].id)
  expect(foreign.pluck(:id)).to be_empty, "#{@mcp_tool} returned #{model} rows of another firm: #{foreign.pluck(:id)}"
end

Then("it returns at least one of Artha's rows") do
  expect(mcp_row_ids).not_to be_empty, "#{@mcp_tool} returned no rows for Artha's admin, so the isolation check proves nothing"
end

Then("it returns none of {string}'s rows, although Zeta has some") do |firm_name|
  model = mcp_tool_model(@mcp_tool)
  theirs = model.where(entity_id: mcp_firms.fetch(firm_name)[:entity].id)
  expect(theirs).to exist, "Precondition: #{firm_name} has no #{model} rows, so this check would prove nothing"
  expect(mcp_row_ids & theirs.pluck(:id)).to be_empty
end

Then("the MCP answer does not reveal Zeta Capital's {}") do |record|
  expect(@mcp_answer.to_json).not_to include(identifying_text("Zeta Capital", record))
end

Then("the MCP answer names Artha's {}") do |record|
  expect(@mcp_answer.to_json).to include(identifying_text("Artha", record))
end

Then("the count equals Artha's own account entries, not including Zeta's") do
  artha = AccountEntry.where(entity_id: mcp_firms.fetch("Artha")[:entity].id).count
  zeta = AccountEntry.where(entity_id: mcp_firms.fetch("Zeta Capital")[:entity].id).count
  expect(zeta).to be_positive, "Precondition: Zeta has no account entries, so the count proves nothing"
  expect(@mcp_answer).to eq("count" => artha)
end

Then("it returns at least one of Kiran's rows") do
  model = mcp_tool_model(@mcp_tool)
  expect(model.where(id: mcp_row_ids, investor_id: investor_named("Kiran").id)).to exist,
                                                                                   "#{@mcp_tool} returned none of Kiran's own rows, so the isolation check proves nothing"
end

Then("every row it returns is Kiran's, none Meera's") do
  model = mcp_tool_model(@mcp_tool)
  meera_rows = model.where(investor_id: investor_named("Meera").id)
  expect(meera_rows).to exist, "Precondition: Meera has no #{model} rows, so this check would prove nothing"
  others = model.where(id: mcp_row_ids).where.not(investor_id: investor_named("Kiran").id)
  expect(others.pluck(:id)).to be_empty, "#{@mcp_tool} returned another LP's #{model} rows: #{others.pluck(:id)}"
end

Then("the MCP answer does not reveal Meera's commitment") do
  expect(@mcp_answer.to_json).not_to include("Meera")
end

Then("the MCP answer names Kiran's commitment") do
  expect(@mcp_answer.to_json).to include("Kiran")
end
