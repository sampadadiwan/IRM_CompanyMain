# frozen_string_literal: true

# Report Builder you can trust — shared "Acme" data and engine/HTTP steps.
# Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples
#
# Amounts are forced with update_columns once every row exists, so a model
# callback that recomputes an amount can't make a scenario check the wrong figure.

ACME_CRORE = 10_000_000 * 100 # one crore in paise

module ReportBuilderTrustWorld
  def acme
    @acme ||= {}
  end

  def crore(value)
    (value.to_d * ACME_CRORE).to_i
  end

  # Builds the design's shared setup: Acme Capital, two funds, four investors,
  # commitments C1–C4, KYCs K1–K2, one call with remittances R1–R4 and payments P1–P2.
  def build_acme_data
    @entity = build_fund_entity(name: "Acme Capital")
    @user   = FactoryBot.create(:user, entity: @entity, first_name: "Meera", permissions: User.permissions.keys)
    # M16 — the engine lists only the rows in the user's Pundit scope; as the firm's company admin
    # Meera sees every row of Acme, which is what the scenarios assert on
    @user.add_role(:company_admin)
    acme[:meera] = @user

    # Funds
    acme[:gf2]    = FactoryBot.create(:fund, entity: @entity, name: "Growth Fund II", currency: "INR", unit_types: "A,B")
    acme[:global] = FactoryBot.create(:fund, entity: @entity, name: "Global Fund", currency: "USD", unit_types: "A")

    # Investors
    { aditi: ["Aditi Rao", "LP"], kiran: ["Kiran Mehta", "LP"], zeta: ["Zeta Holdings", "Co-Investor"], nova: ["Nova LP", "LP"] }.each do |sym, (name, category)|
      investor = build_investor(entity: @entity, name: name)
      investor.update_columns(category: category)
      acme[sym] = investor
    end

    # The call comes first, so creating commitments doesn't generate remittances for it
    acme[:call] = FactoryBot.create(:capital_call, fund: acme[:gf2], entity: @entity, name: "Call 1 — GF2",
                                                   call_date: Date.new(2026, 2, 1), due_date: Date.new(2026, 2, 22))
    acme[:call].update_column(:approved, true)
    # A commitment has one remittance per call, so R2 (C1's second remittance) is on a second call
    acme[:call2] = FactoryBot.create(:capital_call, fund: acme[:gf2], entity: @entity, name: "Call 2 — GF2",
                                                    call_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 3, 22))
    acme[:call2].update_column(:approved, true)

    # Commitments C1–C4: [investor, fund, committed, called, collected, onboarding, unit, date] (in crore; C4 in USD lakh/10)
    {
      c1: [:aditi, :gf2, 5, 2, 1.8, true, "A", Date.new(2026, 1, 15)],
      c2: [:kiran, :gf2, 2.5, 1, 1, false, "A", Date.new(2026, 2, 10)],
      c3: [:zeta, :gf2, 1, 0.4, 0, true, "B", Date.new(2026, 3, 5)],
      c4: [:aditi, :global, 0.1, 0.04, 0.04, false, "A", Date.new(2026, 4, 1)]
    }.each_with_index do |(sym, (inv, fund, committed, _called, _collected, _onb, _unit, date)), idx|
      acme[sym] = FactoryBot.create(:capital_commitment, fund: acme[fund], entity: @entity, investor: acme[inv],
                                                         folio_id: "F-#{idx + 1}", commitment_date: date,
                                                         orig_folio_committed_amount_cents: crore(committed), folio_committed_amount_cents: crore(committed),
                                                         orig_committed_amount_cents: crore(committed), committed_amount_cents: crore(committed))
    end

    # KYCs K1 (Aditi, on C1) and K2 (Kiran, on C2)
    acme[:k1] = FactoryBot.create(:investor_kyc, entity: @entity, investor: acme[:aditi], full_name: "Aditi Rao Family Trust", verified: true)
    acme[:k2] = FactoryBot.create(:investor_kyc, entity: @entity, investor: acme[:kiran], full_name: "Mehta HUF", verified: false)

    # Remittances R1–R4: [commitment, call, called] (crore); statuses and collections are pinned below
    { r1: [:c1, :call, 1], r2: [:c1, :call2, 1], r3: [:c2, :call, 1], r4: [:c3, :call, 0.4] }.each do |sym, (c, call, called)|
      commitment = acme[c]
      acme[sym] = FactoryBot.create(:capital_remittance, fund: acme[:gf2], entity: @entity, capital_call: acme[call],
                                                         capital_commitment: commitment, investor: commitment.investor,
                                                         folio_id: commitment.folio_id, folio_committed_amount_cents: commitment.folio_committed_amount_cents,
                                                         call_amount_cents: crore(called), folio_call_amount_cents: crore(called),
                                                         collected_amount_cents: 0, folio_collected_amount_cents: 0,
                                                         verified: false, remittance_date: Date.new(2026, 2, 1), status: "Pending")
    end

    # Payments P1 (R1) and P2 (R2)
    { p1: [:r1, 1, Date.new(2026, 3, 1), "UTR001"], p2: [:r2, 0.8, Date.new(2026, 4, 1), "UTR002"] }.each do |sym, (r, amount, date, ref)|
      acme[sym] = FactoryBot.create(:capital_remittance_payment, fund: acme[:gf2], entity: @entity, capital_remittance: acme[r],
                                                                 folio_amount_cents: crore(amount), amount_cents: crore(amount),
                                                                 payment_date: date, reference_no: ref)
    end

    force_acme_figures
  end

  # Pins every figure the scenarios check to the design's shared-setup values
  def force_acme_figures
    # Any remittance a callback generated on top of R1–R4 would distort totals
    CapitalRemittance.where(capital_call_id: [acme[:call].id, acme[:call2].id]).where.not(id: %i[r1 r2 r3 r4].map { |s| acme[s].id }).delete_all

    {
      c1: [5, 2, 1.8, true, "A", :k1, "First Close"], c2: [2.5, 1, 1, false, "A", :k2, "First Close"],
      c3: [1, 0.4, 0, true, "B", nil, "Second Close"], c4: [0.1, 0.04, 0.04, false, "A", nil, "First Close"]
    }.each do |sym, (committed, called, collected, onboarding, unit, kyc, close)|
      acme[sym].update_columns(committed_amount_cents: crore(committed), call_amount_cents: crore(called),
                               collected_amount_cents: crore(collected), onboarding_completed: onboarding,
                               unit_type: unit, fund_close: close, investor_kyc_id: kyc && acme[kyc].id)
    end

    { r1: ["Paid", 1, 1], r2: ["Overdue", 1, 0.8], r3: ["Paid", 1, 1], r4: ["Pending", 0.4, 0] }.each do |sym, (status, called, collected)|
      acme[sym].update_columns(status: status, call_amount_cents: crore(called), collected_amount_cents: crore(collected))
    end
  end

  # Report "LPs": investors with capital commitments limited to Growth Fund II
  def build_lps_report(columns: %w[investor_name category])
    report = build_report(entity: @entity, user: @user, root_model: "Investor",
                          columns: columns.map { |k| { key: k } },
                          joins: [{ relation: "capital_commitments", model: "CapitalCommitment",
                                    child_filters: { "fund_id_eq" => acme[:gf2].id.to_s } }])
    report.update!(name: "LPs")
    report
  end

  # Adds a join for a dotted relation path, using the model at the end of the path
  def add_report_join(report, relation)
    klass = report.root_class
    relation.split(".").each { |part| klass = klass.reflect_on_association(part.to_sym).klass }
    tmpl = report.template.deep_stringify_keys
    tmpl["joins"] = (tmpl["joins"] || []) + [{ "relation" => relation, "model" => klass.name }]
    report.update!(template: tmpl)
  end

  def add_report_column(report, key)
    report.grid_view_preferences.create!(key: key, name: key.split(".").last.humanize, label: key.split(".").last.humanize,
                                         entity_id: report.entity_id, sequence: report.grid_view_preferences.count + 1)
  end

  def run_report(report)
    @engine = ReportBuilderQueryEngine.new(report: report.reload, entity: report.entity, user: report.user)
    @rows = @engine.run
  end

  # Compares numerically when the expectation looks like a number, else as text
  def expect_cell(actual, expected)
    if expected.match?(/\A-?[\d.]+\z/) && !actual.nil?
      value = actual.respond_to?(:to_d) ? actual.to_d : BigDecimal(actual.to_s)
      expect(value).to eq(BigDecimal(expected))
    else
      expect(actual.to_s).to eq(expected)
    end
  end

  def row_where(column, value)
    row = @rows.find { |r| r[column].to_s == value }
    expect(row).not_to be_nil, "no row with #{column} = #{value}; rows: #{@rows.pluck(column).inspect}"
    row
  end
end

World(ReportBuilderTrustWorld)

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

Given("the Acme report builder data") do
  build_acme_data
end

Given("I am signed in as Meera") do
  rb_sign_in(acme[:meera])
end

Given("the Acme report {string}") do |name|
  raise "unknown Acme report #{name}" unless name == "LPs"

  @report = build_lps_report
end

Given("a(n) {string} report with columns {string}") do |root_model, keys|
  @report = build_report(entity: @entity, user: @user, root_model: root_model,
                         columns: keys.split(",").map { |k| { key: k.strip } })
end

Given("the report has related data {string}") do |relation|
  add_report_join(@report, relation)
end

Given("the report also shows {string}") do |key|
  add_report_column(@report, key)
end

# ─────────────────────────────────────────────────────────────────────────────
# Running the report
# ─────────────────────────────────────────────────────────────────────────────

When("I run the report") do
  run_report(@report)
end

Then("the row where {string} is {string} shows {string} in {string}") do |key_col, key_val, expected, column|
  expect_cell(row_where(key_col, key_val)[column], expected)
end

Then("the row where {string} is {string} is blank in {string}") do |key_col, key_val, column|
  expect(row_where(key_col, key_val)[column]).to be_blank
end

# ─────────────────────────────────────────────────────────────────────────────
# Totals over HTTP
# ─────────────────────────────────────────────────────────────────────────────

When("I add the column {string} to the report over HTTP") do |key|
  rb_session.post "/report_builder/#{@report.id}/columns", params: { key: key, name: key.split(".").last.humanize }
  @last_rb_response = rb_session.response
end

Then("the stored total for {string} is {string}") do |key, agg|
  expect(ReportBuilderConfig.new(@report.reload.template).aggregate_for(key)).to eq(agg)
end

Then("no total is stored for {string}") do |key|
  expect(ReportBuilderConfig.new(@report.reload.template).aggregate_for(key)).to be_nil
end

Given("the report stores the total {string} for {string}") do |agg, key|
  tmpl = @report.template.deep_stringify_keys
  tmpl["aggregates"] = (tmpl["aggregates"] || {}).merge(key => agg)
  @report.update!(template: tmpl)
end

When("I set the total for {string} to {string} over HTTP") do |key, agg|
  rb_patch "/report_builder/#{@report.id}/aggregate", params: { key: key, aggregate: agg }
end

Then("the request is refused with status {int}") do |status|
  expect(@last_rb_response.status).to eq(status)
end

# ─────────────────────────────────────────────────────────────────────────────
# Column catalog
# ─────────────────────────────────────────────────────────────────────────────

Then("the {string} column list includes {string}") do |model, key|
  expect(ReportBuilderColumnCatalog.columns_for(model.constantize).pluck(:key)).to include(key)
end

Then("the {string} column list does not include {string}") do |model, key|
  expect(ReportBuilderColumnCatalog.columns_for(model.constantize).pluck(:key)).not_to include(key)
end

Then("the {string} filter list includes {string}") do |model, key|
  expect(ReportBuilderColumnCatalog.filter_columns_for(model.constantize).pluck(:key)).to include(key)
end

Then("the related column list for {string} does not include {string}") do |model, key|
  expect(ReportBuilderColumnCatalog.related_columns_for(model.constantize).pluck(:key)).not_to include(key)
end

Then("the related column list for {string} includes {string}") do |model, key|
  expect(ReportBuilderColumnCatalog.related_columns_for(model.constantize).pluck(:key)).to include(key)
end

# E14 — every column offered on any reportable table can be read on its rows,
# and every plain-text reader names a real association to preload
Then("every offered root column of every reportable table is readable") do
  problems = []
  ReportBuilderModelDiscovery.roots.each do |klass|
    probe = klass.new
    ReportBuilderColumnCatalog.columns_for(klass).each do |col|
      next if probe.respond_to?(col[:key]) || ReportBuilderColumnCatalog::READERS.dig(klass.name, col[:key])

      problems << "#{klass.name}##{col[:key]} is offered but has no reader"
    end
  end

  ReportBuilderColumnCatalog::READERS.each do |model, readers|
    klass = model.constantize
    candidate_keys = ReportBuilderColumnCatalog.filter_columns_for(klass).pluck(:key)
    readers.each do |key, reader|
      problems << "#{model}##{key} has a reader but isn't a column" unless candidate_keys.include?(key)
      Array(reader[:preload]).each do |assoc|
        problems << "#{model}##{key} preloads unknown association #{assoc}" unless klass.reflect_on_association(assoc)
      end
    end
  end

  expect(problems).to be_empty, problems.join("\n")
end

# ─────────────────────────────────────────────────────────────────────────────
# Wizard Summarize
# ─────────────────────────────────────────────────────────────────────────────

Then("the wizard Summarize total for {string} shows {string}") do |key, label|
  rb_session.get "/report_builder/#{@wizard_report.id}/wizard/aggregates"
  doc = Nokogiri::HTML(rb_session.response.body)
  form = doc.css("form").find { |f| f.at_css("input[name='key'][value='#{key}']") }
  expect(form).not_to be_nil, "no Summarize form for #{key}"
  expect(form.at_css("select[name='aggregate'] option[selected]")&.text&.strip).to eq(label)
end
