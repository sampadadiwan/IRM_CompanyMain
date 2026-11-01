# frozen_string_literal: true

# Report Builder assistant — charts on the draft page and the report page.
# Worked examples H5, H7, H8, E6, E11, E12:
# openspec/changes/report-builder-assistant/business-rules.md

module ReportBuilderAssistantChartWorld
  def chart_card(doc = draft_doc)
    doc.at_css(".rb-report-chart")
  end

  def chart_spec(doc = draft_doc)
    JSON.parse(chart_card(doc).at_css("[data-chart-renderer-spec-value]")["data-chart-renderer-spec-value"])
  end
end

World(ReportBuilderAssistantChartWorld)

Then("the draft's chart is {string} drawn as a horizontal bar of {string}") do |title, labels|
  expect(chart_card.at_css(".rb-chart-title").text.strip).to eq(title)
  spec = chart_spec
  expect(spec["type"]).to eq("bar")
  expect(spec.dig("options", "indexAxis")).to eq("y")
  expect(spec.dig("data", "labels")).to eq(labels.split(",").map(&:strip))
end

Then("the draft's chart is {string}") do |title|
  expect(chart_card).to be_present, "no chart on the draft page"
  expect(chart_card.at_css(".rb-chart-title").text.strip).to eq(title)
end

When("I open the saved report's page") do
  rb_session.get "/report_builder/#{@draft.id}/view"
  @last_rb_response = rb_session.response
end

Then("the report page shows the chart {string} with Hide chart") do |title|
  card = chart_card
  expect(card).to be_present, "no chart on the report page"
  expect(card.at_css(".rb-chart-title").text.strip).to eq(title)
  expect(card.text).to include("Hide chart")
  # Above the table
  html = @last_rb_response.body
  expect(html.index("rb-report-chart")).to be < html.index("table-responsive")
end

Given("the chart AI draws a pie") do
  @chart_rows = nil
  pie = { "type" => "pie", "data" => { "labels" => %w[A B], "datasets" => [{ "label" => "Committed", "data" => [1, 2] }] } }
  allow(ChartAgentService).to receive(:new) do |**kwargs|
    @chart_rows = kwargs[:json_data]
    instance_double(ChartAgentService, generate_chart!: pie)
  end
end

When("I describe the chart {string}") do |prompt|
  draft_request(:post, "chart", prompt: prompt)
end

Then("the chart AI got the {int} preview rows") do |count|
  expect(@chart_rows.size).to eq(count)
  expect(AgentChart.where(report_id: @draft.id).count).to eq(1)
end
