# frozen_string_literal: true

# Report Builder you can trust — formatting, totals, header sort, Reports list
# link and Excel steps. Pages are fetched over HTTP (no browser) and read with
# Nokogiri; exports are read back with Roo.
# Uses the Acme fixture and helpers from report_builder_trust_steps.rb.
# Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

module ReportBuilderTrustDisplayWorld
  def squish(text)
    text.to_s.gsub(/[[:space:]]+/, " ").strip
  end

  # { headers:, rows: [[cell texts]], body_cells: [[Nokogiri td]], footer: [cell texts] or nil }
  def page_table
    doc   = Nokogiri::HTML(@last_rb_response.body)
    table = doc.at_css("table.table")
    expect(table).not_to be_nil, "no table on the page: #{squish(doc.text)[0, 300]}"
    # The totals row is the last body row, marked report-builder-totals
    data_rows = table.css("tbody tr:not(.report-builder-totals)")
    {
      headers: table.css("thead th").map { |th| squish(th.text) },
      header_cells: table.css("thead th"),
      rows: data_rows.map { |tr| tr.css("td").map { |td| squish(td.text) } },
      body_cells: data_rows.map { |tr| tr.css("td") },
      footer: table.at_css("tr.report-builder-totals")&.css("td")&.map { |td| squish(td.text) }
    }
  end

  def column_index(table, header)
    idx = table[:headers].index { |h| h == header || h.start_with?("#{header} ") }
    expect(idx).not_to be_nil, "no column #{header.inspect}; headers: #{table[:headers].inspect}"
    idx
  end

  def table_row_with(table, text)
    row = table[:rows].find { |cells| cells.include?(text) }
    expect(row).not_to be_nil, "no row with #{text.inspect}; rows: #{table[:rows].inspect}"
    row
  end

  # Excel layout: row 1 name, row 2 filters, row 3 headers, rows 4+ data
  def export_column(header)
    headers = @export_sheet.row(3)
    idx = headers.index { |h| h.to_s == header || h.to_s.start_with?("#{header} ") }
    expect(idx).not_to be_nil, "no Excel column #{header.inspect}; headers: #{headers.inspect}"
    idx + 1
  end

  def export_row_with(text)
    row = (4..@export_sheet.last_row).find { |r| @export_sheet.row(r).map(&:to_s).include?(text) }
    expect(row).not_to be_nil, "no Excel row with #{text.inspect}"
    row
  end

  def open_report_page(query = nil)
    rb_session.get "/report_builder/#{@report.id}/view#{"?#{query}" if query.present?}"
    @last_rb_response = rb_session.response
  end
end

World(ReportBuilderTrustDisplayWorld)

After("@report_builder") do
  # E23 stubs the computed-sort row cap; put the real one back
  if @original_sort_cap
    ReportBuilderQueryEngine.send(:remove_const, :MAX_COMPUTED_SORT_ROWS)
    ReportBuilderQueryEngine.const_set(:MAX_COMPUTED_SORT_ROWS, @original_sort_cap)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Extra data
# ─────────────────────────────────────────────────────────────────────────────

# DP1 Aditi (C1): gross payable ₹13,00,000 · net payable ₹12,34,567 · units 100 · completed
Given("the Acme distribution payment exists") do
  distribution = FactoryBot.create(:capital_distribution, fund: acme[:gf2], entity: @entity, generate_payments: false,
                                                          distribution_date: Date.new(2026, 5, 1))
  dp = FactoryBot.create(:capital_distribution_payment, fund: acme[:gf2], entity: @entity, capital_distribution: distribution,
                                                        investor: acme[:aditi], capital_commitment: acme[:c1],
                                                        folio_id: acme[:c1].folio_id, gross_payable_cents: 1_300_000_00,
                                                        payment_date: Date.new(2026, 5, 1))
  dp.update_columns(investor_name: "Aditi Rao", gross_payable_cents: 1_300_000_00, net_payable_cents: 1_234_567_00,
                    units_quantity: 100, completed: true)
  acme[:dp1] = dp
end

Given("{int} more investors exist") do |count|
  count.times { |i| build_investor(entity: @entity, name: "Extra Investor #{i + 1}") }
end

Given("the report's display currency is {string}") do |currency|
  tmpl = @report.template.deep_stringify_keys
  @report.update!(template: tmpl.merge("currency" => currency))
end

Given("the report is saved sorted by {string} {string}") do |key, dir|
  # Reload: earlier steps may have changed the report over HTTP
  tmpl = @report.reload.template.deep_stringify_keys
  @report.update!(template: tmpl.merge("sort" => { "key" => key, "dir" => dir }))
end

Given("the computed sort row cap is {int}") do |cap|
  @original_sort_cap = ReportBuilderQueryEngine::MAX_COMPUTED_SORT_ROWS
  ReportBuilderQueryEngine.send(:remove_const, :MAX_COMPUTED_SORT_ROWS)
  ReportBuilderQueryEngine.const_set(:MAX_COMPUTED_SORT_ROWS, cap)
end

# ─────────────────────────────────────────────────────────────────────────────
# Report page and preview
# ─────────────────────────────────────────────────────────────────────────────

When("I open the Report Builder page") do
  open_report_page
end

When("I open the Report Builder page with {string}") do |query|
  open_report_page(query)
end

When("I open the preview") do
  rb_session.get "/report_builder/#{@report.id}/preview"
  @last_rb_response = rb_session.response
end

Then("the Report Builder page loads") do
  expect(@last_rb_response.status).to eq(200), "status #{@last_rb_response.status}: #{@last_rb_response.body[0, 300]}"
end

Then("the page is refused") do
  expect(@last_rb_response.status).not_to eq(200)
end

Then("the table shows {string} under {string} in the row with {string}") do |expected, header, row_text|
  table = page_table
  expect(table_row_with(table, row_text)[column_index(table, header)]).to eq(expected)
end

# H15 — the same text in the preview and on the report page
Then("the preview and the report page show {string} under {string} in the row with {string}") do |expected, header, row_text|
  step %(I open the preview)
  step %(the table shows "#{expected}" under "#{header}" in the row with "#{row_text}")
  step %(I open the Report Builder page)
  step %(the table shows "#{expected}" under "#{header}" in the row with "#{row_text}")
end

Then("the {string} column is right-aligned") do |header|
  table = page_table
  idx   = column_index(table, header)
  expect(table[:header_cells][idx]["class"]).to include("text-end")
  table[:body_cells].each { |cells| expect(cells[idx]["class"]).to include("text-end") }
end

Then("the Report Builder page says {string}") do |text|
  expect(squish(Nokogiri::HTML(@last_rb_response.body).text)).to include(text)
end

Then("the totals row is labelled {string}") do |label|
  footer = page_table[:footer]
  expect(footer).not_to be_nil, "no totals row"
  expect(footer.first).to start_with(label)
end

Then("the totals row shows {string} under {string}") do |expected, header|
  table = page_table
  expect(table[:footer]).not_to be_nil, "no totals row"
  cell = table[:footer][column_index(table, header)]
  # The first cell also carries the label
  expect(cell.sub(/\ATotal( \([^)]*\))?\s*/, "")).to eq(expected)
end

Then("the totals row is blank under {string}") do |header|
  table = page_table
  cell = table[:footer][column_index(table, header)]
  expect(cell.sub(/\ATotal( \([^)]*\))?\s*/, "")).to eq("")
end

Then("there is no totals row") do
  expect(page_table[:footer]).to be_nil
end

Then("the rows are in the order {string}") do |names|
  expect(page_table[:rows].map(&:first)).to eq(names.split(",").map(&:strip))
end

Then("the {string} header shows it is sorted {string}") do |header, direction|
  table = page_table
  expect(table[:header_cells][column_index(table, header)]["aria-sort"]).to eq(direction)
end

Then("the next page link keeps the sort {string} {string}") do |key, dir|
  # The pagination link to page 2 (not a header link that merely carries per_page=2)
  links = Nokogiri::HTML(@last_rb_response.body).css("a[href]").pluck("href").grep(/[?&]page=2(&|\z)/)
  expect(links).not_to be_empty, "no link to page 2"
  expect(links.first).to include("sort=#{CGI.escape(key)}").and include("dir=#{dir}")
end

Then("the saved sort is still {string} {string}") do |key, dir|
  sort = ReportBuilderConfig.new(@report.reload.template).sort
  expect([sort[:key], sort[:dir]]).to eq([key, dir])
end

# ─────────────────────────────────────────────────────────────────────────────
# Reports list
# ─────────────────────────────────────────────────────────────────────────────

Given("a grid report {string} on {string}") do |name, url|
  @grid_report = Report.create!(entity: @entity, user: @user, name: name, url: url)
end

When("I open the reports list") do
  rb_session.get "/reports"
  @last_rb_response = rb_session.response
end

Then("the name {string} links to {string}") do |name, href|
  link = Nokogiri::HTML(@last_rb_response.body).css("a").find { |a| squish(a.text) == name }
  expect(link).not_to be_nil, "no link named #{name}"
  expect(link["href"]).to eq(href)
end

Then("the name {string} links to its own grid URL") do |name|
  step %(the name "#{name}" links to "#{@grid_report.reload.url}")
end

Then("the name {string} links to its report page") do |name|
  step %(the name "#{name}" links to "/report_builder/#{@report.id}/view")
end

# ─────────────────────────────────────────────────────────────────────────────
# Formatter and totals in isolation
# ─────────────────────────────────────────────────────────────────────────────

# X6 — a value of an unexpected kind in a column of unknown type reads as text
Then("a column of unknown type holding a hash shows as text") do
  config    = ReportBuilderConfig.new(@report.template)
  formatter = ReportBuilderValueFormatter.new(config: config, entity: @entity)
  column    = ReportBuilderDynamicColumn.new(key: "some_method", label: "Some method")
  expect(formatter.display({ "a" => 1 }, column)).to eq({ "a" => 1 }.to_s)
  expect(formatter.xlsx({ "a" => 1 }, column)).to eq([{ "a" => 1 }.to_s, nil])
end

# E30 — blank values count as zero in a total
Then("the total of {string} over the values {string} is {string}") do |key, values, expected|
  rows   = values.split(",").map { |v| { key => v.strip.presence && BigDecimal(v.strip) } }
  config = ReportBuilderConfig.new(@report.template)
  column = @report.grid_view_preferences.find { |g| g.key == key }
  totals = ReportBuilderTotals.new(rows: rows, columns: [column], config: config).call
  expect(totals[key]).to eq(BigDecimal(expected))
end

# ─────────────────────────────────────────────────────────────────────────────
# Excel
# ─────────────────────────────────────────────────────────────────────────────

When("I export the report to Excel") do
  engine  = ReportBuilderQueryEngine.new(report: @report.reload, entity: @report.entity, user: @report.user)
  rows    = engine.run(computed_sort_cap: nil)
  binary  = ReportBuilderXlsxExporter.new(report: @report, rows: rows, columns: engine.columns).generate
  @xlsx_tempfile = Tempfile.new(["report_builder_export", ".xlsx"], binmode: true)
  @xlsx_tempfile.write(binary)
  @xlsx_tempfile.rewind
  @export_sheet = Roo::Spreadsheet.open(@xlsx_tempfile.path)
  @export_sheet.default_sheet = "Data"
end

Then("the export has the number {string} with format {string} under {string} in the row with {string}") do |value, format, header, row_text|
  r = export_row_with(row_text)
  c = export_column(header)
  expect(@export_sheet.celltype(r, c)).to eq(:float)
  expect(@export_sheet.cell(r, c)).to eq(value.to_f)
  expect(@export_sheet.excelx_format(r, c)).to eq(format)
end

Then("the export has a date cell {string} under {string} in the row with {string}") do |date, header, row_text|
  r = export_row_with(row_text)
  c = export_column(header)
  expect(@export_sheet.celltype(r, c)).to eq(:date)
  expect(@export_sheet.cell(r, c)).to eq(Date.parse(date))
end

Then("the export shows {string} under {string} in the row with {string}") do |text, header, row_text|
  expect(@export_sheet.cell(export_row_with(row_text), export_column(header)).to_s).to eq(text)
end

Then("the export's last row is a bold totals row with {string} under {string}") do |value, header|
  r = @export_sheet.last_row
  expect(@export_sheet.cell(r, 1).to_s).to eq("Total")
  expect(@export_sheet.font(r, 1).bold?).to be true
  expect(@export_sheet.cell(r, export_column(header)).to_f).to eq(value.to_f)
end

# The totals row replaced the separate "Totals" sheet: it is the Data sheet's last row
Then("the Data sheet totals row shows {string} for the column labeled {string}") do |expected, label|
  @export_sheet.default_sheet = "Data"
  idx = @export_sheet.row(3).index { |h| h.to_s.include?(label) }
  expect(idx).not_to be_nil, "no header containing #{label.inspect}"
  expect(@export_sheet.cell(@export_sheet.last_row, idx + 1).to_f).to eq(expected.to_f)
end

Then("the Data sheet totals row is blank for the column labeled {string}") do |label|
  @export_sheet.default_sheet = "Data"
  idx = @export_sheet.row(3).index { |h| h.to_s.include?(label) }
  expect(idx).not_to be_nil, "no header containing #{label.inspect}"
  expect(@export_sheet.cell(@export_sheet.last_row, idx + 1)).to be_nil
end

Then("the export's last row has no total under {string}") do |header|
  expect(@export_sheet.cell(@export_sheet.last_row, export_column(header))).to be_nil
end
