require 'rubyXL'
require 'rubyXL/convenience_methods'

# This class, `KpiWorkbookReader`, is responsible for extracting KPI (Key Performance Indicator) data
# from an Excel workbook using the Roo gem. It processes multiple sheets in the workbook, identifies
# relevant KPI rows and columns, and extracts KPI values for specified target KPIs. The extracted data
# is returned as a structured result set.
#
# Key Features:
# - Detects header rows in each sheet by scanning for rows containing date-like values.
# - Normalizes KPI names and periods for consistent matching and parsing.
# - Handles various date formats, including fiscal quarters and years.
# - Processes rows of data beneath the header to extract KPI values for target KPIs.
# - Logs warnings and errors for invalid or unrecognized data formats.
#
# Usage:
# 1. Initialize the class with the file path to the workbook and a list of target KPI names.
# 2. Call the `extract_kpis` method to process the workbook and retrieve the extracted KPI data.
#
# Example:
#   reader = KpiWorkbookReader.new("tmp/MIS Sample2.xlsx", "Revenue from operations, GRoss Profit, Net Current Assets, Orders MoMGrowth, EBITDA".split(",").map(&:strip))
#   results = reader.extract_kpis
#
# The extracted results are stored in a hash where each key is a normalized KPI name, and the value
# is an array of `Kpi` structs containing the worksheet name, raw KPI name, raw period, parsed
# period date, and the extracted value.
#
# Error Handling:
# - Logs warnings for missing headers or duplicate periods.
# - Logs errors for exceptions encountered during sheet processing.
# - Collects error messages in an array for further inspection.

class KpiWorkbookReader
  # Maps common abbreviations found in Excel tag rows to canonical KpiReport tag values.
  TAG_SYNONYMS = {
    "act" => "Actual",
    "actual" => "Actual",
    "actuals" => "Actual",
    "budget" => "Budget",
    "bud" => "Budget",
    "budgeted" => "Budget",
    "forecast" => "Budget",
    "fc" => "Budget",
    "ic" => "IC",
    "investment committee" => "IC"
  }.freeze

  attr_reader :error_msg

  def initialize(kpi_report, document, kpi_mappings, user, portfolio_company, update_existing_kpis: true)
    @kpi_report = kpi_report
    @document = document
    @kpi_mappings = kpi_mappings
    @user = user
    @update_existing_kpis = update_existing_kpis
    # We need to cleanup the file before processing it to remove blank/hidden rows & cols. Note this will update the file on S3
    # ConvertKpiToCsvJob.perform_now(@kpi_report.id, @user.id, @document.id, action: 'cleanup')

    # Index the @kpi_mappings by normalized KPI names for quick lookup
    # Normalize kpi_mappings to be case-/space-insensitive
    @kpi_name_to_kpi_mappings = @kpi_mappings.index_by do |mapping|
      normalize_kpi_name(mapping.reported_kpi_name)
    end

    Rails.logger.debug { "Document: #{@document.name}" }
    # Normalize reported_kpi_name for consistent matching
    @target_kpis = kpi_mappings.map { |kpi_mapping| normalize_kpi_name(kpi_mapping.reported_kpi_name) }
    Rails.logger.debug { "Target KPIs: #{@target_kpis.inspect}" }

    @portfolio_company = portfolio_company
    @portfolio_company_id = portfolio_company.id
    Rails.logger.debug { "Portfolio Company: #{@portfolio_company.name}" }
    # Initialize results hash to store extracted KPI data
    @results = {}
    # Initialize error messages array to store processing errors
    @error_msg = []
    # Row-level mapping for child KPIs with duplicate names across parents
    # (e.g., "Enterprise" under both Net Sales and Operating Cost).
    # Keys are [sheet_name, row_index], values are InvestorKpiMapping records.
    @row_to_mapping = {}

    # Column index for column-based child KPIs (e.g., children in column B while
    # parents are in column A). Set by detect_column_based_children, nil if not detected.
    @child_col = nil

    # Initialize a set to keep track of target KPIs found in the workbook
    @found_kpis = Set.new
  end

  def extract_kpis
    @document.file.download do |file|
      file_path = file.path
      # Open the workbook using Roo gem
      @workbook = Roo::Spreadsheet.open(file_path)
      @indent_map = build_indent_map(file_path)

      # Iterate through each sheet in the workbook
      @workbook.sheets.each do |sheet|
        Rails.logger.debug { "KpiWorkbookReader: Processing sheet: #{sheet}" }
        begin
          # Set the current sheet as the default sheet
          @workbook.default_sheet = sheet
          # Detect the header row in the sheet
          header_row_index = detect_header_row

          unless header_row_index
            # Log a warning if no valid header row is found
            msg = "No valid header found in KPI import file for sheet: #{sheet}"
            Rails.logger.warn(msg)
            @error_msg << { msg: msg, portfolio_company: @portfolio_company.name, document: @document.name, document_id: @document.id, kpi_name: nil, sheet: sheet, period: nil, parsed_period: nil, old_value: nil, new_value: nil, row: nil, col: nil }
            next
          end

          Rails.logger.debug { "Header row index: #{header_row_index}" }
          # Clean and normalize the header row
          header = clean_row(@workbook.row(header_row_index)).map { |h| normalize_kpi_name(h) }

          # Detect a tag row (ACT/BUDGET labels) below the header
          tag_detection = detect_tag_row(header_row_index)
          if tag_detection
            @column_tags = tag_detection[:column_tags]
            data_start_row = tag_detection[:tag_row_index] + 1
            Rails.logger.debug { "Tag row at #{tag_detection[:tag_row_index]}, data starts at #{data_start_row}" }
          else
            @column_tags = {}
            data_start_row = header_row_index + 1
          end

          # Detect the column containing KPI names (needed for column-based child detection)
          kpi_col = detect_kpi_name_column(data_start_row)

          # Detect parent-child relationships from indent formatting BEFORE
          # processing data rows — this auto-creates InvestorKpiMapping records
          # for indented child KPIs so the parser can import their values.
          detect_parent_child_relationships(sheet, data_start_row, kpi_col)
          # Process the data rows below the header (and tag row, if present).
          # Pass kpi_col so process_data_rows uses the same primary KPI column
          # detected before child mappings expanded @target_kpis.
          process_data_rows(sheet, data_start_row, header, kpi_col)
        rescue StandardError => e
          msg = if e.message.include?("invalid value for Float():")
                  "The xlsx sheet you are trying to import seems to be invalid. Please correct and try again. Sheet: '#{sheet}'"
                else
                  "Failed to process sheet '#{sheet}' in KPI import file: #{e.message}"
                end
          Rails.logger.debug e.backtrace
          Rails.logger.error(msg)
          @error_msg << { msg: msg, portfolio_company: @portfolio_company.name, document: @document.name, document_id: @document.id, kpi_name: nil, sheet: sheet, period: nil, parsed_period: nil, old_value: nil, new_value: nil, row: nil, col: nil }
          next
        end
      end
      # After processing all sheets, check for target KPIs that were not found
      log_missing_target_kpis
    end

    # Trigger KPI cumulation job after extraction
    KpiCumulateJob.perform_later(@portfolio_company_id)
    # Return the extracted results
    @results
  end

  private

  # Scans the first N rows and returns the row with the most DISTINCT date-like
  # values. This replaces the old "return first row with 2+ date-like cells"
  # approach which broke on multi-row headers common in Indian financial Excel
  # files. For example, a P&L sheet might have:
  #
  #   Row 4: | FY 25-26 Actual | FY 25-26 Actual | FY 25-26 Budget | ...
  #   Row 5: | Apr'25          | May'25          | June'25         | ...
  #   Row 6: | ACT             | ACT             | BUDGET          | ...
  #
  # Row 4 has date-like values ("FY 25-26" matches date_like?) but they repeat —
  # only ~3 distinct values. Row 5 has 12+ distinct monthly periods. By scoring
  # on distinct count, Row 5 wins. For simple single-row headers, the best row
  # and the first row are the same, so there is no regression.
  def detect_header_row
    max_scan_rows = 10
    best_row = nil
    best_score = 0

    (1..[max_scan_rows, @workbook.last_row].min).each do |i|
      row = clean_row(@workbook.row(i))
      # Exclude the first column (assumed to be KPI label) and check the rest
      period_candidates = row[1..]

      # Count distinct date-like values — a real period header row has many
      # unique periods (Apr, May, Jun...) while a grouping/label row repeats
      # the same FY tag across many columns
      distinct_date_count = period_candidates
                            .select { |val| val.present? && !val.to_s.strip.match?(/\A[\d.]+\z/) && KpiDateUtils.date_like?(val) }
                            .map { |val| val.to_s.strip.downcase }
                            .uniq
                            .size

      if distinct_date_count > best_score
        best_score = distinct_date_count
        best_row = i
      end
    end

    # Require at least 2 distinct date-like values to qualify as a header
    best_row if best_score >= 2
  end

  # @param header_row_index [Integer] the row index of the detected date header
  # @return [Hash, nil] { tag_row_index:, column_tags: { col_index => "Actual"|"Budget"|"IC" } }
  def detect_tag_row(header_row_index)
    [header_row_index + 1, header_row_index + 2].each do |candidate_row|
      next if candidate_row > @workbook.last_row

      row = clean_row(@workbook.row(candidate_row))
      value_cells = row[1..] || []

      non_empty = value_cells.each_with_index.select { |cell, _| cell.present? }
      next if non_empty.size < 2

      tag_matches = {}
      non_empty.each do |cell, idx|
        normalized = cell.to_s.strip.downcase.gsub(/\s+/, ' ')
        canonical_tag = TAG_SYNONYMS[normalized]
        tag_matches[idx + 1] = canonical_tag if canonical_tag
      end

      if tag_matches.size > non_empty.size / 2
        Rails.logger.debug { "Tag row detected at row #{candidate_row}: #{tag_matches.inspect}" }
        return { tag_row_index: candidate_row, column_tags: tag_matches }
      end
    end

    nil
  end

  # Processes rows of KPI data beneath the header.
  # Reads the KPI name from either the primary column or the child column
  # (for column-based parent-child layouts where children are in a separate column).
  # kpi_col is passed from extract_kpis to ensure the same primary column is used
  # after child mappings have been registered (which expands @target_kpis and would
  # cause detect_kpi_name_column to pick the child column instead).
  def process_data_rows(sheet, start_row, header, kpi_col)
    (start_row..@workbook.last_row).each do |row_index|
      Rails.logger.debug { "Row index: #{row_index},  #{@workbook.row(row_index)}" }
      row = clean_row(@workbook.row(row_index))
      # Skip empty rows or rows where all cells are blank
      next if row.empty? || row.all?(&:blank?)

      # For column-based children: if primary column is blank, read from child column
      raw_kpi_name = row[kpi_col]
      raw_kpi_name = row[@child_col] if raw_kpi_name.blank? && @child_col

      # Normalize the KPI name for consistent matching
      kpi_name = normalize_kpi_name(raw_kpi_name)

      # Skip rows where the KPI name is not in the target list
      next unless @target_kpis.include?(kpi_name)

      # Add the normalized KPI name to the set of found KPIs
      @found_kpis.add(kpi_name)

      # Process the row to extract KPI values
      process_kpi_row(sheet, row, row_index, header, raw_kpi_name, kpi_name)
    end
  end

  # Processes a single row of KPI data
  def process_kpi_row(sheet, row, row_index, header, raw_kpi_name, _kpi_name)
    seen_periods = {}
    # Iterate through each value in the row (excluding the KPI name column)
    # Start value extraction after the KPI name column(s). For column-based children,
    # skip both column A (parent) and column B (child) to avoid treating the child
    # name as a numeric value.
    value_start_col = @child_col ? @child_col + 1 : 1
    row[value_start_col..].each_with_index do |value, col_index|
      raw_period = header[col_index + value_start_col]

      period = raw_period&.to_s&.strip
      # Skip blank periods, blank values, or invalid values like "n/a"
      next if period.blank? || value.blank? || value.downcase == "n/a" || value.downcase == "na"

      # Parse the period into a date object
      parsed_period = KpiDateUtils.parse_period(period, raise_error: false)
      unless parsed_period
        # Log a warning if the period format is unrecognized
        msg = "Unrecognized period format: '#{period}' in sheet '#{sheet}', skipping"
        Rails.logger.debug msg
        @error_msg << { msg: msg, document: @document.name, document_id: @document.id, portfolio_company: @portfolio_company.name, kpi_name: raw_kpi_name, sheet: sheet, period: period, parsed_period: parsed_period, old_value: nil, new_value: nil, row: row_index, col: col_index }
        next
      end

      period_type = KpiDateUtils.detect_period_type(period)

      # Determine the tag for this column: per-column tag if detected, else report-level tag
      col_tag = @column_tags[col_index + value_start_col]

      effective_tag = col_tag || @kpi_report.tag_list

      # Skip future 'Actual' KPIs
      if effective_tag&.include?('Actual') && parsed_period > Date.current
        Rails.logger.debug { "Skipping future 'Actual' KPI for period: #{period}, parsed_period: #{parsed_period}" }
        next
      end

      # Check for duplicate periods in the same row (scoped by tag to allow same period for ACT + BUDGET)
      dedup_key = "#{parsed_period}:#{period_type}:#{effective_tag}"
      if seen_periods[dedup_key].present?
        log_duplicate_period_warning(sheet, period, header)
        next
      else
        seen_periods[dedup_key] = true
      end

      # Find or create a KPI report for the parsed period and tag
      kpi_report = find_or_create_kpi_report(parsed_period, period, tag: effective_tag)
      # Save the KPI entry into the database
      save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row, row_index, col_index)
    end
  end

  # Logs a warning for duplicate periods in the same row
  def log_duplicate_period_warning(sheet, period, header)
    msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping. Header: #{header.join(', ')}"
    Rails.logger.debug msg
    @error_msg << { msg: msg, document: @document.name, document_id: @document.id, portfolio_company: @portfolio_company.name, kpi_name: nil, sheet: sheet, period: period, parsed_period: nil, old_value: nil, new_value: nil, row: nil, col: nil }
  end

  # @param tag [String, nil] canonical tag ("Actual"/"Budget"/"IC") from column detection
  def find_or_create_kpi_report(parsed_period, period, tag: nil)
    # Detect the type of period (e.g., month, quarter, year)
    period_type = KpiDateUtils.detect_period_type(period)

    effective_tag_list = tag || @kpi_report.tag_list
    key = "#{parsed_period}:#{period_type}:#{effective_tag_list}"
    # Find or create a KPI report for the portfolio company, period, and tag
    @results[key] ||= KpiReport.where(
      entity_id: @kpi_report.entity_id,
      tag_list: effective_tag_list,
      as_of: parsed_period,
      period: period_type,
      portfolio_company_id: @portfolio_company_id
    ).first_or_create.tap do |report|
      # Assign the user if the report is newly created
      report.user ||= @user
      report.save! unless report.persisted?
    end

    Rails.logger.debug { "KPI Report: #{period} #{parsed_period} #{period_type} #{@portfolio_company.name}" }
    Rails.logger.debug @results[key]
    @results[key]
  end

  # Saves a single KPI data point into the database as an unapproved record.
  #
  # Uses row-level mapping (@row_to_mapping) for positional disambiguation when
  # the same KPI name appears under different parents (e.g., "Enterprise" under
  # both Net Sales and Operating Cost). Falls back to name-based lookup for
  # parent KPIs and single-occurrence children.
  #
  # Scopes the KPI query by investor_kpi_mapping_id to prevent value overwrites
  # when duplicate names exist — each parent-child combination gets its own
  # Kpi record even if the raw Excel name is identical.
  #
  # @param kpi_report [KpiReport] the target report for this period
  # @param raw_kpi_name [String] the KPI name as it appears in the Excel cell
  # @param value [String, Numeric] the raw cell value
  # @param sheet [String] sheet name (used as part of @row_to_mapping key)
  # @param period [String] the raw period string from the header
  # @param parsed_period [Date] the parsed date for this period
  # @param _row [Array] unused (the full row data)
  # @param row_index [Integer] 1-based row index (used as part of @row_to_mapping key)
  # @param col_index [Integer] 0-based column index
  def save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, _row, row_index, col_index)
    # Prefer row-level mapping (handles duplicate names under different parents,
    # e.g., "Enterprise" under Net Sales vs "Enterprise" under Operating Cost)
    investor_kpi_mapping = @row_to_mapping[[sheet, row_index]] ||
                           @kpi_name_to_kpi_mappings[normalize_kpi_name(raw_kpi_name)]

    standard_name = investor_kpi_mapping.standard_kpi_name
    kpi = kpi_report.kpis.unapproved.where(
      name: standard_name,
      portfolio_company_id: @portfolio_company_id,
      entity_id: @portfolio_company&.entity_id,
      investor_kpi_mapping_id: investor_kpi_mapping&.id
    ).first_or_initialize

    kpi.investor_kpi_mapping = investor_kpi_mapping if investor_kpi_mapping.present?

    if investor_kpi_mapping.present? && investor_kpi_mapping.denomination.present?
      multiplier = case investor_kpi_mapping.denomination
                   when 'millions' then 1_000_000
                   when 'crores' then 10_000_000
                   when 'lakhs' then 100_000
                   when 'thousands' then 1_000
                   else 1
                   end
      value = value.to_d * multiplier
    end

    # Check if an approved KPI with the same value already exists.
    # If it does, we don't even need to create an unapproved one.
    # Scoped by mapping ID to handle duplicate names under different parents.
    existing_approved = kpi_report.kpis.approved.find_by(
      name: standard_name,
      portfolio_company_id: @portfolio_company_id,
      investor_kpi_mapping_id: investor_kpi_mapping&.id
    )

    if existing_approved && existing_approved.value.to_d.round(6) == value.to_d.round(6)
      Rails.logger.debug { "Approved KPI value for #{standard_name} #{kpi_report.as_of} is same, skipping" }
      return
    end

    Rails.logger.debug { "#{kpi.persisted? ? 'Updating' : 'Creating'} Unapproved KPI: #{kpi.name}, value: #{value}" }

    # Assign attributes to the KPI entry
    kpi.assign_attributes(
      value: value,
      display_value: value,
      notes: "Imported from Document #{@document.id}, Sheet: #{sheet}, Period: #{period}, Date: #{parsed_period}, Row: #{row_index}, Col: #{col_index}"
    )

    kpi.save if kpi.changed?
  end

  # Strips and normalizes a row's values
  def clean_row(row)
    # Convert each cell to a string, strip whitespace, and handle nil values
    row.map { |cell| cell&.to_s&.strip }
  end

  # Normalize KPI names for consistent matching
  def normalize_kpi_name(kpi)
    # Convert to lowercase and remove spaces
    kpi.to_s.downcase.gsub(/\s+/, '') # You can also .gsub('%', '') if needed
  end

  # Detects the column containing KPI names
  def detect_kpi_name_column(start_row, max_cols_to_scan = 3, sample_size = 10)
    target_kpi_set = @target_kpis.to_set
    kpi_match_counts = Hash.new(0)
    non_empty_counts = Hash.new(0)

    # Scan a sample of rows to determine the most likely KPI column
    (start_row..[start_row + sample_size, @workbook.last_row].min).each do |row_index|
      row = clean_row(@workbook.row(row_index))
      (0...max_cols_to_scan).each do |col_index|
        cell = row[col_index]
        next if cell.nil? || cell.to_s.strip.empty?

        non_empty_counts[col_index] += 1
        # Favor columns whose values match target KPI names
        kpi_match_counts[col_index] += 1 if target_kpi_set.include?(normalize_kpi_name(cell))
      end
    end

    # Prefer the column with the most KPI name matches; fall back to non-empty count.
    if kpi_match_counts.values.any?(&:positive?)
      # Use [count, -col] to prefer leftmost column when counts are equal
      kpi_match_counts.max_by { |col, count| [count, -col] }&.first || 0
    else
      # Use [count, -col] to prefer leftmost column when counts are equal
      non_empty_counts.max_by { |col, count| [count, -col] }&.first || 0
    end
  end

  # Builds a map of Excel cell indent levels from the workbook using rubyXL.
  #
  # Reads `cell.text_indent` formatting from the first non-empty cell in
  # columns A-C of each row. The Roo gem (used for value extraction) cannot
  # read cell formatting, so rubyXL is used for this one-time pass.
  #
  # Row indices are converted from rubyXL 0-based to Roo 1-based (+1).
  #
  # @param file_path [String] path to the Excel file on disk
  # @return [Hash<Array(String, Integer), Integer>] `{ [sheet_name, row_index] => indent_level }`
  #   Only entries with indent > 0 are stored.
  def build_indent_map(file_path)
    indent_map = {}
    workbook = RubyXL::Parser.parse(file_path)
    workbook.worksheets.each do |ws|
      ws.each_with_index do |row, row_idx|
        next unless row

        cell = (0..2).filter_map { |c| row[c] }.first
        next unless cell

        indent = cell.text_indent.to_i
        indent_map[[ws.sheet_name, row_idx + 1]] = indent if indent.positive?
      end
    end
    indent_map
  end

  # Detects whether the sheet uses a two-column parent-child layout where parent
  # KPI names are in one column (e.g., A) and child KPI names are in the adjacent
  # column (e.g., B). In this pattern, when column A has a value column B is empty,
  # and when column B has a value column A is empty.
  #
  # Detection criteria: at least 2 rows where the primary KPI column is blank but
  # the next column has a non-numeric, non-date text value.
  #
  # @param start_row [Integer] first data row index
  # @param kpi_col [Integer] the primary KPI name column index (from detect_kpi_name_column)
  # @return [Integer, nil] the child column index, or nil if not detected
  def detect_column_based_children(start_row, kpi_col)
    child_col = kpi_col + 1
    child_hits = 0

    (start_row..[start_row + 20, @workbook.last_row].min).each do |row_index|
      row = clean_row(@workbook.row(row_index))
      next if row.empty? || row.all?(&:blank?)

      primary_blank = row[kpi_col].blank?
      child_value = row[child_col]&.strip

      # Row where primary column is blank but next column has a text value
      # (not purely numeric and not a date) — likely a child KPI name
      next unless primary_blank && child_value.present? &&
                  !child_value.match?(/\A[\d.,]+\z/) &&
                  !KpiDateUtils.date_like?(child_value)

      child_hits += 1
    end

    if child_hits >= 1
      Rails.logger.info { "KpiWorkbookReader: Column-based children detected in column #{child_col}" }
      child_col
    end
  end

  # Walks data rows to detect parent-child KPI hierarchy from either:
  # 1. Excel cell indentation (indent > 0 in @indent_map), OR
  # 2. Column-based layout (parent in column A, child in column B)
  #
  # Maintains a parent stack of `[indent_level, kpi_name]` pairs. When a child
  # row is detected (by either method), auto-creates a child mapping via
  # {#create_child_mapping} and registers it for value extraction.
  # Subtotal rows (matching `/\Atotal\s/i`) are skipped unless they are
  # explicitly configured as target KPIs.
  #
  # Must run BEFORE {#process_data_rows} so child mappings exist when values are extracted.
  #
  # @param sheet [String] sheet name (used as part of @row_to_mapping key)
  # @param start_row [Integer] first data row index (after header and optional tag row)
  # @param kpi_col [Integer] the primary KPI name column index
  # @return [void]
  def detect_parent_child_relationships(sheet, start_row, kpi_col = 0)
    parent_stack = []
    # Check if this sheet uses a two-column parent-child layout
    # (e.g., parents in column A, children in column B)
    @child_col = detect_column_based_children(start_row, kpi_col)

    (start_row..@workbook.last_row).each do |row_index|
      row = clean_row(@workbook.row(row_index))
      next if row.empty? || row.all?(&:blank?)

      indent = @indent_map[[sheet, row_index]] || 0
      primary_name = row[kpi_col]&.strip
      child_name = @child_col ? row[@child_col]&.strip : nil

      # Determine if this is a column-based child row:
      # primary column is blank, child column has a text value
      is_column_child = @child_col && primary_name.blank? && child_name.present?

      # Get the effective KPI name for this row
      raw_name = is_column_child ? child_name : primary_name
      next if raw_name.blank?

      # For column-based children, treat them as indent level 1
      effective_indent = is_column_child ? 1 : indent

      parent_stack.pop while parent_stack.any? && parent_stack.last[0] >= effective_indent

      if raw_name.match?(/\Atotal\s/i) && @target_kpis.exclude?(normalize_kpi_name(raw_name))
        Rails.logger.debug { "KpiWorkbookReader: Subtotal row detected: '#{raw_name}' (sheet: #{sheet}, row: #{row_index})" }
        next
      end

      # Child detected by indent OR by column position
      if parent_stack.any? && (effective_indent.positive? || is_column_child)
        parent_name = parent_stack.last[1]
        parent_mapping = @kpi_name_to_kpi_mappings[normalize_kpi_name(parent_name)]
        child_mapping = parent_mapping ? create_child_mapping(raw_name, parent_mapping) : nil

        if child_mapping
          register_mapping(child_mapping)
          @row_to_mapping[[sheet, row_index]] = child_mapping
          detection_method = is_column_child ? 'column' : 'indent'
          Rails.logger.info do
            "KpiWorkbookReader: Auto-created child mapping '#{raw_name}' under '#{parent_name}' " \
              "(sheet: #{sheet}, row: #{row_index}, method: #{detection_method})"
          end
        end
      end

      parent_stack.push([effective_indent, raw_name])
    end
  end

  # Creates or updates an InvestorKpiMapping as a child of the given parent mapping.
  #
  # Child mappings use a "Parent - Child" naming convention for `standard_kpi_name`
  # (e.g., "Net Sales - Enterprise", "Operating Cost - Enterprise"). This provides:
  # - **Uniqueness** — same child name under different parents becomes distinct
  # - **Searchability** — "Net Sales - Enterprise" is meaningful in cross-company search
  # - **Consistency** — matches fund managers' existing manual naming practice
  #
  # The `reported_kpi_name` retains the raw Excel name ("Enterprise") for import matching.
  #
  # Handles three scenarios:
  # 1. **Re-upload** — finds existing mapping by prefixed standard name (idempotent)
  # 2. **Existing flat mapping** — a parentless mapping with the raw name gets adopted
  #    under this parent, and its standard name is updated to the prefixed format
  # 3. **New child** — creates a mapping inheriting category, data_type, and denomination
  #    from the parent
  #
  # Note: The ancestry gem stores hierarchy in a string `ancestry` column, not a `parent_id`
  # column. The `parent` and `parent_id` methods are virtual accessors provided by the gem.
  # `parent:` works in `update!` and create calls (gem setter), but not in query keys.
  #
  # @param child_name [String] raw KPI name from the Excel cell
  # @param parent_mapping [InvestorKpiMapping] the parent's mapping record (must be persisted)
  # @return [InvestorKpiMapping, nil] the child mapping, or nil if creation failed
  def create_child_mapping(child_name, parent_mapping)
    normalized = normalize_kpi_name(child_name)
    existing = @kpi_name_to_kpi_mappings[normalized]
    # Already registered with the correct parent — no work needed
    return existing if existing && existing.parent_id == parent_mapping.id

    # Standard name uses "Parent - Child" format for uniqueness and searchability.
    # e.g., "Enterprise" under Net Sales becomes "Net Sales - Enterprise",
    # while "Enterprise" under Operating Cost becomes "Operating Cost - Enterprise".
    prefixed_name = "#{parent_mapping.standard_kpi_name} - #{child_name.strip}"

    # Search by standard name (parent-prefixed) for idempotent re-uploads
    mapping = InvestorKpiMapping.find_by(
      entity: parent_mapping.entity,
      investor: parent_mapping.investor,
      standard_kpi_name: prefixed_name
    )
    return mapping if mapping

    # Check if a flat (parentless) mapping exists with the raw name — adopt it
    flat_mapping = InvestorKpiMapping.find_by(
      entity: parent_mapping.entity,
      investor: parent_mapping.investor,
      reported_kpi_name: child_name.strip,
      ancestry: nil
    )
    if flat_mapping
      flat_mapping.update!(parent: parent_mapping, standard_kpi_name: prefixed_name)
      return flat_mapping
    end

    # No match — create a new record
    InvestorKpiMapping.create!(
      entity: parent_mapping.entity,
      investor: parent_mapping.investor,
      reported_kpi_name: child_name.strip,
      standard_kpi_name: prefixed_name,
      parent: parent_mapping,
      category: parent_mapping.category,
      data_type: parent_mapping.data_type,
      denomination: parent_mapping.denomination,
      show_in_report: true
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn { "KpiWorkbookReader: Failed to create child mapping '#{child_name}': #{e.message}" }
    nil
  end

  # Registers a newly created child mapping so the parser imports its values.
  #
  # Adds the mapping to @kpi_name_to_kpi_mappings (keyed by normalized
  # reported_kpi_name) and to @target_kpis so {#process_data_rows} recognises
  # the child's raw Excel name as a valid KPI to import.
  #
  # Note: for duplicate child names (e.g., "Enterprise" under two parents),
  # the last registration wins in @kpi_name_to_kpi_mappings. The @row_to_mapping
  # hash provides the correct positional disambiguation in {#save_kpi_entry}.
  #
  # @param mapping [InvestorKpiMapping] the child mapping to register
  # @return [void]
  def register_mapping(mapping)
    normalized = normalize_kpi_name(mapping.reported_kpi_name)
    @kpi_name_to_kpi_mappings[normalized] = mapping
    @target_kpis << normalized unless @target_kpis.include?(normalized)
  end

  # Checks for target KPIs that were not found in any sheet and logs errors
  def log_missing_target_kpis
    missing_kpis = @target_kpis.map { |k| normalize_kpi_name(k) } - @found_kpis.to_a.map { |k| normalize_kpi_name(k) }

    return unless missing_kpis.any?

    missing_kpis.each do |missing_kpi|
      original_kpi_mapping = @kpi_mappings.find do |mapping|
        normalize_kpi_name(mapping.reported_kpi_name) == normalize_kpi_name(missing_kpi)
      end
      original_kpi_name = original_kpi_mapping&.reported_kpi_name || missing_kpi

      msg = "Target KPI '#{original_kpi_name}' not found in any sheet of the KPI import file."
      Rails.logger.error(msg)
      @error_msg << {
        msg: msg,
        portfolio_company: @portfolio_company.name,
        document: @document.name,
        document_id: @document.id,
        kpi_name: original_kpi_name,
        sheet: nil,
        period: nil,
        parsed_period: nil,
        old_value: nil,
        new_value: nil,
        row: nil,
        col: nil
      }
    end
  end
end
