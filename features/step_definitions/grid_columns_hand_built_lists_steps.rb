# Steps for the hand-built lists (jQuery DataTables) moved to the shared columns mechanism.
# openspec/changes/grid-columns-inline-settings/business-rules.md#1b-hand-built-list-tables--phase-2
# Reuses the steps of grid_columns_inline_settings_steps.rb (open a page, open the panel, add, save, headings).

Given("my firm has funds {string}") do |names|
  @gcl_funds = names.split(",").map(&:strip).map { |name| FactoryBot.create(:fund, entity: @entity, name:) }
  @gcs_fund = @gcl_funds.first
end

Given("the fund {string} has distributions {string}") do |fund_name, titles|
  fund = Fund.find_by!(entity: @entity, name: fund_name)
  @gcs_fund = fund
  titles.split(",").map(&:strip).each.with_index do |title, index|
    FactoryBot.create(:capital_distribution, fund:, entity: @entity, title:, generate_payments: false,
                                             distribution_date: Date.new(2025, 12, 4) + index.months)
  end
end

Given("the distribution {string} has {string} set to {string}") do |title, field, value|
  distribution = CapitalDistribution.find_by!(title:)
  distribution.json_fields = distribution.json_fields.merge(field => value)
  distribution.save!(validate: false)
end

When("I open the distributions of the fund {string}") do |fund_name|
  visit capital_distributions_path(fund_id: Fund.find_by!(entity: @entity, name: fund_name).id)
end

When("I open the form type page for my firm's {string}") do |model_name|
  visit form_type_path(gcs_find_or_create_form_type(model_name))
end

Then("the columns button should be beside the DataTables search box") do
  expect(page).to have_css(".dt-search .grid-columns-btn, .dataTables_filter .grid-columns-btn", wait: 20)
end

Then("the {string} list should link each name to its record") do |table_id|
  rows = all("table##{table_id} tbody tr")
  expect(rows).not_to be_empty
  rows.each { |row| expect(row).to have_css("td:first-child a[href]") }
end

When("I search the DataTables list for {string}") do |text|
  find(".dt-search input, .dataTables_filter input").fill_in(with: text)
end

Then("the {string} list should show only {string}") do |table_id, text|
  gcs_eventually do
    rows = all("table##{table_id} tbody tr").map(&:text)
    rows.size == 1 && rows.first.include?(text)
  end
end

When("I clear the DataTables search") do
  find(".dt-search input, .dataTables_filter input").fill_in(with: "")
end

When("I sort the {string} list by {string}") do |table_id, heading|
  find("table##{table_id} thead th", text: heading, match: :first).click
end

Then("the first row of the {string} list should be {string}") do |table_id, text|
  gcs_eventually { first("table##{table_id} tbody tr")&.text.to_s.include?(text) }
end

Then("the page should offer Configure Grids") do
  expect(page).to have_link("Configure Grids")
end

# E30 — the parents the parameterised lists need (fund, deal, approval, opportunity, investor)
Given("my firm has one record for each converted list") do
  @gcl_records = {
    fund: @gcs_fund,
    deal: FactoryBot.create(:deal, entity: @entity),
    approval: FactoryBot.create(:approval, entity: @entity),
    io: FactoryBot.create(:investment_opportunity, entity: @entity),
    investor: FactoryBot.create(:investor, entity: @entity, investor_entity: FactoryBot.create(:entity, entity_type: "Investor"))
  }
end

Then("each converted list should render with the columns button:") do |table|
  failures = table.hashes.filter_map do |row|
    path = row["path"].gsub(/\{(\w+)\}/) { @gcl_records.fetch(Regexp.last_match(1).to_sym).id.to_s }
    visit path
    ok = page.has_css?(".grid-columns-btn", wait: 20) && page.has_no_text?("Something went wrong", wait: 0)
    "#{row['list']} (#{path})" unless ok
  end
  expect(failures).to be_empty, "lists without the columns button: #{failures.join(', ')}"
end

# --- Responsive width (E31, E32 — ui/datatable-layout, modified) -----------------------------------------------

Given("my browser is {int} pixels wide") do |width|
  page.driver.with_playwright_page { |pw| pw.set_viewport_size(width:, height: 900) }
end

def gcl_visible_headings(table_id)
  sleep 1.5 # DataTables measures and folds after the first draw
  all("table##{table_id} thead th").select(&:visible?).map { |th| th.text.gsub(/[▲▼]/, "").squish }
end

Then("the {string} list should show its first column {string}") do |table_id, label|
  gcs_eventually { gcl_visible_headings(table_id).first == label }
end

Then("the {string} list should fold its actions column") do |table_id|
  gcs_eventually { gcl_visible_headings(table_id).exclude?("Actions") }
end

Then("the {string} list should show its actions column") do |table_id|
  gcs_eventually { gcl_visible_headings(table_id).include?("Actions") }
end

Then("the {string} list should fold some middle columns") do |table_id|
  gcs_eventually do
    all_headings = all("table##{table_id} thead th", visible: :all).size
    gcl_visible_headings(table_id).size < all_headings
  end
end
