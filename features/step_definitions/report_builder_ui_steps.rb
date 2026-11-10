# frozen_string_literal: true

# Report Builder you can trust — browser steps for the builder page
# (save messages). Uses the Acme fixture from
# report_builder_trust_steps.rb and log_in from login.rb.
# Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

Given("Meera is on the builder for the report") do
  log_in(acme[:meera])
  visit "/report_builder/#{@report.id}/edit"
  wait_for_page_to_settle
end

# Settings live in tabs; open the one a step needs first
def open_builder_tab(key)
  find("#rb-tab-#{key}").click
end

When("I choose {string} as the default sort") do |label|
  open_builder_tab("sort")
  find("select[data-report-builder-target='sortKey']").select(label)
end

# E25 — the next save request never reaches the server
When("the network drops the next save") do
  page.driver.with_playwright_page do |pw_page|
    pw_page.route("**/report_builder/**", ->(route, request) { request.method == "PATCH" ? route.abort : route.continue })
  end
end

# X3 — the total picker sends a value the server refuses (422)
When("I pick a total the server refuses for {string}") do |key|
  page.execute_script(<<~JS)
    const select = document.querySelector('select[data-key=#{key.to_json}]');
    const option = document.createElement("option");
    option.value = "median"; option.text = "median";
    select.appendChild(option);
    select.value = "median";
    select.dispatchEvent(new Event("change", { bubbles: true }));
  JS
end

Then("I see a green message {string}") do |text|
  expect(page).to have_css(".report-builder-toast.text-bg-success", text: text, wait: 10)
end

Then("I see a red message containing {string}") do |text|
  expect(page).to have_css(".report-builder-toast.text-bg-danger", text: text, wait: 10)
end

Then("I see no green message") do
  expect(page).to have_no_css(".report-builder-toast.text-bg-success", wait: 2)
end

Then("the default sort shows {string}") do |label|
  open_builder_tab("sort")
  select = find("select[data-report-builder-target='sortKey']")
  expect(select.find("option[value='#{select.value}']").text.strip).to eq(label)
end

Then("the total for {string} shows {string}") do |key, value|
  open_builder_tab("columns")
  expect(find("select[data-key='#{key}']").value).to eq(value)
end

# ─────────────────────────────────────────────────────────────────────────────
# Live builder (report-builder-live-builder: H1, H5, H7, H9, E9, E10)
# ─────────────────────────────────────────────────────────────────────────────

def builder_preview
  find("turbo-frame#report_builder_preview")
end

Then("the preview shows {string} without a click") do |names|
  within(builder_preview) do
    names.split(",").map(&:strip).each { |name| expect(page).to have_css("tbody td", text: name, wait: 10) }
  end
end

Then("the preview shows a {string} row") do |label|
  within(builder_preview) { expect(page).to have_css("tr.report-builder-totals", text: label, wait: 10) }
end

When("I rename the {string} column to {string} from its header") do |label, new_label|
  within(builder_preview) do
    find("button[aria-label='#{label} column menu']").click
    input = find(".dropdown-menu.show input[name='label']")
    input.fill_in(with: new_label)
    input.send_keys(:enter)
  end
end

Then("the preview header reads {string}") do |label|
  within(builder_preview) { expect(page).to have_css("thead th", text: label, wait: 10) }
end

When("I add a filter on {string}") do |field_label|
  open_builder_tab("filters")
  first("button", text: "Add filter").click
  # The report's own rows' filters (related data may already have filter rows of its own)
  within(own_filter_rows) do
    find(".filter-row select.filter-field", wait: 10).select(field_label)
    # The row is drawn again for the field: wait for its operator list
    expect(page).to have_css(".filter-row select.filter-op", wait: 10)
  end
end

def own_filter_rows
  find("[data-report-builder-target='rootFilterRows']")
end

When("I choose the operator {string}") do |label|
  within(own_filter_rows) do
    find(".filter-row select.filter-op").select(label)
    # Choosing an operator draws the row again
    expect(page).to have_css(".filter-row select.filter-op option[selected]", text: label, wait: 10)
  end
end

When("I type the date {string} in the filter") do |text|
  input = within(own_filter_rows) { find(".filter-row [data-locale-date-target='display']") }
  input.fill_in(with: text)
  input.send_keys(:tab)
end

Then("the filter row says {string}") do |text|
  within(own_filter_rows) { expect(page).to have_css(".filter-row .filter-error", text: text, wait: 10) }
end

Then("the report's own filters are {string}") do |expected|
  # The filter saves itself 600 ms after the last change
  actual = nil
  20.times do
    actual = @report.reload.template["root_filters"]
    break if actual == JSON.parse(expected)

    # KEEP: poll interval of a bounded wait, not a fixed delay
    sleep 0.5
  end
  expect(actual).to eq(JSON.parse(expected))
end

Then("the report's own filters stay empty") do
  # KEEP: asserts the filter did NOT save, so real time must pass the 600 ms debounce first
  sleep 1.5 # longer than the 600 ms pause before a filter saves
  expect(@report.reload.template["root_filters"].presence || {}).to eq({})
end

Then("the preview rows are {string}") do |values|
  within(builder_preview) do
    expected = values.split(",").map(&:strip)
    expect(page).to have_css("tbody tr:not(.report-builder-totals)", count: expected.size, wait: 10)
    expected.each { |v| expect(page).to have_css("tbody td", text: v) }
  end
end

When("I open the formula editor") do
  open_builder_tab("formulas")
  click_on "Add formula"
  expect(page).to have_css("#formulaModal.show", wait: 10)
end

When("I click the column {string} in the formula editor") do |label|
  within("#formulaModal") { find("[data-report-builder-target='formulaColumns'] button", text: label).click }
end

Then("the formula expression contains {string}") do |text|
  expect(find("#rb_formula_expression").value).to include(text)
end
