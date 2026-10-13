# Steps for features/fund/evergreen/folio_kyc_orders.feature, folio_kyc_link.feature and
# folio_statements.feature. Every evergreen folio carries an approved KYC; orders record it.
# Worked examples — openspec/changes/evergreen-folio-soa/design.md#worked-examples

def evergreen_kyc_named(investor_name, kyc_name)
  inv = evergreen_investor_named(investor_name)
  InvestorKyc.find_by!(entity_id: inv.entity_id, investor_id: inv.id, full_name: kyc_name)
end

Given('{string} has another approved KYC {string}') do |name, kyc_name|
  inv = evergreen_investor_named(name)
  FactoryBot.create(:investor_kyc, entity: inv.entity, investor: inv, full_name: kyc_name, verified: true)
end

Given('{string} has a pending KYC {string}') do |name, kyc_name|
  inv = evergreen_investor_named(name)
  FactoryBot.create(:investor_kyc, entity: inv.entity, investor: inv, full_name: kyc_name, verified: false)
end

# The setup steps give every investor an approved KYC; this undoes that for the refusal paths
Given('{string} has no approved KYC') do |name|
  inv = evergreen_investor_named(name)
  InvestorKyc.where(entity_id: inv.entity_id, investor_id: inv.id).find_each { |k| k.update_columns(verified: false, submission_status: "not_sent") }
end

# A folio from before folios carried a KYC
Given('folio {string} has no KYC linked') do |folio|
  @fund.capital_commitments.find_by!(folio_id: folio).update_columns(investor_kyc_id: nil)
end

# Like "has placed a … order" but keeps a refusal instead of raising (and, unlike "tries a … order", can pick the KYC); "entity=<KYC name>" picks the investing entity
When('{string} tries to place a {string} order {string} received {string}') do |name, kind, values, received|
  inv = evergreen_investor_named(name)
  kv = evergreen_kv(values)
  folio = @fund.capital_commitments.find_by(folio_id: kv.delete(:folio)) if kv[:folio]
  kyc_id = evergreen_kyc_named(name, kv.delete(:entity)).id if kv[:entity]
  # A KYC of another investor, posted directly (X3)
  kyc_id = evergreen_kyc_named(kv[:other_investor], kv.delete(:other_entity)).id if kv[:other_entity]
  kv.delete(:other_investor)
  params = kv.merge(kind:, investor_id: inv.id, capital_commitment_id: folio&.id, investor_kyc_id: kyc_id, unit_type: kv[:class] || "A", received_at: received)
  # "the order should be refused with" / "accepted" (evergreen_edge_orders_steps.rb) read these
  @orders_before = DealingOrder.count
  @order_result = DealingOrderCreate.call(fund: @fund, params: params.except(:class), current_user: @gp_user || @user, source: "admin")
  @last_order = @order_result[:order] if @order_result.success?
end

Then('the latest order of {string} should be for investing entity {string}') do |name, kyc_name|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(order.investor_kyc&.full_name).to eq(kyc_name)
end

Then('folio {string} should be for investing entity {string}') do |folio, kyc_name|
  expect(@fund.capital_commitments.find_by!(folio_id: folio).investor_kyc&.full_name).to eq(kyc_name)
end

Then('the latest folio of {string} should be for investing entity {string}') do |name, kyc_name|
  folio = @fund.capital_commitments.where(investor: evergreen_investor_named(name)).order(:id).last
  expect(folio).to be_present
  expect(folio.investor_kyc&.full_name).to eq(kyc_name)
end

Then('{string} should have no folio') do |name|
  expect(@fund.capital_commitments.where(investor: evergreen_investor_named(name))).to be_empty
end

Then('the order form should ask for the investing entity with {string}') do |options|
  expect(page).to have_select("order_investor_kyc", with_options: options.split(",").map(&:strip))
end

Then('the order form should not ask for the investing entity') do
  expect(page).to have_no_css("#order_investor_kyc")
end

# The order upload with the sheet's own header row (so optional columns such as "Investing Entity" can be added)
When('I upload the order rows with headers:') do |table|
  path = Rails.root.join("tmp/evergreen_order_upload_#{SecureRandom.hex(4)}.xlsx")
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Orders") do |sheet|
      table.raw.each { |r| sheet.add_row(r) }
    end
    p.serialize(path.to_s)
  end
  @import_upload = ImportUpload.create!(name: "Orders upload", entity_id: @fund.entity_id, owner: @fund, user: @gp_user || @user,
                                        import_type: "DealingOrder", import_file: File.open(path))
  ImportUploadJob.perform_now(@import_upload.id)
  @import_upload.reload
end

# X5: an order that reached dealing with no KYC (data fixed by hand) and an investor with several approved KYCs
Given('the latest order of {string} has no investing entity') do |name|
  DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last.update_columns(investor_kyc_id: nil)
end

When('I choose the investing entity {string}') do |kyc_name|
  select(kyc_name, from: "order_investor_kyc")
end

When('I start a subscription into folio {string}') do |folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  evergreen_visit(new_evergreen_order_path(@fund, kind: "subscription", dealing_order: { capital_commitment_id: cc.id, unit_type: cc.unit_type }))
end

Then('the order of {string} should not be waiting on {string}') do |name, step|
  order = DealingOrder.joins(:investor).where(fund_id: @fund.id, investors: { investor_name: name }).order(:id).last
  expect(OrderJourneyStatus.waiting_on(order)).not_to eq(step)
end

# ---- ③ Link KYC to existing folios ----

# Runs evergreen:link_folio_kycs for the current fund and keeps what it printed
When('the folio KYC link task runs {string}') do |mode|
  Rails.application.load_tasks unless Rake::Task.task_defined?("evergreen:link_folio_kycs")
  env = { "FUND_ID" => @fund.id.to_s, "EXECUTE" => (mode.strip == "with EXECUTE=1" ? "1" : nil) }
  old = env.keys.index_with { |k| ENV.fetch(k, nil) }
  env.each { |k, v| ENV[k] = v }
  out = StringIO.new
  $stdout = out
  Rake::Task["evergreen:link_folio_kycs"].reenable
  Rake::Task["evergreen:link_folio_kycs"].invoke
ensure
  $stdout = STDOUT
  old&.each { |k, v| ENV[k] = v }
  @task_output = out&.string
end

Then('the task output should mention {string}') do |text|
  expect(@task_output).to include(text)
end

Then('folio {string} should have no KYC linked') do |folio|
  expect(@fund.capital_commitments.find_by!(folio_id: folio).investor_kyc_id).to be_nil
end

Then('the investing entity picker should offer {string}') do |options|
  expect(page).to have_select("folio_investor_kyc", options: [""] + options.split(",").map(&:strip))
end

Then('the folio page should have no investing entity picker') do
  expect(page).to have_no_css("#folio_investor_kyc")
end

When('I link the investing entity {string}') do |kyc_name|
  select(kyc_name, from: "folio_investor_kyc")
  click_on("link_kyc")
end

# A request straight to the link action, bypassing the page (X12, X13, X14)
When('a request links folio {string} to the KYC {string} of {string}') do |folio, kyc_name, investor_name|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  page.driver.submit :patch, link_kyc_evergreen_folio_path(@fund, cc), { investor_kyc_id: evergreen_kyc_named(investor_name, kyc_name).id }
end

Given('a read-only employee {string} of the fund') do |name|
  user = FactoryBot.create(:user, entity: @fund.entity, first_name: name)
  user.add_role(:employee) unless user.has_role?(:employee)
  # Fund access with read permission only: permissioned_employee?(:update) is false
  ar = AccessRight.new(owner: @fund, access_type: "Fund", user_id: user.id, entity_id: @fund.entity_id)
  ar.permissions = %i[read]
  ar.save!
  @evergreen_people ||= {}
  @evergreen_people[name] = user
end

When('{string} logs in') do |name|
  evergreen_fresh_login(@evergreen_people.fetch(name))
end

# ---- ④–⑦ Statements ----

Given('the fund has the evergreen statement template {string}') do |name|
  evergreen_doc_template(@fund, name, "SOA Template", "Evergreen Statement Template.docx")
end

Given('folio {string} has its own statement template {string}') do |folio, name|
  evergreen_doc_template(@fund.capital_commitments.find_by!(folio_id: folio), name, "SOA Template", "Evergreen Statement Template.docx")
end

Given("the fund's statement templates are removed") do
  @fund.documents.templates.where(owner_tag: Evergreen::StatementsController::TEMPLATE_TAGS).find_each(&:destroy)
end

# The modal's fields are in the page; rack_test fills the hidden ISO inputs the locale date fields submit
When('I generate statements from {string} to {string}') do |from, to|
  find("input[name='start_date']", visible: :all).set(Date.parse(from).iso8601)
  find("input[name='end_date']", visible: :all).set(Date.parse(to).iso8601)
  click_on("generate_statements")
end

When('I generate statements with template {string} from {string} to {string}') do |template, from, to|
  select(template, from: "statement_template")
  steps %(When I generate statements from "#{from}" to "#{to}")
end

# The statements of a folio for a period (generated document names carry the period, "01 October,2026")
def evergreen_statements(folio, from, to)
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  period = "#{Date.parse(from).strftime('%d %B,%Y')} to #{Date.parse(to).strftime('%d %B,%Y')}"
  Document.where(owner: cc, owner_tag: "Generated").where("name LIKE ?", "%#{period}%")
end

Then('folio {string} should have {string} statement(s) for {string} to {string}') do |folio, count, from, to|
  expect(evergreen_statements(folio, from, to).count).to eq(count.to_i)
end

Then('the statement of folio {string} for {string} to {string} should be generated from {string}') do |folio, from, to, owner|
  doc = evergreen_statements(folio, from, to).last
  expected_owner = owner == "the fund" ? @fund : @fund.capital_commitments.find_by!(folio_id: owner.delete_prefix("folio "))
  expect(doc.from_template.owner).to eq(expected_owner)
end

Then('the statement of folio {string} for {string} to {string} should be a PDF') do |folio, from, to|
  doc = evergreen_statements(folio, from, to).last
  expect(doc.file.metadata["mime_type"] || doc.file.mime_type).to eq("application/pdf")
end

# Documents › Approve: the existing bulk approval (DocumentApprovalJob) for folio documents, with Notify
When('the fund admin approves the generated statements with notification') do
  DocumentApprovalJob.perform_now(@fund.entity_id, (Time.zone.today - 1.year).iso8601, Time.zone.today.iso8601,
                                  { user_id: (@gp_user || @user).id, notification: "1", owner_type: "CapitalCommitment" })
end

Then('the statement of folio {string} for {string} to {string} should be approved') do |folio, from, to|
  expect(evergreen_statements(folio, from, to).last.approved).to be(true)
end

# X8 / X9: a request straight to the generate action
When('a request generates statements for folio {string} with template {string} from {string} to {string}') do |folio, template, from, to|
  cc = folio.present? ? @fund.capital_commitments.find_by!(folio_id: folio) : nil
  tpl = Document.templates.find_by!(name: template)
  @docs_before = Document.where(owner_tag: "Generated").count
  page.driver.submit :post, evergreen_statements_path(@fund),
                     { capital_commitment_id: cc&.id, template_id: tpl.id, start_date: Date.parse(from).iso8601, end_date: Date.parse(to).iso8601 }
end

Then('no statement should have been generated') do
  expect(Document.where(owner_tag: "Generated").count).to eq(@docs_before)
end

Given('another fund {string} has the evergreen statement template {string}') do |fund_name, name|
  other = FactoryBot.create(:fund, entity: @fund.entity, name: fund_name)
  Document.create!(entity_id: other.entity_id, owner: other, name:, owner_tag: "SOA Template", template: true, user: @gp_user || @user,
                   file: Rails.public_path.join("sample_uploads", "Evergreen Statement Template.docx").open("rb"))
end

Then('{string} should have received a document email') do |name|
  user = @investor_users.fetch(name)
  expect(ActionMailer::Base.deliveries.any? { |m| Array(m.to).include?(user.email) }).to be(true)
end

Then('the statement of folio {string} for {string} to {string} should have no closing NAV') do |folio, from, to|
  ctx = EvergreenStatement.new(@fund.capital_commitments.find_by!(folio_id: folio), Date.parse(from), Date.parse(to)).context
  expect(ctx["closing_nav_per_unit"]).to be_nil
  expect(ctx["closing_value"]).to be_nil
end

Then('the Generate button should be disabled') do
  expect(page).to have_button("generate_statements", disabled: true)
end

Then('the Generate statement button should be disabled') do
  expect(page).to have_button("generate_statement_open", disabled: true)
end

# The rows a template's evergreen.transactions:each(t) loop prints (dealing date, type, units, NAV per unit, amount)
Then('the statement transactions of folio {string} for {string} to {string} should be:') do |folio, from, to, table|
  t = EvergreenStatement.new(@fund.capital_commitments.find_by!(folio_id: folio), Date.parse(from), Date.parse(to)).template_context
  rows = t.transactions.map { |r| [r.dealing_date.iso8601, r.kind, r.format_4_units, r.money_nav_per_unit, r.money_amount] }
  expect(rows).to eq(table.rows)
end

# ---- NAV from the fund's real portfolio (no fair-value stub) ----

# A portfolio company of the fund's entity with one equity instrument
def evergreen_portfolio_company(name)
  pc = @fund.entity.investors.portfolio_companies.find_by(investor_name: name)
  return pc if pc

  steps %(Given there is an existing portfolio company "name=#{name};category=Portfolio Company")
  pc = @fund.entity.investors.portfolio_companies.find_by!(investor_name: name)
  FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: pc, name: "#{name} Equity", currency: @fund.currency)
  pc
end

def evergreen_instrument(pc)
  InvestmentInstrument.find_by!(portfolio_company_id: pc.id)
end

# Buys (positive) or sells (negative) through PortfolioInvestmentCreate, as a portfolio upload would
Given('the fund {string} {string} shares of {string} on {string} for {string}') do |action, quantity, company, date, amount|
  pc = evergreen_portfolio_company(company)
  qty = quantity.delete(",").to_d * (action == "sells" ? -1 : 1)
  pi = FactoryBot.build(:portfolio_investment, entity: @fund.entity, fund: @fund, portfolio_company: pc, investment_instrument: evergreen_instrument(pc),
                                               investment_date: Date.parse(date), quantity: qty, ex_expenses_base_amount_cents: evergreen_cents(amount))
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "portfolio investment failed: #{pi.errors.full_messages.to_sentence}" unless result.success?
end

Given('{string} is valued at {string} a share on {string}') do |company, per_share, date|
  pc = evergreen_portfolio_company(company)
  FactoryBot.create(:valuation, entity: @fund.entity, owner: pc, investment_instrument: evergreen_instrument(pc), valuation_date: Date.parse(date),
                                per_share_value_cents: evergreen_cents(per_share), valuation_cents: evergreen_cents(per_share) * 1000)
end
