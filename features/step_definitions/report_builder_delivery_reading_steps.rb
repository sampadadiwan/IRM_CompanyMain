# frozen_string_literal: true

# Report Builder delivery — the report page's filter chips, Narrow down and
# headline totals, and the removal of Save as View, over HTTP on the Acme
# fixture from report_builder_trust_steps.rb.
# Worked examples H9–H12, E8–E14:
# openspec/changes/report-builder-delivery/business-rules.md

module ReportBuilderReadingWorld
  def rb_text(node)
    node.text.gsub(/[[:space:]]+/, " ").strip
  end

  # First cell of every body row, without the totals row
  def report_page_names
    page_doc.css(".table-responsive table tbody tr:not(.report-builder-totals)").map { |tr| rb_text(tr.at_css("td")) }
  end

  def headline_cards
    page_doc.css(".rb-headline-totals .card").map do |card|
      { amount: rb_text(card.at_css("h2, h3")), label: rb_text(card.at_css(".card-subtitle")),
        footnote: card.at_css(".small.text-muted") && rb_text(card.at_css(".small.text-muted")) }
    end
  end

  # { column label => totals row cell } of the page's table, labels from the header
  def totals_row
    labels = page_doc.css(".table-responsive table thead th").map { |th| rb_text(th) }
    cells  = page_doc.css(".table-responsive table tbody tr.report-builder-totals td").map { |td| rb_text(td) }
    labels.zip(cells).to_h
  end
end

World(ReportBuilderReadingWorld)

Given("Aditi Rao is in {string} and Kiran Mehta in {string}") do |aditi_city, kiran_city|
  acme[:aditi].update_columns(city: aditi_city)
  acme[:kiran].update_columns(city: kiran_city)
  # The factory's own city could be either; the others are elsewhere
  %i[zeta nova].each { |sym| acme[sym].update_columns(city: "Delhi") }
end

Given("the report has no filters") do
  tmpl = @report.reload.template.deep_stringify_keys
  tmpl["root_filters"] = {}
  tmpl["joins"] = tmpl["joins"].map { |j| j.merge("child_filters" => {}) }
  @report.update!(template: tmpl)
end

Given("the report shows only Investor and Category") do
  @report.grid_view_preferences.where.not(key: %w[investor_name category]).destroy_all
end

Given("the report was once marked as a view") do
  @report.update_columns(is_view: true)
end

When("I open the report builder report page with {string}") do |query|
  open_delivery_report_page(Rack::Utils.parse_nested_query(query).to_h)
end

# The Narrow down row's own fields, as its Apply sends them
When("I narrow the report down to {string} {string} {string}") do |field, op, value|
  @template_before = @report.reload.template.deep_dup
  open_delivery_report_page(nf: field, nop: op, nv: value, apply: "1")
end

When("I remove the reader chip {string}") do |text|
  chip = page_doc.css(".rb-reader-chip").find { |c| rb_text(c) == text }
  expect(chip).not_to be_nil, "no reader chip #{text}; chips: #{page_doc.css('.rb-reader-chip').map { |c| rb_text(c) }}"
  rb_session.get chip.at_css("a")["href"], headers: { "Accept" => "text/html" }
  @last_rb_response = rb_session.response
end

When("I request the old view-settings address") do
  rb_request_or_not_found(:patch, "/report_builder/#{@report.id}/view_settings", is_view: true)
end

Then("the report shows only {string}") do |chips|
  shown = page_doc.css(".rb-saved-filters .badge").map { |b| rb_text(b) }
  expect(shown).to eq(chips.split(",").map(&:strip))
end

Then("the report page offers {string}") do |text|
  expect(page_doc.css(".rb-view-filters a").map { |a| rb_text(a) }).to include(text)
end

Then("the report page offers Narrow down") do
  expect(page_doc.at_css(".rb-narrow-down select[name='nf']")).to be_present
end

Then("the report page has no {string}") do |text|
  expect(rb_page_text).not_to include(text)
end

Then("the report page rows are {string}") do |names|
  expect(report_page_names).to eq(names.split(",").map(&:strip))
end

Then("the reader chips are {string}") do |chips|
  expect(page_doc.css(".rb-reader-chip").map { |c| rb_text(c) }).to eq(chips.split(",").map(&:strip))
end

Then("there are no reader chips") do
  expect(page_doc.css(".rb-reader-chip")).to be_empty
end

Then("the report's saved filters are still Category is LP") do
  expect(@report.reload.template).to eq(@template_before)
  expect(@report.template.dig("root_filters", "category_eq")).to eq("LP")
end

Then("the headline cards are {string}") do |expected|
  cards = headline_cards.map { |c| "#{c[:label]}=#{c[:amount]}" }
  expect(cards).to eq(expected.split("|").map(&:strip))
end

Then("each headline card equals the totals row") do
  row = totals_row
  expect(headline_cards).not_to be_empty
  headline_cards.each do |card|
    cell = row.fetch(card[:label])
    # The first cell also carries the "Total" label
    expect(cell.sub(/\ATotal( \(this page\))? ?/, "")).to eq(card[:amount])
  end
end

Then("each headline card says {string}") do |text|
  expect(headline_cards.pluck(:footnote).uniq).to eq([text])
end

Then("the totals row reads {string}") do |label|
  expect(rb_text(page_doc.at_css(".table-responsive table tbody tr.report-builder-totals td"))).to start_with(label)
end

Then("there are no headline cards") do
  expect(page_doc.css(".rb-headline-totals")).to be_empty
end

Then("the builder page has no View or Sharing settings") do
  expect(page_doc.css("#viewTargetSection, [data-action*='toggleView'], [data-action*='toggleShared']")).to be_empty
end
