# Step definitions for features/fund/entry_explanation.feature. Entries are built by the steps in
# formula_entry_steps.rb (tagged @entry_explanation, which also cleans them up); these open an
# AccountEntryExplanation over them and read its nodes.

def ex_nodes(node = @ex_root)
  node.children.flat_map { |child| [child] + ex_nodes(child) }
end

def ex_term!(label)
  term = ex_nodes.find { |n| n.label == label }
  expect(term).not_to be_nil, "No term #{label.inspect}; got #{ex_nodes.map(&:label).inspect}"
  term
end

Given('the run produced {string} of {string} for folio {string} computed by {string} recording:') do |name, amount, folio_id, formula, table|
  breakdown = table.hashes.to_h { |row| [row["expression"].strip, row["value"]] }
  dt_entry(name: name, amount: amount, folio_id: folio_id, formula: formula, breakdown: breakdown)
end

When('I open the explanation of {string} for folio {string}') do |name, folio_id|
  @ex = AccountEntryExplanation.new(dt_find!(name, folio_id))
  @ex_root = @ex.root
end

Then('the explanation should list {string}') do |labels|
  expect(@ex_root.children.map(&:label)).to eq(labels.split(",").map(&:strip))
end

Then('term {string} should be taken away') do |label|
  expect(ex_term!(label).subtracted?).to be(true)
end

Then('term {string} should be another entry') do |label|
  expect(ex_term!(label).kind).to eq(:entry)
end

Then('term {string} should carry no operator') do |label|
  term = ex_term!(label)
  expect([term.op, term.subtracted?]).to eq([nil, false])
end

Then('term {string} should divide') do |label|
  expect(ex_term!(label).divisor?).to be(true)
end

Then('term {string} should show {string}') do |label, value|
  expect(ex_term!(label).numeric_value.to_s("F").sub(/\.0\z/, "")).to eq(value)
end

Then('term {string} should open into {string}') do |label, labels|
  expect(ex_term!(label).children.map(&:label)).to eq(labels.split(",").map(&:strip))
end

Then('term {string} should be from an earlier period') do |label|
  expect(ex_term!(label).kind).to eq(:earlier)
end

Then('term {string} should be a total over time') do |label|
  expect(ex_term!(label).kind).to eq(:aggregate)
end

Then('term {string} should say {string}') do |label, text|
  expect(ex_term!(label).note.to_s).to include(text)
end

Then('term {string} should not be money') do |label|
  expect(ex_term!(label).money?).to be(false)
end

Then('the explanation should say its lines add up') do
  expect(@ex.reconciles?).to be(true)
end

Then('the explanation should say its lines do not add up') do
  expect(@ex.reconciles?).to be(false)
end

# A product's lines are its inputs, not parts of a sum; totalling them would be a category error.
Then('the explanation should not claim a total') do
  expect(@ex.additive?).to be(false)
  expect(@ex.reconciles?).to be_nil
end

Then('term {string} should not link to a single entry') do |label|
  expect(ex_term!(label).entry_id).to be_nil
end

Then('term {string} should not open') do |label|
  expect(ex_term!(label).lazy?).to be(false)
end

When('I open the total {string} since inception from it') do |name|
  @ex_window, = @ex.window_nodes(helper: "since_inception", name: name, entry_type: nil)
end

# The rule ran before its own entry existed, so the entry cannot be among what it totalled.
Then('the total should not list the entry being explained') do
  expect(@ex_window.map(&:entry_id)).not_to include(@ex.entry.id)
  expect(@ex_window).not_to be_empty
end

Then('term {string} should be a share of a fund total') do |label|
  expect(ex_term!(label).kind).to eq(:source)
end

Then('term {string} should be worth {string}') do |label, major_units|
  expect(format("%.2f", (ex_term!(label).numeric_value / 100).round(2))).to eq(major_units)
end

Then('no term should be another entry') do
  expect(ex_nodes.select { |n| n.kind == :entry }.map(&:label)).to be_empty
end

Then('that investor should not be able to open the explanation\'s lines') do
  entry = AccountEntry.where(fund_id: @fund.id, name: "NAV").first
  expect(AccountEntryPolicy.new(@tie_out_investor, entry).explanation_node?).to be(false)
end

Then('the company admin should be able to open the explanation\'s lines') do
  entry = AccountEntry.where(fund_id: @fund.id, name: "NAV").first
  expect(AccountEntryPolicy.new(@user, entry).explanation_node?).to be(true)
end

Then('the explanation should say {string}') do |text|
  expect(@ex.leaf_reason.to_s).to include(text)
end

Then('term {string} should have no parts') do |label|
  expect(ex_term!(label).children).to be_empty
end

Then('the calculation steps should be {string}') do |pairs|
  expected = pairs.split(",").map { |pair| pair.split("=", 2).map(&:strip) }
  expect(@ex.steps.map { |key, value| [key, value.to_s] }).to eq(expected)
end

Then('there should be no calculation steps') do
  expect(@ex.steps).to be_empty
end

# Draws the steps partial on its own — it takes only the explanation, so no request or policy is
# needed — and keeps the HTML for the checks below.
When('the calculation steps table is drawn') do
  html = AccountEntriesController.render(partial: "account_entries/explanation_steps",
                                         locals: { explanation: @ex, entry: @ex.entry, ai_data: nil })
  @ex_steps_html = Nokogiri::HTML.fragment(html)
end

Then('the steps table should show {string} as {string}') do |expression, value|
  row = @ex_steps_html.css("#explanation_steps tbody tr").find { |tr| tr["data-step-expr"] == expression }
  expect(row).not_to be_nil, "No row for #{expression.inspect}"
  expect(row.css("td")[2].text.strip).to eq(value)
end

Then('the steps table should not be drawn') do
  expect(@ex_steps_html.css("#explanation_steps")).to be_empty
end
