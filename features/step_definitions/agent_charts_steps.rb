# frozen_string_literal: true

# ── Helpers ───────────────────────────────────────────────────────────────────

# Minimal valid Chart.js v4 spec that validate_chartjs! will accept.
# responsive/maintainAspectRatio are normally injected by validate_chartjs!,
# but we return them pre-set here so the stub bypasses that method cleanly.
STUB_CHART_SPEC = {
  "type"    => "bar",
  "data"    => {
    "labels"   => ["Jan", "Feb"],
    "datasets" => [{ "label" => "Revenue", "data" => [100, 200], "borderWidth" => 1 }]
  },
  "options" => { "responsive" => true, "maintainAspectRatio" => false }
}.freeze

# Stub LlmService so no real API key is needed and the returned JSON is deterministic.
def stub_llm_with_valid_spec
  mock_chat = double("chat")
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
  # ask is called twice per generate_chart! (system primer then user message),
  # plus once more on the retry path if parse fails — return the spec on every call.
  allow(mock_chat).to receive(:ask).and_return(STUB_CHART_SPEC.to_json)
end

def stub_llm_with_error
  allow(LlmService).to receive(:ruby_llm_chat).and_raise(StandardError, "LLM unavailable")
end

# ── Background / setup steps ──────────────────────────────────────────────────

Given('there is an agent chart {string}') do |args|
  # Parse semicolon-delimited key=value pairs, matching the project's key_values convention.
  attrs = args.split(";").each_with_object({}) do |pair, h|
    k, v = pair.split("=", 2)
    h[k.strip] = v.strip
  end

  @agent_chart = AgentChart.create!(
    entity:           @entity,
    title:            attrs["title"]       || "Test Chart",
    prompt:           attrs["prompt"]      || "Plot something",
    status:           attrs["status"]      || "draft",
    tag_list:         attrs["tag_list"],
    chart_height:     attrs["chart_height"]&.to_i,
    # kpi_names is serialized; split the comma-separated string if present.
    kpi_names:        attrs["kpi_names"]&.split(",")&.map(&:strip)
  )
end

# Variant: agent chart that already has a saved spec for @investor.
# Used in rendering scenarios so we can jump straight to show without triggering the LLM.
Given('there is an agent chart {string} with a saved spec for the portfolio company') do |args|
  steps %(Given there is an agent chart "#{args}")

  # Spec keys must be strings — JSON round-trip through the DB converts integer
  # keys to strings, and the show view looks up via spec[params[:portfolio_company_id]].
  @agent_chart.update!(
    status: "ready",
    spec:   { @investor.id.to_s => STUB_CHART_SPEC }
  )
end

Given('KPI data {string} exists for the portfolio company') do |args|
  attrs = args.split(";").each_with_object({}) { |p, h| k, v = p.split("=", 2); h[k.strip] = v.strip }

  @kpi_report = KpiReport.create!(
    entity:               @entity,
    user:                 @user,
    portfolio_company_id: @investor.id,
    as_of:                Date.today,
    period:               "Month"
  )

  Kpi.create!(
    entity:     @entity,
    name:       attrs["name"]  || "Revenue",
    value:      attrs["value"] || "100",
    kpi_report: @kpi_report
  )
end

Given('the portfolio company has tag {string}') do |tag|
  @investor.update!(tag_list: tag)
end

Given('the LLM is mocked to return a valid bar chart spec') do
  stub_llm_with_valid_spec
end

Given('the LLM is mocked to raise an error') do
  stub_llm_with_error
end

# ── Navigation steps ──────────────────────────────────────────────────────────

When('I visit the agent charts index') do
  visit agent_charts_path
end

When('I visit the new agent chart page') do
  visit new_agent_chart_path
end

When('I visit the show page for that agent chart') do
  visit agent_chart_path(@agent_chart)
end

When('I visit the edit page for that agent chart') do
  visit edit_agent_chart_path(@agent_chart)
end

# ── Form interaction steps ────────────────────────────────────────────────────

When('I fill in the agent chart form with:') do |table|
  # Locate by the Rails-generated field id rather than the attribute name — Capybara's
  # field matcher requires an exact id/name match (no substring), and label text like
  # "Chart Height (px, optional)" doesn't contain the snake_case attribute name either.
  table.rows_hash.each do |field, value|
    fill_in "agent_chart_#{field}", with: value
  end
end

When('I select KPI {string} for the agent chart') do |kpi_name|
  # kpi_names uses a Select2 multi-select; trigger it via JS.
  page.execute_script(
    "var sel = document.querySelector('select[name=\"agent_chart[kpi_names][]\"]'); " \
    "if (sel) { var opt = Array.from(sel.options).find(o => o.text === '#{kpi_name}'); if (opt) opt.selected = true; }"
  )
end

When('I submit the agent chart form') do
  click_button I18n.t("common.save")
end

When('I update the title to {string}') do |new_title|
  fill_in "agent_chart_title", with: new_title
end

When('I delete the agent chart') do
  # Deletion uses a Turbo-disabled form with a confirm controller that shows a
  # custom modal (not a native JS confirm()) — must click through "Proceed".
  click_button "Delete"
  click_on("Proceed")
end

When('I select the portfolio company from the Charts dropdown') do
  # The Charts dropdown links to agent_chart_path with portfolio_company_id param.
  click_button "Charts"
  click_link @investor.name
end

# ── Generation steps ──────────────────────────────────────────────────────────

When('I generate the chart spec for the portfolio company') do
  # Call generate_spec! directly rather than going through the async job, so the
  # spec is created synchronously and we can assert on it immediately.
  @agent_chart.generate_spec!(portfolio_company_id: @investor.id)
rescue StandardError
  # Failed generation is an expected outcome in the failure scenario — the model
  # has already been updated to status "failed" inside generate_spec! before raise.
  nil
end

When('the agent chart job runs for all tagged portfolio companies') do
  # Inline the job logic to avoid async queuing in tests.
  AgentChartJob.new.perform(
    @user.id,
    agent_chart_id:      @agent_chart.id,
    portfolio_company_id: @investor.id
  )
rescue StandardError
  nil
end

# ── Assertion steps ───────────────────────────────────────────────────────────

Then('I should see {string} in the agent charts table') do |text|
  within("table#agent_charts, table.dataTable") do
    expect(page).to have_content(text)
  end
end

Then('I should not see {string} in the agent charts table') do |text|
  within("table#agent_charts, table.dataTable") do
    expect(page).not_to have_content(text)
  end
end

Then('the agent chart status should be {string}') do |expected_status|
  # On create, @agent_chart isn't set by a Given step — resolve it from the show page
  # URL instead of querying right after the click, which would race the server's commit.
  @agent_chart ||= AgentChart.find(current_path[%r{/agent_charts/(\d+)}, 1])
  # Reload from DB rather than relying on instance variable which may be stale.
  actual = @agent_chart.reload.status.humanize
  expect(actual).to eq(expected_status)
end

Then('the agent chart error should not be blank') do
  expect(@agent_chart.reload.error).to be_present
end

Then('I should see chart height {string} on the agent chart show page') do |height|
  # The show view writes chart_height (or 420 default) into the data attribute.
  expect(page).to have_css("[data-chart-renderer-height-value='#{height}']")
end

Then('the chart container should have height value {string}') do |height|
  expect(page).to have_css("[data-chart-renderer-height-value='#{height}']")
end

Then('I should see the chart canvas rendered on the page') do
  expect(page).to have_css("canvas[data-chart-renderer-target='canvas']")
end

Then('the chart controller should have the spec value set') do
  # Verify the Stimulus data attribute is non-empty — actual Chart.js rendering
  # requires a real browser with JS execution enabled.
  node = find("[data-chart-renderer-spec-value]")
  expect(node["data-chart-renderer-spec-value"]).to be_present
end

Then('I should see {string} on the agent chart show page') do |text|
  expect(page).to have_content(text)
end

Then('the spec should have a string key for the portfolio company id') do
  spec = @agent_chart.reload.spec
  # Keys must be strings after JSON round-trip; an integer key would produce a
  # silent miss when the view looks up spec[params[:portfolio_company_id]].
  expect(spec.keys.all? { |key| key.is_a?(String) }).to be true
  expect(spec[@investor.id.to_s]).to be_present
end

Then('the agent chart should have a spec for the portfolio company') do
  spec = @agent_chart.reload.spec
  expect(spec[@investor.id.to_s]).to be_present
end
