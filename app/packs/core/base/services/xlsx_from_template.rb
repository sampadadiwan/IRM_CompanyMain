# app/packs/core/documents/services/xlsx_from_template.rb

require 'axlsx'
require 'json'

class XlsxFromTemplate
  def self.generate_and_save(json_data, records, column_data_mapping, file_path: nil)
    pkg = new(json_data, records, column_data_mapping).call
    file_path ||= Rails.root.join('tmp', "export_#{Time.now.to_i}.xlsx")
    pkg.serialize(file_path)
    file_path
  end

  def self.generate_and_stream(json_data, records, column_data_mapping)
    pkg = new(json_data, records, column_data_mapping).call
    pkg.to_stream.read
  end

  def initialize(data, records, column_data_mapping)
    @data = data.is_a?(String) ? JSON.parse(data) : data
    @records = records

    # Mappings of col names to data, which is typically in the metadata in the report.
    @column_data_mapping = column_data_mapping.split(';') # break on semicolons
                                              .to_h do |pair| # ["Fund=fund.name", ...]
      key, value = pair.split("=", 2) # split on the first “=”
      [key.strip, value&.strip] # remove surrounding whitespace
    end

    @pivot_columns = @column_data_mapping['pivot']

    @package = Axlsx::Package.new
    @wb = @package.workbook
    @style_map = {}
    @format_map = {}

    load_styles
    process_column_styles # New call
  end

  def call
    @data['sheets']&.each do |sdata|
      @wb.add_worksheet(name: sdata['name']) do |sheet|
        add_headers(sheet, sdata['columnHeaders'])
        add_rows(sheet, sdata['columnHeaders'])
        apply_merges(sheet, sdata['merges'])
        set_col_widths(sheet, sdata['columnHeaders'])
        add_pivot_table(sheet, sdata['columnHeaders']) if @pivot_columns
      end
    end
    @package
  end

  private

  def load_styles
    @format_map = {} # tracks numFmt style indices

    @data['styles']&.each do |id, sh|
      font = sh['font']
      fill = sh['fill']
      alignment = sh['alignment']
      opts = {}
      opts[:b] = true if font['bold']
      opts[:sz] = font['size'].to_i if font['size']
      opts[:fg_color] = font['color'][2..] if font['color']
      opts[:bg_color] = fill['fgColor'][2..] if fill['pattern'] == 'solid' && fill['fgColor']
      opts[:alignment] = { horizontal: alignment['h']&.to_sym, wrap_text: alignment['wrap'] } if alignment
      num = sh['numFmt']
      opts[:format_code] = num if num.present? && num != 'General'

      style_idx = @wb.styles.add_style(opts)
      @style_map[id] = style_idx
      @format_map[num] = style_idx if opts[:format_code]
    end
  end

  # Processes row styles defined directly within columnHeaders and stores their indices.
  def process_column_styles
    @data['sheets']&.each do |sdata|
      sdata['columnHeaders']&.each do |c|
        if c['row_styles'].present?
          c['processed_row_style_indices'] = [] # Initialize array to store style indices
          c['row_styles'].each do |rs|
            font = rs['font']
            fill = rs['fill']
            alignment = rs['alignment']
            opts = {}
            opts[:b] = true if font['bold']
            opts[:sz] = font['size'].to_i if font['size']
            opts[:fg_color] = font['color'][2..] if font['color']
            opts[:bg_color] = fill['fgColor'][2..] if fill['pattern'] == 'solid' && fill['fgColor']
            opts[:alignment] = { horizontal: alignment['h']&.to_sym, wrap_text: alignment['wrap'] } if alignment
            num = rs['numFmt']
            opts[:format_code] = num if num.present? && num != 'General'

            style_idx = @wb.styles.add_style(opts)
            c['processed_row_style_indices'] << style_idx # Store the index
            @format_map[num] = style_idx if opts[:format_code] # Also add to format_map if it has a format code
          end
        end
      end
    end
  end

  def add_headers(sheet, cols)
    names = cols.pluck('name')
    styles = cols.map { |c| @style_map[c['header_style_id']] }
    sheet.add_row names, style: styles
  end

  def add_rows(sheet, cols)
    return if @records.blank?

    Rails.logger.debug { "XlsxFromTemplate: Adding rows for #{@records.size} records with #{cols.size} columns" }

    @records.each_with_index do |rec, i|
      values_for_row = []
      styles_for_row = []

      # Excel rows are 1-indexed. Headers are row 1. First data row (i=0) is Excel row 2.
      excel_row_for_formula = i + 2

      cols.each_with_index do |c, _col_idx|
        cell_style = nil
        if c['processed_row_style_indices'].present? # Changed from row_style_ids
          cell_style = c['processed_row_style_indices'][i % c['processed_row_style_indices'].size]
        elsif c['numFmt'].present?
          cell_style = @format_map[c['numFmt']]
        end
        styles_for_row << cell_style # Collect style for this cell

        if c['formulas'].present?
          # Add a placeholder value for now; we'll update it after the row is created.
          values_for_row << nil
        else
          begin
            field = @column_data_mapping[c['name']]
            val = field.to_s.split('.').inject(rec) { |o, m| o&.send(m) } if field.present?
          rescue StandardError => e
            Rails.logger.error "XlsxFromTemplate: Error accessing field #{c['field']}: #{e.message}"
            val = "Error"
          end

          values_for_row << if c['numFmt'].present? && c['numFmt'] != 'General' && val.respond_to?(:to_f)
                               val.to_f # Pass as float
                             else
                               val # Pass as string or other inferred type
                             end
        end
      end

      # Add the row with placeholder values and styles
      new_row = sheet.add_row values_for_row, style: styles_for_row

      # Now, iterate through the columns again and update the formula cells
      cols.each_with_index do |c, col_idx|
        next if c['formulas'].blank?

        curr_formula = c['formulas'].first.to_s
        # The formula string should NOT start with '=' when setting the .formula property
        formula_string = curr_formula.gsub(/\d+/, excel_row_for_formula.to_s).delete_prefix('=')

        # Get the cell from the newly created row and set its formula property
        new_row.cells[col_idx]
        # Get the cell from the newly created row and set its type and value
        cell = new_row.cells[col_idx]
        cell.escape_formulas = false
        cell.value = "=#{formula_string}"
      end
    end
  end

  def add_pivot_table(sheet, cols)
    return unless @pivot_columns

    data_range = "A1:#{Axlsx.col_ref(cols.size - 1)}#{@records.size + 1}"
    pivot_table_location = "#{Axlsx.col_ref(cols.size + 1)}1"

    sheet.add_pivot_table "#{pivot_table_location}:#{Axlsx.col_ref(cols.size + 8)}20", data_range do |pivot_table|
      pivot_table.rows = @pivot_columns.split(",").map(&:strip)
      # Use the first other column as the column for the pivot table
      pivot_table.columns = []
      # Use specific columns for data, or fall back to the first numeric column.
      pivot_data_cols_str = @column_data_mapping['pivot_data_cols']
      if pivot_data_cols_str.present?
        pivot_data_col_names = pivot_data_cols_str.split(',').map(&:strip)
        data_for_pivot = pivot_data_col_names.filter_map do |col_name|
          data_col = cols.find { |c| c['name'] == col_name }
          if data_col&.[]('numFmt').present? && data_col['numFmt'] != 'General'
            num_fmt_style = @format_map[data_col['numFmt']]
            if num_fmt_style
              { ref: data_col['name'], num_fmt: num_fmt_style }
            else
              { ref: data_col['name'] } # Include without num_fmt if style not found
            end
          else
            { ref: data_col['name'] } # Include without num_fmt if not numeric or general
          end
        end

        pivot_table.data = data_for_pivot if data_for_pivot.present?
      else
        # Fallback to original behavior if pivot_data_cols is not specified
        data_col = cols.find { |c| c['numFmt'].present? && c['numFmt'] != 'General' }
        if data_col
          num_fmt_style = @format_map[data_col['numFmt']]
          pivot_table.data = [{ ref: data_col['name'], num_fmt: num_fmt_style }]
        end
      end
    end
  end

  def apply_merges(sheet, merges)
    merges&.each { |m| sheet.merge_cells(m) }
  end

  def set_col_widths(sheet, cols)
    cols.each { |c| sheet.column_info[c['columnIndex']].width = c['width'] if sheet.column_info[c['columnIndex']] && c['width'] }
  end
end
