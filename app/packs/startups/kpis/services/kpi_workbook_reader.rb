# frozen_string_literal: true

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
  # Used by detect_tag_row to identify ACT/BUDGET/IC labels in rows below the date header.
  # Some Excel files have Actual and Budget columns side by side in the same sheet —
  # this mapping normalizes the various labels (e.g., "ACT", "Actuals", "FC") to their
  # canonical form so each column's values are saved to the correct KpiReport.
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

    # Index the @kpi_mappings by normalized reported_kpi_name for lookup.
    # Uses group_by instead of index_by because the same reported_kpi_name can
    # appear under different parents (e.g., "Enterprise" under both Net Sales and
    # Operating Cost). group_by stores an Array of mappings per normalized name,
    # and process_data_rows uses parent context to pick the correct one.
    @kpi_name_to_kpi_mappings = @kpi_mappings.group_by do |mapping|
      normalize_kpi_name(mapping.reported_kpi_name)
    end

    Rails.logger.debug { "Document: #{@document.name}" }
    # Normalize reported_kpi_name for consistent matching.
    # Using .uniq because the same reported_kpi_name under different parents
    # would otherwise appear multiple times (we only need it once for the
    # inclusion check in process_data_rows).
    @target_kpis = kpi_mappings.map { |kpi_mapping| normalize_kpi_name(kpi_mapping.reported_kpi_name) }.uniq
    Rails.logger.debug { "Target KPIs: #{@target_kpis.inspect}" }

    @portfolio_company = portfolio_company
    @portfolio_company_id = portfolio_company.id
    Rails.logger.debug { "Portfolio Company: #{@portfolio_company.name}" }
    # Initialize results hash to store extracted KPI data
    @results = {}
    # Initialize error messages array to store processing errors
    @error_msg = []
    # Initialize a set to keep track of target KPIs found in the workbook
    @found_kpis = Set.new
  end

  def extract_kpis
    @document.file.download do |file|
      file_path = file.path
      # Open the workbook using Roo gem
      @workbook = Roo::Spreadsheet.open(file_path)

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

          # Clean and normalize the header row
          header = clean_row(@workbook.row(header_row_index)).map { |h| normalize_kpi_name(h) }

          # Detect a tag row (ACT/BUDGET/IC labels) in the 1-2 rows below the header.
          # When present, each column gets its own tag so Actual and Budget values
          # are saved to separate KpiReports instead of all using the report-level tag.
          tag_detection = detect_tag_row(header_row_index)
          if tag_detection
            @column_tags = tag_detection[:column_tags]
            data_start_row = tag_detection[:tag_row_index] + 1
            Rails.logger.debug { "Tag row at #{tag_detection[:tag_row_index]}, data starts at #{data_start_row}" }
          else
            @column_tags = {}
            data_start_row = header_row_index + 1
          end

          # Detect where date columns begin in the header. All columns before
          # this index are KPI name/label columns; all from this index onward
          # are value columns. This replaces the old single-column majority vote.
          @first_date_col = detect_first_date_column(header)

          # Process the data rows below the header (and tag row, if present)
          process_data_rows(sheet, data_start_row, header)
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
  #
  # Cells must contain at least one letter or date separator (/ or -) before
  # checking date_like?. Pure numeric cells (20, 25, 30) were matching
  # Date.local_parse fallback and causing data rows to outscore the real header
  # row. Slashes and dashes are allowed so MM/DD/YYYY and YYYY-MM-DD formats
  # (common when Roo reads CSV-converted Excel files) pass through.
  #
  # @return [Integer, nil] the 1-based row index of the detected header, or nil
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
      # the same FY tag across many columns.
      # Require at least one letter or date separator (/ or -) to avoid pure
      # numeric cells (20, 25, 30) matching the lenient Date.local_parse fallback.
      # Slashes/dashes allow MM/DD/YYYY and YYYY-MM-DD formats from CSV-converted files.
      distinct_date_count = period_candidates
                            .select { |val| val.present? && val.to_s.strip.match?(%r{[a-z/-]}i) && KpiDateUtils.date_like?(val) }
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

  # Detects a tag row (ACT/BUDGET/IC labels) in the 1-2 rows immediately below
  # the date header. Some Excel files have Actual and Budget columns side by side
  # in the same sheet, with a dedicated row of labels like:
  #
  #   Header row: | Apr'25 | May'25 | Jun'25 | Apr'25 | May'25 | Jun'25 |
  #   Tag row:    | ACT    | ACT    | ACT    | BUDGET | BUDGET | BUDGET |
  #
  # When detected, each column gets its own tag so values are saved to the
  # correct KpiReport (Actual vs Budget vs IC) instead of all going to
  # the report-level tag.
  #
  # Detection criteria: >50% of non-empty cells in the candidate row must match
  # a TAG_SYNONYMS entry. This avoids false positives on data rows that happen
  # to contain words like "actual".
  #
  # Also strips trailing "Case" noise word before lookup — some companies use
  # "IC Case", "Budget Case", "Actual Case" instead of bare tags (PR #1564).
  #
  # @param header_row_index [Integer] the row index of the detected date header
  # @return [Hash, nil] { tag_row_index:, column_tags: { col_index => "Actual"|"Budget"|"IC" } }
  #   or nil if no tag row is found
  def detect_tag_row(header_row_index)
    # Check the 2 rows immediately after the header for tag labels
    [header_row_index + 1, header_row_index + 2].each do |candidate_row|
      next if candidate_row > @workbook.last_row

      row = clean_row(@workbook.row(candidate_row))
      # Skip the first column (KPI name label) and check the rest
      value_cells = row[1..] || []

      # Collect non-empty cells with their original index
      non_empty = value_cells.each_with_index.select { |cell, _| cell.present? }
      next if non_empty.size < 2

      tag_matches = {}
      non_empty.each do |cell, idx|
        # Normalize for lookup: lowercase, collapse whitespace, strip trailing "Case".
        # "IC Case" → "ic", "Budget Case" → "budget", "Actual Case" → "actual"
        normalized = cell.to_s.strip.downcase.gsub(/\s+/, ' ').gsub(/\s*case\b/, '')
        next unless TAG_SYNONYMS.key?(normalized)

        # Preserve original Excel text (title-cased) instead of canonical synonym.
        # Only normalize "Actuals" → "Actual" (singular/plural, system default).
        tag_value = cell.to_s.strip
        tag_value = "Actual" if tag_value == "Actuals"
        # +1 because value_cells starts from index 1 of the original row
        tag_matches[idx + 1] = tag_value
      end

      # Accept as tag row if >50% of non-empty cells matched a known tag synonym
      if tag_matches.size > non_empty.size / 2
        Rails.logger.debug { "Tag row detected at row #{candidate_row}: #{tag_matches.inspect}" }
        return { tag_row_index: candidate_row, column_tags: tag_matches }
      end
    end

    nil
  end

  # Processes rows of KPI data beneath the header.
  #
  # Instead of picking a single "majority" KPI name column, this method scans
  # ALL columns to the left of the first date column for KPI name matches.
  # This handles Excel layouts where parents are in column A and children are
  # in column B (or additional qualifier columns in C/D). Typically there are
  # only 1-5 columns before dates start (dates usually begin around column D/E).
  #
  # For each row, every pre-date column is checked against @target_kpis. The
  # FIRST match found (scanning left to right) is used as the KPI name for
  # that row. Rows with no matching KPI name in any pre-date column are skipped.
  #
  # Parent tracking: maintains @current_parent_mapping as rows are processed.
  # When a parent KPI is found (a mapping with no parent), it becomes the
  # current parent. When a child KPI name matches multiple mappings under
  # different parents (e.g., "Enterprise" under both Net Sales and Operating
  # Cost), the current parent is used to pick the correct mapping. This
  # avoids the need for positional hacks like @row_to_mapping.
  #
  # All KPI mappings (including parent-child hierarchy) must be pre-configured
  # via the InvestorKpiMapping bulk import — the parser does NOT auto-create
  # child mappings. It only imports values for KPIs that already have mappings.
  #
  # @param sheet [String] sheet name
  # @param start_row [Integer] first data row index (after header + optional tag row)
  # @param header [Array] cleaned/normalized header row
  def process_data_rows(sheet, start_row, header)
    # Track the current parent mapping as we scan rows top-to-bottom.
    # Used to disambiguate child KPIs with the same reported_kpi_name
    # under different parents (e.g., "Enterprise" under Net Sales vs Operating Cost).
    @current_parent_mapping = nil

    (start_row..@workbook.last_row).each do |row_index|
      Rails.logger.debug { "Row index: #{row_index},  #{@workbook.row(row_index)}" }
      row = clean_row(@workbook.row(row_index))
      # Skip empty rows or rows where all cells are blank
      next if row.empty? || row.all?(&:blank?)

      # Scan all columns before the first date column for a KPI name match.
      # The first match (left to right) wins. This handles layouts where
      # parent KPIs are in column A and child KPIs are in column B — both
      # columns are checked against existing mappings.
      raw_kpi_name = nil
      (0...@first_date_col).each do |col_index|
        cell = row[col_index]
        next if cell.blank?

        normalized = normalize_kpi_name(cell)
        if @target_kpis.include?(normalized)
          raw_kpi_name = cell
          break
        end
      end

      # Skip rows where no pre-date column matched a configured KPI mapping
      next if raw_kpi_name.blank?

      kpi_name = normalize_kpi_name(raw_kpi_name)

      # Resolve the correct InvestorKpiMapping for this row.
      # When the same reported_kpi_name exists under multiple parents,
      # use @current_parent_mapping to pick the right one.
      mapping = resolve_mapping(kpi_name)
      next unless mapping

      # Update parent tracking: if this mapping has no parent (it IS a parent),
      # remember it so subsequent child rows can be disambiguated.
      @current_parent_mapping = mapping if mapping.parent_id.blank?

      # Add the normalized KPI name to the set of found KPIs
      @found_kpis.add(kpi_name)

      # Process the row to extract KPI values, passing the resolved mapping
      process_kpi_row(sheet, row, row_index, header, raw_kpi_name, mapping)
    end
  end

  # Processes a single row of KPI data, extracting values from all date columns.
  #
  # Value extraction starts from @first_date_col (the first date column detected
  # in the header row). All columns before that are KPI name columns, all columns
  # from @first_date_col onward are value columns.
  #
  # Per-column tags: when a tag row is detected (ACT/BUDGET/IC labels below the
  # header), each column gets its own tag via @column_tags. This allows Actual and
  # Budget values in the same row to be saved to separate KpiReports. Falls back
  # to the report-level tag_list when no per-column tag is detected.
  #
  # @param sheet [String] sheet name
  # @param row [Array] cleaned row data
  # @param row_index [Integer] 1-based row index
  # @param header [Array] cleaned/normalized header row
  # @param raw_kpi_name [String] KPI name as it appears in the Excel cell
  # @param investor_kpi_mapping [InvestorKpiMapping] the resolved mapping for this row,
  #   already disambiguated by parent context in process_data_rows
  def process_kpi_row(sheet, row, row_index, header, raw_kpi_name, investor_kpi_mapping)
    seen_periods = {}
    # Start value extraction from the first date column — all columns before
    # this are KPI name/label columns and should not be treated as values.
    value_start_col = @first_date_col
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

      # Determine the tag for this column: per-column tag if detected via tag row,
      # else fall back to the report-level tag_list.
      # Note: @kpi_report.tag_list is a String (e.g., "Actual"), NOT an Array.
      # Using it directly (not .first) avoids a bug where .first on a String
      # returns just the first character ("A" instead of "Actual").
      col_tag = @column_tags[col_index + value_start_col]
      effective_tag = col_tag || @kpi_report.tag_list

      # Skip future 'Actual' KPIs
      if effective_tag&.include?('Actual') && parsed_period > Date.current
        Rails.logger.debug { "Skipping future 'Actual' KPI for period: #{period}, parsed_period: #{parsed_period}" }
        next
      end

      # Check for duplicate periods in the same row (scoped by tag so same period
      # for ACT + BUDGET columns don't collide — they go to separate KpiReports)
      dedup_key = "#{parsed_period}:#{period_type}:#{effective_tag}"
      if seen_periods[dedup_key].present?
        log_duplicate_period_warning(sheet, period, header)
        next
      else
        seen_periods[dedup_key] = true
      end

      # Find or create a KPI report for the parsed period and tag
      kpi_report = find_or_create_kpi_report(parsed_period, period, tag: effective_tag)
      # Save the KPI entry into the database, passing the already-resolved mapping
      # so save_kpi_entry doesn't need to re-lookup (and risk picking the wrong
      # mapping when duplicate reported_kpi_names exist under different parents)
      save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row, row_index, col_index,
                     mapping: investor_kpi_mapping)
    end
  end

  # Logs a warning for duplicate periods in the same row
  def log_duplicate_period_warning(sheet, period, header)
    msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping. Header: #{header.join(', ')}"
    Rails.logger.debug msg
    @error_msg << { msg: msg, document: @document.name, document_id: @document.id, portfolio_company: @portfolio_company.name, kpi_name: nil, sheet: sheet, period: period, parsed_period: nil, old_value: nil, new_value: nil, row: nil, col: nil }
  end

  # Finds or creates a KPI report for the given period and tag.
  #
  # When per-column tags are detected (ACT/BUDGET side by side), the tag parameter
  # carries the column-specific tag (e.g., "Actual" or "Budget"). This creates
  # separate KpiReports per tag so values don't collide. Falls back to the
  # report-level tag_list when no per-column tag is provided.
  #
  # The results cache key includes the tag to prevent Actual and Budget values
  # for the same period from sharing a single KpiReport.
  #
  # @param parsed_period [Date] the parsed date for this period
  # @param period [String] the raw period string from the header
  # @param tag [String, nil] canonical tag ("Actual"/"Budget"/"IC") from column detection
  # @return [KpiReport] the found or created report
  def find_or_create_kpi_report(parsed_period, period, tag: nil)
    # Detect the type of period (e.g., month, quarter, year)
    period_type = KpiDateUtils.detect_period_type(period)

    # Use the per-column tag if provided, otherwise fall back to report-level tag
    effective_tag_list = tag || @kpi_report.tag_list
    # Cache key includes tag so same period with different tags (ACT vs BUDGET)
    # get separate KpiReports
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
  # Receives the already-resolved InvestorKpiMapping via the `mapping:` keyword
  # argument, passed down from process_data_rows → process_kpi_row. This avoids
  # re-looking up by reported_kpi_name, which would fail to disambiguate when
  # the same name exists under different parents.
  #
  # Queries are scoped by investor_kpi_mapping_id to prevent value overwrites
  # when the same KPI name exists under different parents (e.g., "Enterprise"
  # under both Net Sales and Operating Cost). Each parent-child combination
  # gets its own Kpi record even if the raw Excel name is identical.
  #
  # @param kpi_report [KpiReport] the target report for this period
  # @param raw_kpi_name [String] the KPI name as it appears in the Excel cell
  # @param value [String, Numeric] the raw cell value
  # @param sheet [String] sheet name
  # @param period [String] the raw period string from the header
  # @param parsed_period [Date] the parsed date for this period
  # @param _row [Array] unused (the full row data)
  # @param row_index [Integer] 1-based row index
  # @param col_index [Integer] 0-based column index
  # @param mapping [InvestorKpiMapping] the pre-resolved mapping for this KPI row
  def save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, _row, row_index, col_index,
                     mapping: nil)
    # Use the pre-resolved mapping passed from process_kpi_row. Falls back to
    # name-based lookup only as a safety net (should not happen in normal flow).
    investor_kpi_mapping = mapping || @kpi_name_to_kpi_mappings[normalize_kpi_name(raw_kpi_name)]&.first

    standard_name = investor_kpi_mapping.standard_kpi_name

    # Find or initialize an unapproved KPI for this report, standard name, AND mapping ID.
    # Scoping by investor_kpi_mapping_id is critical when the same reported_kpi_name appears
    # under different parents — without it, the second parent's value would overwrite the first's.
    kpi = kpi_report.kpis.unapproved.where(
      name: standard_name,
      portfolio_company_id: @portfolio_company_id,
      entity_id: @portfolio_company&.entity_id,
      investor_kpi_mapping_id: investor_kpi_mapping&.id
    ).first_or_initialize

    kpi.investor_kpi_mapping = investor_kpi_mapping if investor_kpi_mapping.present?

    # Apply denomination multiplier (e.g., if mapping says "crores", multiply raw value by 10M)
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
    # Also scoped by mapping ID to handle duplicate names under different parents.
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
      investor_kpi_mapping_id: investor_kpi_mapping&.id,
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

  # Finds the 0-based index of the first date column in the header row.
  #
  # All columns before this index are treated as KPI name/label columns
  # (scanned for mapping matches). All columns from this index onward are
  # treated as value columns (date periods with numeric data).
  #
  # This replaces the old detect_kpi_name_column approach which picked a
  # single "majority" column — that approach missed KPI names in adjacent
  # columns (e.g., parents in column A, children in column B).
  #
  # Uses the same guard as detect_header_row: cells must contain at least one
  # letter or date separator (/ or -) before checking date_like? to avoid pure
  # numeric cells (20, 25, 30) matching the lenient Date.local_parse fallback.
  # Slashes/dashes allow MM/DD/YYYY and YYYY-MM-DD formats from CSV-converted files.
  #
  # Falls back to column index 1 if no date column is found (assumes column A
  # is the KPI name and column B onward are values — the most common layout).
  #
  # @param header [Array] the cleaned header row
  # @return [Integer] 0-based column index where date columns begin
  def detect_first_date_column(header)
    header.each_with_index do |cell, idx|
      # Skip the first column (always a KPI label, never a date)
      next if idx.zero?
      next if cell.blank?

      # Require at least one letter or date separator (/ or -) before checking
      # date_like? to avoid pure numeric cells matching Date.local_parse fallback
      next unless cell.to_s.strip.match?(%r{[a-z/-]}i)

      if KpiDateUtils.date_like?(cell)
        Rails.logger.debug { "First date column detected at index #{idx}: '#{cell}'" }
        return idx
      end
    end

    # Fallback: if no date column found, assume column 0 is KPI name
    # and column 1 onward are values (most common single-column layout)
    Rails.logger.warn { "No date column detected in header, falling back to column index 1" }
    1
  end

  # Resolves the correct InvestorKpiMapping for a given normalized KPI name.
  #
  # Since @kpi_name_to_kpi_mappings is a group_by hash (one name can map to
  # multiple mappings under different parents), this method picks the right one:
  #
  # 1. If only one mapping exists for this name → return it (common case)
  # 2. If multiple mappings exist (same reported_kpi_name, different parents):
  #    a. Try to find one whose parent matches @current_parent_mapping
  #    b. Fall back to the first mapping if no parent context is available
  #
  # @param kpi_name [String] the normalized KPI name
  # @return [InvestorKpiMapping, nil] the resolved mapping, or nil if not found
  def resolve_mapping(kpi_name)
    mappings = @kpi_name_to_kpi_mappings[kpi_name]
    return nil if mappings.blank?

    # Single mapping — no disambiguation needed (most common case)
    return mappings.first if mappings.size == 1

    # Multiple mappings with same reported_kpi_name but different parents.
    # Use @current_parent_mapping to pick the correct one.
    if @current_parent_mapping
      parent_match = mappings.find { |m| m.parent_id == @current_parent_mapping.id }
      return parent_match if parent_match
    end

    # Fallback: no parent context available, or no mapping matched the current parent.
    # Return the first mapping and log a warning since we can't disambiguate.
    Rails.logger.warn do
      "KpiWorkbookReader: Multiple mappings for '#{kpi_name}' but could not disambiguate " \
        "by parent (current_parent: #{@current_parent_mapping&.standard_kpi_name}). Using first match."
    end
    mappings.first
  end

  # Checks for target KPIs that were not found in any sheet and logs errors.
  # Called after all sheets have been processed to report which configured
  # KPI mappings had no matching rows in the uploaded Excel file.
  def log_missing_target_kpis
    # Determine which target KPIs were not found in the processed sheets (normalize both sides)
    missing_kpis = @target_kpis.map { |k| normalize_kpi_name(k) } - @found_kpis.to_a.map { |k| normalize_kpi_name(k) }

    return unless missing_kpis.any?

    missing_kpis.each do |missing_kpi|
      # Find the original reported KPI name for the missing normalized KPI (case-insensitive, space-insensitive)
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
