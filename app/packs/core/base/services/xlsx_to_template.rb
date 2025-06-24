# frozen_string_literal: true

# app/packs/core/documents/services/xlsx_to_json_converter.rb

require 'rubyXL'
require 'rubyXL/convenience_methods' # ← loads extra helpers
require 'json'
require 'digest'

class XlsxToTemplate
  # ---------------------------------------------------------------------------
  #  PUBLIC API
  # ---------------------------------------------------------------------------
  # Convert an XLSX file’s structure, styles & formulas to a JSON-compatible Hash
  #
  # @param file_path [String] absolute or relative path to the .xlsx file
  # @return [Hash]  data conforming to XlsxToJsonConfig::SCHEMA
  def self.convert(file_path)
    raise "File not found: #{file_path}" unless File.exist?(file_path)

    workbook = RubyXL::Parser.parse(file_path)
    styles_map = {} # Styles are now dynamically discovered

    sheets = workbook.worksheets.map.with_index do |worksheet, index|
      extract_sheet_data(worksheet, index, styles_map, workbook)
    end

    {
      'workbookName' => File.basename(file_path, '.*'),
      'styles' => styles_map,
      'sheets' => sheets
    }
  rescue StandardError => e
    raise "Failed to parse XLSX file: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  #                             PRIVATE HELPERS
  # ---------------------------------------------------------------------------

  # ---------------------------  STYLE EXTRACTION  ----------------------------
  # -- refactored: No longer pre-extracts all styles. Styles are discovered
  #    dynamically to account for table-based differential styles (DXFs).

  # -- fixed: no more .size call; use font.sz&.val etc. -----------------------
  def self.style_to_hash(x_format, workbook, d_format = nil)
    font   = workbook.stylesheet.fonts[x_format.font_id]
    fill   = workbook.stylesheet.fills[x_format.fill_id]
    border = workbook.stylesheet.borders[x_format.border_id]

    # Merge DXF styles if provided
    if d_format
      font   = merge_font(font, d_format.font) if d_format.font
      fill   = merge_fill(fill, d_format.fill) if d_format.fill
      border = merge_border(border, d_format.border) if d_format.border
    end

    {
      'font' => font_to_hash(font),
      'fill' => fill_to_hash(fill),
      'border' => border_to_hash(border),
      'alignment' => alignment_to_hash(x_format.alignment),
      'numFmt' => get_number_format_code(x_format.num_fmt_id, workbook),
      'protection' => protection_to_hash(x_format.protection)
    }.compact
  end

  # ---------------------------  STYLE HASH HELPERS  --------------------------
  def self.font_to_hash(font)
    {
      'name' => font&.name&.val,
      'size' => font&.sz&.val,
      'bold' => font&.b&.val || false,
      'italic' => font&.i&.val || false,
      'underline' => font&.u&.val || false,
      'color' => font&.color&.rgb
    }.compact
  end

  def self.fill_to_hash(fill)
    {
      'pattern' => fill&.pattern_fill&.pattern_type,
      'fgColor' => fill&.pattern_fill&.fg_color&.rgb,
      'bgColor' => fill&.pattern_fill&.bg_color&.rgb
    }.compact
  end

  def self.border_to_hash(border)
    {
      'top' => { 'style' => border&.top&.style, 'color' => border&.top&.color&.rgb }.compact,
      'bottom' => { 'style' => border&.bottom&.style, 'color' => border&.bottom&.color&.rgb }.compact,
      'left' => { 'style' => border&.left&.style, 'color' => border&.left&.color&.rgb }.compact,
      'right' => { 'style' => border&.right&.style, 'color' => border&.right&.color&.rgb }.compact
    }.compact
  end

  def self.alignment_to_hash(alignment)
    {
      'h' => alignment&.horizontal,
      'v' => alignment&.vertical,
      'wrap' => alignment&.wrap_text,
      'indent' => alignment&.indent,
      'shrink' => alignment&.shrink_to_fit,
      'rotation' => alignment&.text_rotation
    }.compact
  end

  def self.protection_to_hash(protection)
    { 'locked' => protection&.locked, 'hidden' => protection&.hidden }.compact
  end

  # ---------------------------  STYLE MERGING HELPERS  -----------------------
  def self.merge_font(base_font, d_format_font)
    merged = base_font.dup
    merged.b = d_format_font.b if d_format_font.b
    merged.i = d_format_font.i if d_format_font.i
    merged.u = d_format_font.u if d_format_font.u
    merged.sz = d_format_font.sz if d_format_font.sz
    merged.color = d_format_font.color if d_format_font.color
    merged.name = d_format_font.name if d_format_font.name
    merged
  end

  def self.merge_fill(base_fill, d_format_fill)
    merged = base_fill.dup
    merged.pattern_fill = d_format_fill.pattern_fill if d_format_fill.pattern_fill
    merged
  end

  def self.merge_border(base_border, d_format_border)
    merged = base_border.dup
    merged.top = d_format_border.top if d_format_border.top
    merged.bottom = d_format_border.bottom if d_format_border.bottom
    merged.left = d_format_border.left if d_format_border.left
    merged.right = d_format_border.right if d_format_border.right
    merged
  end

  # ---------------------------  SHEET/ROW/CELL EXTRACTION  ---------------------
  def self.extract_sheet_data(worksheet, index, styles_map, workbook)
    {
      'name' => worksheet.sheet_name,
      'index' => index,
      'columnHeaders' => extract_column_headers(worksheet, styles_map, workbook),
      'merges' => extract_merges(worksheet)
    }.compact
  end

  # ---------------------------  FORMULA EXTRACTION  --------------------------
  def self.extract_formula(cell)
    cell&.formula&.expression
  end

  # ---------------------------  COLUMN HEADER EXTRACTION  --------------------
  def self.extract_column_headers(worksheet, styles_map, workbook)
    header_row = worksheet[0]
    return [] if header_row.nil?

    data_rows = find_data_rows(worksheet)
    headers = []

    header_row.cells.each_with_index do |cell, col_idx|
      next if cell.nil? || cell.value.to_s.strip.empty?

      row_styles = []
      column_formulas = [] # Initialize array to store formulas for this column

      data_rows.each do |data_row|
        row_cell = data_row&.cells&.at(col_idx)
        next unless row_cell

        style_id = get_style_id(row_cell, styles_map, workbook, worksheet)
        row_styles << styles_map[style_id] if style_id # Retrieve the actual style hash

        formula = extract_formula(row_cell)
        column_formulas << formula if formula # Capture formula if present in data cell
      end
      row_styles.uniq!
      column_formulas.uniq!

      column_data = {
        'name' => cell.value.to_s,
        'field' => cell.value.to_s.parameterize.underscore,
        'columnIndex' => col_idx,
        'header_style_id' => get_style_id(cell, styles_map, workbook, worksheet),
        'row_styles' => row_styles,
        'formulas' => column_formulas # Store all unique formulas found in the column
      }.compact

      # Add column width if available
      # Add column width
      col_info = worksheet.cols&.find { |col| col.min && col.max && (col_idx + 1).between?(col.min, col.max) }
      column_data['width'] = col_info.width if col_info&.width

      # Get number format from the first data cell in the column
      first_data_row = worksheet[1] # Assuming header is at row 0
      if first_data_row
        cell_in_col = first_data_row[col_idx]
        if cell_in_col&.style_index
          cell_x_format = workbook.stylesheet.cell_xfs[cell_in_col.style_index]
          if cell_x_format&.num_fmt_id
            Rails.logger.debug { "XlsxToTemplate: Calling get_number_format_code from extract_column_headers for cell (col: #{col_idx}) with style_index: #{cell_in_col.style_index}, num_fmt_id: #{cell_x_format.num_fmt_id}" }
            column_data['numFmt'] = get_number_format_code(cell_x_format.num_fmt_id, workbook)
          end
        end
      end

      headers << column_data
    end
    headers
  end

  # ---------------------------  MERGE/STYLE-ID HELPERS  ------------------------
  def self.find_data_rows(worksheet)
    data_rows = []
    worksheet.each_with_index do |row, idx|
      next if idx.zero? # Skip header row

      # Consider a row as a data row if it has any non-blank cells
      data_rows << row if row&.cells&.any? { |c| !c&.value.to_s.strip.empty? }
    end
    data_rows
  end

  def self.extract_merges(worksheet)
    return [] if worksheet.merged_cells.nil?

    worksheet.merged_cells.map(&:to_s)
  end

  def self.get_style_id(cell, styles_map, workbook, worksheet)
    return nil if cell&.style_index.nil?

    x_format = workbook.stylesheet.cell_xfs[cell.style_index]
    return nil if x_format.nil?

    d_format = find_dxf_for_cell(cell, worksheet, workbook)
    Rails.logger.debug { "XlsxToTemplate: Generating style_hash for cell (row: #{cell.row}, col: #{cell.column}) with style_index: #{cell.style_index}, num_fmt_id: #{x_format.num_fmt_id}" }
    style_hash = style_to_hash(x_format, workbook, d_format)
    style_id = Digest::MD5.hexdigest(JSON.generate(style_hash))

    if styles_map[style_id].nil?
      Rails.logger.debug { "XlsxToTemplate: Adding new style to map. ID: #{style_id}, Hash: #{style_hash.inspect}" }
      styles_map[style_id] = style_hash
    else
      Rails.logger.debug { "XlsxToTemplate: Style already exists in map. ID: #{style_id}" }
    end
    style_id
  end

  def self.find_dxf_for_cell(cell, worksheet, workbook)
    row_index = cell.row
    col_index = cell.column

    return nil if worksheet.table_parts.nil?

    worksheet.table_parts.each do |table|
      next unless table.ref.include?(row_index, col_index)

      table_style = workbook.stylesheet.table_styles[table.style_info.name]
      next unless table_style

      # Determine cell's role in the table
      d_format_id = if table.header_row_count == 1 && row_index == table.ref.first_row
                      table_style.header_row_dxf_id
                    elsif table.total_row_count == 1 && row_index == table.ref.last_row
                      table_style.total_row_dxf_id
                    else
                      # Handle banded rows/columns
                      relative_row = row_index - table.ref.first_row - table.header_row_count
                      if table.banded_rows && table_style.band1_horiz_dxf_id && (relative_row % 2).zero?
                        table_style.band1_horiz_dxf_id
                      elsif table.banded_rows && table_style.band2_horiz_dxf_id && (relative_row % 2).positive?
                        table_style.band2_horiz_dxf_id
                      end
                    end

      return workbook.stylesheet.dxfs[d_format_id] if d_format_id
    end
    nil
  end

  def self.get_number_format_code(num_fmt_id, workbook)
    return nil unless num_fmt_id

    # First, try to get from custom number formats in the stylesheet
    custom_format = workbook.stylesheet&.number_formats&.find { |f| f.num_fmt_id == num_fmt_id }
    if custom_format
      format_code = custom_format.format_code
      Rails.logger.debug { "XlsxToTemplate: Found custom number format for ID #{num_fmt_id}: #{format_code}" }
      return format_code
    else
      Rails.logger.debug { "XlsxToTemplate: Custom number format not found for ID #{num_fmt_id}. Available custom formats: #{workbook.stylesheet&.number_formats.inspect}" }
    end

    # If not found in custom formats, check built-in formats
    built_in = built_in_formats[num_fmt_id]
    if built_in
      Rails.logger.debug { "XlsxToTemplate: Found built-in number format for ID #{num_fmt_id}: #{built_in}" }
    else
      Rails.logger.debug { "XlsxToTemplate: No built-in number format found for ID #{num_fmt_id}" }
    end
    built_in
  end

  def self.built_in_formats
    {
      0 => 'General',
      1 => '0',
      2 => '0.00',
      3 => '#,##0',
      4 => '#,##0.00',
      9 => '0%',
      10 => '0.00%',
      11 => '0.00E+00',
      12 => '# ?/?',
      13 => '# ??/??',
      14 => 'mm-dd-yy',
      15 => 'd-mmm-yy',
      16 => 'd-mmm',
      17 => 'mmm-yy',
      18 => 'h:mm AM/PM',
      19 => 'h:mm:ss AM/PM',
      20 => 'h:mm',
      21 => 'h:mm:ss',
      22 => 'm/d/yy h:mm',
      37 => '#,##0 ;(#,##0)',
      38 => '#,##0 ;[Red](#,##0)',
      39 => '#,##0.00;(#,##0.00)',
      40 => '#,##0.00;[Red](#,##0.00)',
      45 => 'mm:ss',
      46 => '[h]:mm:ss',
      47 => 'mmss.0',
      48 => '##0.0E+0',
      49 => '@'
    }
  end
end
