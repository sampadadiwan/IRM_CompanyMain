# The one mapping between a fund formula import row and FundFormula attributes, used by the importer
# (ImportFundFormula) and by everything that produces formulas the importer must be able to read back
# (run check suggestions: "Add selected" and "Download xlsx"). Because both directions live here, a
# downloaded file uploaded unchanged creates the same formulas as adding them directly.
#
#   FundFormulaAttributes.from_row(row_hash)   # import headers => attributes
#   FundFormulaAttributes.to_row(attributes)   # attributes => import headers (cell strings)
#   FundFormulaAttributes.as_imported(attrs)   # attrs after a round trip through a sheet, cells cleaned as an import cleans them
class FundFormulaAttributes
  HEADERS = ImportFundFormula::STANDARD_HEADERS
  YTD_HEADER = "Generate Ytd, Quarterly, Since Inception Numbers".freeze

  # Attribute => header for plain text columns
  TEXT_COLUMNS = { name: "Name", description: "Description", entry_type: "Entry Type", formula: "Formula", rule_type: "Rule Type",
                   rule_for: "Rule For", tag_list: "Tag List", meta_data: "Metadata" }.freeze
  # Attribute => header for Yes/No columns
  FLAG_COLUMNS = { roll_up: "Rollup", generate_ytd_qtly: YTD_HEADER, enabled: "Enabled", add_to_commitment_cache: "Cache" }.freeze

  # @param row [Hash{String => String}] one import row keyed by header
  # @return [Hash{Symbol => Object}] :sequence is the stripped string, or nil when blank
  def self.from_row(row)
    attrs = TEXT_COLUMNS.transform_values { |header| row[header] }
    FLAG_COLUMNS.each { |attr, header| attrs[attr] = row[header]&.downcase == "yes" }
    attrs[:sequence] = row["Sequence"]&.strip.presence
    attrs
  end

  # @param attrs [Hash{Symbol => Object}]
  # @return [Hash{String => String}] every import header, in order
  def self.to_row(attrs)
    attrs = attrs.to_h.symbolize_keys
    row = { "Sequence" => attrs[:sequence].to_s }
    TEXT_COLUMNS.each { |attr, header| row[header] = attrs[attr].to_s }
    FLAG_COLUMNS.each { |attr, header| row[header] = attrs[attr] ? "Yes" : "No" }
    HEADERS.index_with { |header| row.fetch(header) }
  end

  # The attributes an import of to_row(attrs) produces: an empty cell reads back as nil, and every cell is
  # cleaned the way ImportUtil cleans it
  def self.as_imported(attrs)
    from_row(to_row(attrs).transform_values { |cell| cell == "" ? nil : ImportUtil.sanitize_cell(cell) })
  end

  # Writes rows of attributes as an xlsx the fund formula import accepts
  # @return [String] the file's bytes
  def self.to_xlsx(attributes_list)
    package = Axlsx::Package.new
    wrap = package.workbook.styles.add_style(alignment: { wrap_text: true, vertical: :top })
    bold = package.workbook.styles.add_style(b: true)
    package.workbook.add_worksheet(name: "FundFormula") do |sheet|
      sheet.add_row(HEADERS, style: bold)
      attributes_list.each do |attrs|
        sheet.add_row(to_row(attrs).values, style: wrap, types: Array.new(HEADERS.size, :string))
      end
      sheet.column_widths(10, 45, 60, 14, 12, 90, 10, 8, 8, 10, 12, 10, 8)
    end
    package.to_stream.read
  end
end
