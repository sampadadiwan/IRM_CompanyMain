# Steps for the 2026-10 security review items implemented after the first passes: M10 (secondaries
# part: the offers / interests report names), the unscoped sale lookups flagged after H11 (SL-*),
# M11 (allocation create and update), M16 (report builder scope) and L14 (`*_type` request params).
# Design and worked examples: docs/security/security_review_2026_10.md (C4 card, H11 card, the M10 /
# M11 rows of the secondaries table, and the M16 / L14 rows of "Core / misc — Medium and Low").
#
# Scenarios: features/security/secondaries_isolation.feature (M10, SL, M11),
# features/security/security_review_2026_10_medium.feature (M16) and
# features/security/security_review_2026_10_low.feature (L14).
#
# Reused helpers: sr_request / sr_sign_in (security_c4_c7_h16_l10_steps.rb), the sale parties
# sec_offer_of / sec_interest_of / sec_allocations / sec_foreign_sales
# (security_h8_h11_h14_h15_h19_steps.rb), and the named firms and people cma_firm / cma_user /
# cma_request (security_core_medium_a_steps.rb).

module SecurityDeferredHelpers
  # ---- M16 ------------------------------------------------------------------------------------

  # The engine rows of the last report run, and the users the export job built the engine for
  def sdf_rows
    @sdf_rows ||= []
  end

  # A report-builder report of `firm` owned by `owner`, on `root_model`, showing `columns` (GVP keys).
  # `joins` / `aggregates` follow the template JSON the builder writes.
  def sdf_report(firm, owner, root_model, columns, joins: [], aggregates: {})
    report = Report.create!(entity: firm, user: owner, name: "M16 #{root_model} #{SecureRandom.hex(3)}",
                            report_builder: true, url: "/report_builder", curr_role: "employee",
                            template: { version: 1, root_model:, joins:, aggregates:, root_filters: {}, sort: {} })
    # One grid column per key, in order, as "Add column" makes them
    columns.each_with_index do |key, index|
      report.grid_view_preferences.create!(key:, name: key.humanize, label: key.humanize,
                                           entity_id: firm.id, sequence: index + 1)
    end
    report
  end

  # Runs `report` through the query engine for `user`, the way the report page does
  def sdf_run(report, user)
    @sdf_rows = ReportBuilderQueryEngine.new(report:, entity: report.entity, user:).run
  end

  # Records the user each ReportBuilderQueryEngine is built for, then stops the job there (the job
  # rescues the error and alerts), as TenantIsolationHelpers#capture_report_entity does for the entity
  def sdf_capture_engine_user
    @sdf_engine_users = []
    allow(ReportBuilderQueryEngine).to receive(:new) do |user:, **|
      @sdf_engine_users << user&.id
      raise TenantIsolationHelpers::Captured
    end
  end
end
World(SecurityDeferredHelpers)

# ==== M10 — the sale's offers / interests reports ==============================================

When("the sale's company admin opens the sale's {string} with report {string}") do |list, report|
  sr_sign_in(@user)
  # Literal path: the same address the Reports menu links to, with the crafted report name
  sr_request(:get, "/secondary_sales/#{@sale.id}/#{list}", report:)
end

# ==== SL — sale lookups through the user's scope ===============================================

When("the sale's {string} lists the interests of the sale {string}") do |party, sale_name|
  sr_sign_in(@c4_parties.fetch(party))
  sr_request(:get, interests_path(secondary_sale_id: sec_foreign_sales.fetch(sale_name).id))
end

When("the sale's {string} lists the offers of the sale {string}") do |party, sale_name|
  sr_sign_in(@c4_parties.fetch(party))
  sr_request(:get, offers_path(secondary_sale_id: sec_foreign_sales.fetch(sale_name).id))
end

When("the sale's {string} searches the offers of the sale {string} for {string}") do |party, sale_name, query|
  sr_sign_in(@c4_parties.fetch(party))
  # The search box sends the sale id and the query; the sale is resolved before any index lookup
  sr_request(:get, search_offers_path(secondary_sale_id: sec_foreign_sales.fetch(sale_name).id, query:))
end

When("the sale's {string} lists the interests of the sale") do |party|
  sr_sign_in(@c4_parties.fetch(party))
  sr_request(:get, interests_path(secondary_sale_id: @sale.id))
end

# ==== M11 — allocation create and update =======================================================

When('I create an allocation of {int} shares from the offer of {string} to the interest of {string}') do |quantity, seller, buyer|
  # The new-allocation form's fields, posted as whoever is signed in now. secondary_sale_id is the
  # form's hidden field; create ignores it and takes the sale from the offer
  sr_request(:post, allocations_path,
             allocation: { offer_id: sec_offer_of(seller).id, interest_id: sec_interest_of(buyer).id,
                           secondary_sale_id: @sale.id, quantity:, price: @sale.min_price })
end

When('I create an allocation of {int} shares from the offer of {string} to the interest of {string} naming the sale {string}') do |quantity, seller, buyer, sale_name|
  # The attack M11 closes: the stand-in was authorized on the caller's own sale, then rebuilt from the
  # other firm's offer and saved into that firm's sale
  sr_request(:post, allocations_path,
             allocation: { offer_id: sec_offer_of(seller).id, interest_id: sec_interest_of(buyer).id,
                           secondary_sale_id: sec_foreign_sales.fetch(sale_name).id, quantity:,
                           price: @sale.min_price })
end

When("the sale's company admin creates an allocation of {int} shares from the offer of {string} to the interest of {string}") do |quantity, seller, buyer|
  sr_sign_in(@user)
  step %(I create an allocation of #{quantity} shares from the offer of "#{seller}" to the interest of "#{buyer}")
end

Then('there is no allocation from the offer of {string} to the interest of {string}') do |seller, buyer|
  expect(Allocation.where(offer_id: sec_offer_of(seller).id, interest_id: sec_interest_of(buyer).id)).not_to exist
end

Then("the sale has an allocation of {int} shares from the offer of {string} to the interest of {string}") do |quantity, seller, buyer|
  offer = sec_offer_of(seller)
  allocation = Allocation.find_by!(offer_id: offer.id, interest_id: sec_interest_of(buyer).id)
  # In the offer's sale and firm, with the quantity asked for
  expect(allocation.secondary_sale_id).to eq(@sale.id)
  expect(allocation.entity_id).to eq(offer.entity_id)
  expect(allocation.quantity.to_d).to eq(quantity.to_d)
end

When("the sale's company admin updates the allocation {string} with the offer of {string}, the interest of {string} and the notes {string}") do |pair, seller, buyer, notes|
  sr_sign_in(@user)
  allocation = sec_allocations.fetch(pair)
  # Every key the old permit list let through, pointed elsewhere, plus a field that may change
  sr_request(:patch, allocation_path(allocation),
             allocation: { offer_id: sec_offer_of(seller).id, interest_id: sec_interest_of(buyer).id,
                           entity_id: sec_offer_of(seller).investor.investor_entity_id, notes: })
end

Then('the allocation {string} is still from the offer of {string} to the interest of {string} with the notes {string}') do |pair, seller, buyer, notes|
  allocation = sec_allocations.fetch(pair).reload
  expect(allocation.offer_id).to eq(sec_offer_of(seller).id)
  expect(allocation.interest_id).to eq(sec_interest_of(buyer).id)
  expect(allocation.secondary_sale_id).to eq(@sale.id)
  expect(allocation.entity_id).to eq(@sale.entity_id)
  expect(allocation.notes.to_s).to eq(notes)
end

# ==== M16 — report builder scope ===============================================================

Given('{string} has a fund {string} with a commitment of the investor {string}') do |firm_name, fund_name, investor_name|
  firm = cma_firm(firm_name)
  # The fund and the stakeholder, created once and reused across steps
  fund = Fund.find_by(entity: firm, name: fund_name) || FactoryBot.create(:fund, entity: firm, name: fund_name)
  investor = Investor.find_by(entity: firm, investor_name:) || cma_create_investor(firm, investor_name)
  FactoryBot.create(:capital_commitment, fund:, entity: firm, investor:)
end

Given('{string} has access to the fund {string} only') do |first_name, fund_name|
  user = cma_user(first_name)
  # The employee grant the fund's Access tab creates
  AccessRight.create!(owner: Fund.find_by!(name: fund_name), entity_id: user.entity_id, user_id: user.id, notify: false)
end

Given('{string} may read every stakeholder of the firm') do |first_name|
  user = cma_user(first_name)
  # The investor_read extended permission: InvestorPolicy::Scope then lists every stakeholder
  user.extended_permissions.set(:investor_read)
  user.save!
end

When('{string} runs a report of {string} with the column {string}') do |first_name, root_model, column|
  user = cma_user(first_name)
  @sdf_report = sdf_report(user.entity, user, root_model, [column])
  sdf_run(@sdf_report, user)
end

When('{string} runs a report of {string} with the column {string} and the count of {string}') do |first_name, root_model, column, relation|
  user = cma_user(first_name)
  # One join with a count aggregate on the child id, as "+ Add related data" then "count" writes it
  @sdf_report = sdf_report(user.entity, user, root_model, [column, "#{relation}.id"],
                           joins: [{ relation:, model: relation.classify }],
                           aggregates: { "#{relation}.id" => "count" })
  sdf_run(@sdf_report, user)
end

Then('the report lists {string} under {string}') do |values, column|
  expected = values.split(",").map(&:strip)
  expect(sdf_rows.map { |row| row[column].to_s }).to match_array(expected)
end

Then('the report row of {string} counts {int} {string}') do |name, count, relation|
  row = sdf_rows.find { |r| r.values.map(&:to_s).include?(name) }
  expect(row).to be_present, "no report row for #{name}"
  expect(row["#{relation}.id"].to_i).to eq(count)
end

Then('a report-builder report of {string} on {string} is refused') do |firm_name, root_model|
  firm = cma_firm(firm_name)
  report = Report.new(entity: firm, user: User.find_by!(entity: firm), name: "Crafted root",
                      report_builder: true, url: "/report_builder", curr_role: "employee",
                      template: { version: 1, root_model:, joins: [], aggregates: {} })
  # The save the builder's create / update_template make is refused, with the reason on the template
  expect(report.save).to be(false)
  expect(report.errors[:template].join).to include("not available for reports")
end

Then('a stored report on {string} returns no rows for {string}') do |root_model, first_name|
  user = cma_user(first_name)
  # A row written before the validation existed (or past it): the engine still runs nothing
  report = Report.new(entity: user.entity, user:, name: "Legacy root", report_builder: true, url: "/report_builder",
                      curr_role: "employee", template: { version: 1, root_model:, joins: [], aggregates: {} })
  report.save!(validate: false)
  engine = ReportBuilderQueryEngine.new(report:, entity: user.entity, user:)
  expect(engine.run).to eq([])
  expect(engine.count).to eq(0)
end

Given('{string} owns a scheduled report-builder report of {string}') do |first_name, root_model|
  owner = cma_user(first_name)
  @sdf_report = sdf_report(owner.entity, owner, root_model, ["id"])
  @sdf_schedule = ReportSchedule.new(report: @sdf_report, frequency: "daily", recipients: ["ops@alpha.example"])
  @sdf_schedule.save(validate: false)
end

When('the scheduled export of the report runs') do
  sdf_capture_engine_user
  # As ReportBuilderSchedulerJob enqueues it
  ReportBuilderExportJob.perform_now(@sdf_report.id, @sdf_report.user_id, @sdf_schedule.id)
end

When('{string} exports the report on demand') do |first_name|
  sdf_capture_engine_user
  # As report_builder#export enqueues it for the requesting user
  ReportBuilderExportJob.perform_now(@sdf_report.id, cma_user(first_name).id)
end

Then('the report rows were read as {string}') do |first_name|
  expect(@sdf_engine_users).to eq([cma_user(first_name).id])
end

# ==== L14 — `*_type` request params ============================================================

When('they send a {string} request to {string}') do |method, address|
  # Literal address, as a crafted link or form would send it
  cma_request(method.downcase.to_sym, address)
end

When('they open the tasks board for the investor {string}') do |investor_name|
  investor = Investor.find_by!(investor_name:)
  cma_request(:get, tasks_path(board: true, owner_type: "Investor", owner_id: investor.id))
end

When('they open the notes of the investor {string}') do |investor_name|
  investor = Investor.find_by!(investor_name:)
  cma_request(:get, notes_path(owner_type: "Investor", owner_id: investor.id))
end
