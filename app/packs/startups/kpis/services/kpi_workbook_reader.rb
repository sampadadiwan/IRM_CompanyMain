# frozen_string_literal: true

# This class, `KpiWorkbookReader`, is responsible for extracting KPI (Key Performance Indicator) data
# from an Excel workbook using the Roo gem. It processes multiple sheets in the workbook, identifies
# relevant KPI rows and columns, and extracts KPI values for specified target KPIs. The extracted data
# is returned as a structured result set.
#
# It has two entry points that share ONE code path (docs/technical/kpi_portco_upload_validation_review.md):
#
# - `extract_kpis` — the import: writes Kpi rows (as `unapproved`) and returns the KpiReports touched.
# - `validate`     — a dry run: parses exactly as the import would, writes nothing, and returns a
#                    structured verdict ({errors, warnings, summary, cells}) that the portco sees
#                    BEFORE saving and that the controller uses as the submit gate. Because it is the
#                    same code, what the portco is shown is what the import will store.
#
# Key Features:
# - Detects header rows in each sheet by scanning for rows containing date-like values.
# - Normalizes KPI names and periods for consistent matching and parsing.
# - Handles various date formats, including fiscal quarters and years (fiscal-year start comes from
#   the entity's `month_offset_for_fy` setting, portco override first).
# - Interprets cell formatting via KpiValueNormalizer (1,200 / (500) / ₹ / 1.2M / 12%) — never stores 0
#   for text; Excel error cells and ambiguous text are errors.
# - Skips hidden sheets (with a warning), flags conflicting duplicate KPI rows, checks that the period
#   the fund asked for (kpi_report.as_of + period) is present and filled, and raises plausibility
#   warnings (denomination, percentage scale, thresholds, RAG, sign flips, outliers).
#
# Usage:
#   reader = KpiWorkbookReader.new(kpi_report, document, kpi_mappings, user, portfolio_company)
#   reader.extract_kpis            # import
#   reader.validate                # dry run → { ok:, errors:, warnings:, summary:, cells: }
#
# Error Handling:
# - `issues` holds structured Issue structs (severity/code/message/sheet/row/col/kpi/period).
# - `error_msg` keeps the legacy Array<Hash> shape used by ImportKpiWorkbookJob's email report.

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

  # Denomination on the mapping → multiplier applied to raw cell values (unless the cell carries
  # its own unit suffix, in which case KpiValueNormalizer lets the explicit unit win).
  DENOMINATION_MULTIPLIERS = {
    'millions' => 1_000_000,
    'crores' => 10_000_000,
    'lakhs' => 100_000,
    'thousands' => 1_000
  }.freeze

  # workbook.xml sheet states that mean "not shown to the user"
  HIDDEN_SHEET_STATES = %w[hidden veryHidden].freeze
  # Issue codes after which nothing else can be judged (no file / not a spreadsheet / no mappings)
  FATAL_CODES = %i[no_mappings no_file not_spreadsheet].freeze
  # Warnings that the legacy import email always reported (they were "errors" before the validator
  # existed). Informational warnings added by the validator (historic periods touched, hidden sheet
  # skipped, plausibility …) are NOT emailed — they would fire on nearly every multi-period MIS.
  LEGACY_EMAIL_WARNING_CODES = %i[kpi_missing no_header unrecognized_period empty_sheet].freeze

  # Plausibility thresholds (§2.9). Warnings only — never blocking.
  DENOMINATION_SUSPECT_RATIO = 1_000        # ≥ 3 orders of magnitude vs last approved value
  OUTLIER_DEFAULT_PCT = 200                 # ±200% change when the mapping has no thresholds
  HISTORY_LOOKBACK = 3                      # how many prior approved values inform sign/scale checks
  HISTORY_MAX_AGE = 36.months               # older approved values are not a useful "please confirm" baseline

  # One structural finding. severity is :error (blocks submission) or :warning (shown, not blocking).
  Issue = Struct.new(:severity, :code, :message, :sheet, :row, :col, :kpi, :period, keyword_init: true) do
    # JSON-shaped (string keys, string severity/code) so in-memory and persisted verdicts look identical
    def to_h
      super.transform_keys(&:to_s).merge('severity' => severity.to_s, 'code' => code.to_s)
    end
  end

  attr_reader :error_msg, :issues, :cells, :periods_found

  # @param kpi_report [KpiReport] the report the upload is for (its as_of/period is "the request")
  # @param document [Document, nil] the KPIs document; nil when validating a not-yet-attached upload
  # @param kpi_mappings [Enumerable<InvestorKpiMapping>] mappings to extract (caller passes not_compute)
  # @param user [User] acting user (portco user for magic-link uploads)
  # @param portfolio_company [Investor]
  # @param update_existing_kpis [Boolean] legacy flag, kept for the job's signature
  # @param dry_run [Boolean] when true nothing is written (validate sets this itself)
  # @param file_path [String, nil] local path to the workbook when there is no Document yet
  # @param file_name [String, nil] original filename (used for messages and Roo's extension detection)
  def initialize(kpi_report, document, kpi_mappings, user, portfolio_company, update_existing_kpis: true, dry_run: false, file_path: nil, file_name: nil)
    @kpi_report = kpi_report
    @document = document
    @kpi_mappings = kpi_mappings.to_a
    @user = user
    @update_existing_kpis = update_existing_kpis
    @dry_run = dry_run
    @file_path = file_path
    @file_name = file_name || document&.file&.original_filename.presence || document&.name

    # Index the @kpi_mappings by normalized reported_kpi_name for lookup.
    # Uses group_by instead of index_by because the same reported_kpi_name can
    # appear under different parents (e.g., "Enterprise" under both Net Sales and
    # Operating Cost). group_by stores an Array of mappings per normalized name,
    # and process_data_rows uses parent context to pick the correct one.
    @kpi_name_to_kpi_mappings = @kpi_mappings.group_by do |mapping|
      normalize_kpi_name(mapping.reported_kpi_name)
    end

    Rails.logger.debug { "Document: #{@file_name}" }
    # Normalize reported_kpi_name for consistent matching.
    # Using .uniq because the same reported_kpi_name under different parents
    # would otherwise appear multiple times (we only need it once for the
    # inclusion check in process_data_rows).
    @target_kpis = @kpi_mappings.map { |kpi_mapping| normalize_kpi_name(kpi_mapping.reported_kpi_name) }.uniq
    Rails.logger.debug { "Target KPIs: #{@target_kpis.inspect}" }

    @portfolio_company = portfolio_company
    @portfolio_company_id = portfolio_company.id
    @fx_converter = KpiFxConverter.new(portfolio_company)
    Rails.logger.debug { "Portfolio Company: #{@portfolio_company.name}" }
    # Fiscal-year start (1-based month) from the existing month_offset_for_fy setting — portco's own
    # json_fields first, then the fund's EntitySetting, then the April default. Same resolution order
    # as KpiCumulative#fiscal_year_key so cumulation and import agree on what "FY26" means.
    @fiscal_year_start_month = resolve_fiscal_year_start_month
    # Initialize results hash to store extracted KPI data
    @results = {}
    # Legacy error list (Array<Hash>) consumed by ImportKpiWorkbookJob's email report
    @error_msg = []
    # Structured findings for the validation verdict
    @issues = []
    # Every matched value cell: what we read, what we will store, and how we got there
    @cells = []
    # Every date column found in any sheet: { sheet:, col:, raw:, parsed_period:, period_type:, tag: }
    @periods_found = []
    # Names of hidden sheets we skipped
    @hidden_sheets = []
    # Header row index per sheet (nil when none found) — for the summary
    @header_row_by_sheet = {}
    # Number locale detected per sheet (:western / :european / :mixed)
    @locale_by_sheet = {}
    # Initialize a set to keep track of target KPIs found in the workbook
    @found_kpis = Set.new
    # [mapping_id, parsed_period, period_type, tag] → { value:, sheet:, row:, col: } for duplicate detection
    @seen_values = {}
    # Issue codes we only want once per (sheet, col) — e.g. a future column, a duplicate header
    @once_keys = Set.new
    @processed = false
  end

  # Import entry point: parses the workbook and writes Kpi rows (unapproved). Returns the KpiReports touched.
  def extract_kpis
    process_workbook
    # Trigger KPI cumulation job after extraction (import only — never from a dry run)
    KpiCumulateJob.perform_later(@portfolio_company_id) unless @dry_run
    # Return the extracted results
    @results
  end

  # Dry-run entry point: same parsing, no writes. Returns the verdict hash (see #result).
  def validate
    @dry_run = true
    process_workbook
    result
  end

  # Structured verdict — available after either extract_kpis or validate.
  # All values are JSON-safe so the hash can be stored on kpi_reports.validation_result.
  def result
    errors = @issues.select { |i| i.severity == :error }
    warnings = @issues.select { |i| i.severity == :warning }
    {
      'ok' => errors.empty?,
      'errors' => errors.map(&:to_h),
      'warnings' => warnings.map(&:to_h),
      'summary' => summary,
      'cells' => @cells.map { |c| serialize_cell(c) },
      'generated_at' => Time.current.iso8601
    }
  end

  # True when at least one blocking issue was found.
  def errors?
    @issues.any? { |i| i.severity == :error }
  end

  private

  # Runs the whole parse once (both entry points call this; guarded so validate-then-import on the
  # same instance does not double-count).
  def process_workbook
    return if @processed

    @processed = true

    # No mappings → nothing can be imported; the fund has not configured this portco yet (§2.7).
    if @kpi_mappings.empty?
      add_issue(:error, :no_mappings,
                "Your fund has not configured which KPIs to collect from #{@portfolio_company.name} yet — please contact them before uploading.")
      return
    end

    with_workbook_file do |file_path|
      # Open the workbook using Roo gem (extension from the original filename when the temp path lacks one)
      begin
        @workbook = open_workbook(file_path)
      rescue StandardError => e
        # Not a spreadsheet Roo can open (wrong type, corrupt, renamed PDF …).
        add_issue(:error, :not_spreadsheet, "The uploaded file could not be opened as a spreadsheet (#{e.message.truncate(120)}). Please upload an .xlsx, .xls or .csv file.")
        next
      end
      @hidden_sheets = hidden_sheet_names

      # Iterate through each sheet in the workbook
      @workbook.sheets.each do |sheet|
        # Hidden sheets are the portco saying "not this one" — skip, but say so (§2.6).
        if @hidden_sheets.include?(sheet)
          add_issue(:warning, :hidden_sheet_skipped, "Sheet '#{sheet}' is hidden in the workbook and was ignored.", sheet: sheet)
          next
        end

        Rails.logger.debug { "KpiWorkbookReader: Processing sheet: #{sheet}" }
        begin
          process_sheet(sheet)
        rescue StandardError => e
          msg = if e.message.include?("invalid value for Float():")
                  "The xlsx sheet you are trying to import seems to be invalid. Please correct and try again. Sheet: '#{sheet}'"
                else
                  "Failed to process sheet '#{sheet}' in KPI import file: #{e.message}"
                end
          Rails.logger.debug e.backtrace
          Rails.logger.error(msg)
          add_issue(:error, :sheet_failed, msg, sheet: sheet)
          next
        end
      end
    end

    post_checks
  end

  # Yields a local path to the workbook: the caller-supplied path (validating a cached upload) or a
  # download of the attached Document.
  def with_workbook_file(&)
    if @file_path.present?
      yield @file_path
    elsif @document.present?
      @document.file.download { |file| yield file.path }
    else
      add_issue(:error, :no_file, "No KPI workbook has been uploaded yet.")
    end
  end

  def open_workbook(file_path)
    ext = File.extname(@file_name.to_s).delete('.').downcase.presence
    if ext.present? && File.extname(file_path).blank?
      Roo::Spreadsheet.open(file_path, extension: ext)
    else
      Roo::Spreadsheet.open(file_path)
    end
  end

  # Names of sheets marked hidden/veryHidden in workbook.xml (xlsx only; other formats expose none).
  def hidden_sheet_names
    return [] unless @workbook.respond_to?(:workbook) && @workbook.workbook.respond_to?(:sheets)

    @workbook.workbook.sheets.select { |s| HIDDEN_SHEET_STATES.include?(s['state']) }.pluck('name')
  rescue StandardError
    []
  end

  # Processes one visible sheet: header → tag row → date columns → data rows.
  def process_sheet(sheet)
    # Set the current sheet as the default sheet
    @workbook.default_sheet = sheet
    # Detect the header row in the sheet
    header_row_index = detect_header_row
    @header_row_by_sheet[sheet] = header_row_index

    unless header_row_index
      # No row with 2+ distinct period-like cells: nothing can be imported from this sheet. A cover or
      # notes sheet is normal in an MIS, so this is a warning per sheet; it becomes a blocking error in
      # post_checks only when NO sheet has a header.
      Rails.logger.warn("No valid header found in KPI import file for sheet: #{sheet}")
      if @workbook.last_row.to_i.zero?
        add_issue(:warning, :empty_sheet, "Sheet '#{sheet}' is empty — skipped.", sheet: sheet)
      else
        add_issue(:warning, :no_header,
                  "Sheet '#{sheet}': no header row with at least two period columns (e.g. Jan 2026, Feb 2026 or Q1 FY26, Q2 FY26) — sheet skipped.",
                  sheet: sheet)
      end
      return
    end

    # Clean and normalize the header row
    header = clean_row(@workbook.row(header_row_index)).map { |h| normalize_kpi_name(h) }
    raw_header = clean_row(@workbook.row(header_row_index))

    # Detect a tag row (ACT/BUDGET/IC labels) in the 1-2 rows below the header.
    # When present, each column gets its own tag so Actual and Budget values
    # are saved to separate KpiReports instead of all using the report-level tag.
    tag_detection = detect_tag_row(header_row_index)
    if tag_detection
      @column_tags = tag_detection[:column_tags]
      # Cells in the tag row that carry text we do not recognise ("Variance", "Var %", "Achievement")
      # are their own thing — not Actuals. Ignore those columns rather than letting them collide with
      # the Actual column of the same period as a duplicate.
      @ignored_tag_cols = clean_row(@workbook.row(tag_detection[:tag_row_index])).each_index.select do |i|
        i.positive? && clean_row(@workbook.row(tag_detection[:tag_row_index]))[i].present? && !@column_tags.key?(i)
      end
      data_start_row = tag_detection[:tag_row_index] + 1
      Rails.logger.debug { "Tag row at #{tag_detection[:tag_row_index]}, data starts at #{data_start_row}" }
    else
      @column_tags = {}
      @ignored_tag_cols = []
      data_start_row = header_row_index + 1
    end

    # Detect where date columns begin in the header. All columns before
    # this index are KPI name/label columns; all from this index onward
    # are value columns. This replaces the old single-column majority vote.
    @first_date_col = detect_first_date_column(header)

    # Parse every date column ONCE per sheet (not once per KPI row as before) and remember it,
    # so the requested-period check and the summary know exactly which periods the file carries.
    @sheet_periods = index_sheet_periods(sheet, raw_header)

    # Number locale for this sheet — decided from all value cells so "1,234" is read consistently.
    @locale_by_sheet[sheet] = detect_sheet_locale(data_start_row)

    # Process the data rows below the header (and tag row, if present)
    process_data_rows(sheet, data_start_row, header)
  end

  # Builds { col_index => { raw:, parsed_period:, period_type:, tag: } } for the value columns of a sheet.
  # Unrecognised headers ("Comments", "Notes") are warned about once and their values ignored.
  def index_sheet_periods(sheet, raw_header)
    periods = {}
    raw_header.each_with_index do |raw, col|
      next if col < @first_date_col
      next if raw.blank?

      if @ignored_tag_cols.include?(col)
        add_issue(:warning, :unrecognized_tag_column,
                  "Sheet '#{sheet}', column #{col_letter(col)} ('#{raw}'): its label in the Actual/Budget row is not one we recognise — column ignored.",
                  sheet: sheet, col: col, period: raw)
        next
      end

      parsed = KpiDateUtils.parse_period(raw, fiscal_year_start_month: @fiscal_year_start_month, raise_error: false)
      unless parsed
        add_issue(:warning, :unrecognized_period,
                  "Sheet '#{sheet}', column #{col_letter(col)}: header '#{raw}' is not a period we recognise — values under it are ignored.",
                  sheet: sheet, col: col, period: raw)
        next
      end

      period_type = KpiDateUtils.detect_period_type(raw)
      # NOTE: @kpi_report.tag_list is a String (e.g., "Actual"), NOT an Array.
      tag = @column_tags[col] || @kpi_report.tag_list
      info = { raw: raw, parsed_period: parsed, period_type: period_type, tag: tag }
      periods[col] = info
      @periods_found << info.merge(sheet: sheet, col: col)
    end
    periods
  end

  # Scans the value area of the sheet for strings and lets the normaliser decide the locale.
  def detect_sheet_locale(data_start_row)
    strings = []
    (data_start_row..@workbook.last_row.to_i).each do |row_index|
      row = @workbook.row(row_index)
      next if row.blank?

      row[@first_date_col..].to_a.each { |cell| strings << cell if cell.is_a?(String) }
    end
    KpiValueNormalizer.detect_locale(strings)
  end

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

    (1..[max_scan_rows, @workbook.last_row.to_i].min).each do |i|
      row = clean_row(@workbook.row(i))
      # Exclude the first column (assumed to be KPI label) and check the rest
      period_candidates = row[1..] || []

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

    # Require at least 2 distinct date-like values to qualify as a header …
    return best_row if best_score >= 2

    # … except for a single-period sheet ("KPI | Jun 2026" — the natural reply to a monthly request):
    # accept a lone period cell only when the rows beneath it carry mapped KPI names, which is what
    # rules out a stray date in a title/notes row being mistaken for the header (§2.3, option C).
    if best_score == 1 && single_period_header_backed_by_kpis?(best_row)
      add_issue_once([:single_period, @workbook.default_sheet], :warning, :single_period_header,
                     "Sheet '#{@workbook.default_sheet}' has a single period column — accepted because the KPI names below it match your fund's list.",
                     sheet: @workbook.default_sheet)
      return best_row
    end

    nil
  end

  # For a candidate header row with exactly one period cell: do the rows below contain, left of that
  # period column, at least one name that matches a configured mapping?
  def single_period_header_backed_by_kpis?(header_row_index)
    header = clean_row(@workbook.row(header_row_index))
    date_col = header.each_index.find { |i| i.positive? && header[i].present? && header[i].to_s.match?(%r{[a-z/-]}i) && KpiDateUtils.date_like?(header[i]) }
    return false if date_col.nil?

    ((header_row_index + 1)..@workbook.last_row.to_i).any? do |i|
      row = clean_row(@workbook.row(i))
      row[0...date_col].any? { |cell| cell.present? && @target_kpis.include?(normalize_kpi_name(cell)) }
    end
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

    (start_row..@workbook.last_row.to_i).each do |row_index|
      raw_row = @workbook.row(row_index)
      Rails.logger.debug { "Row index: #{row_index},  #{raw_row}" }
      row = clean_row(raw_row)
      # Skip empty rows or rows where all cells are blank
      next if row.empty? || row.all?(&:blank?)

      # Scan all columns before the first date column for a KPI name match.
      # The first match (left to right) wins. This handles layouts where
      # parent KPIs are in column A and child KPIs are in column B — both
      # columns are checked against existing mappings.
      #
      # Filled-down layouts repeat the parent on every child row ("Net Sales | Enterprise | 600"):
      # collect every match across the label columns, and when a row names both a parent and one of
      # its children, the row IS the child row (the parent label is just context).
      matches = []
      (0...@first_date_col).each do |col_index|
        cell = row[col_index]
        next if cell.blank?

        normalized = normalize_kpi_name(cell)
        matches << [col_index, cell, normalized] if @target_kpis.include?(normalized)
      end

      if matches.empty?
        # An unmapped label in the parent's column ("Customers", "Headcount") starts a section we know
        # nothing about — forget the previous parent so its children are not claimed by mistake.
        first_label = row[0...@first_date_col].find(&:present?)
        @current_parent_mapping = nil if first_label.present? && @current_parent_mapping && @kpi_mappings.none? { |m| normalize_kpi_name(m.reported_kpi_name) == normalize_kpi_name(first_label) }
        next
      end

      raw_kpi_name, kpi_name, mapping = pick_row_mapping(matches, sheet, row_index)
      next unless mapping

      # Add the normalized KPI name to the set of found KPIs
      @found_kpis.add(kpi_name)

      # Process the row to extract KPI values, passing the resolved mapping.
      # raw_row (not the stringified row) so numeric cells stay numeric for the normaliser.
      process_kpi_row(sheet, raw_row, row_index, header, raw_kpi_name, mapping)
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
  # Every value cell goes through KpiValueNormalizer; the outcome (stored value, transformations
  # applied, or the error) is recorded in @cells so the portco can see exactly how each cell was read.
  #
  # @param sheet [String] sheet name
  # @param raw_row [Array] the row as Roo returned it (numeric cells still numeric)
  # @param row_index [Integer] 1-based row index
  # @param _header [Array] cleaned/normalized header row (periods now come from @sheet_periods)
  # @param raw_kpi_name [String] KPI name as it appears in the Excel cell
  # @param investor_kpi_mapping [InvestorKpiMapping] the resolved mapping for this row,
  #   already disambiguated by parent context in process_data_rows
  def process_kpi_row(sheet, raw_row, row_index, _header, raw_kpi_name, investor_kpi_mapping)
    seen_periods = {}
    # Start value extraction from the first date column — all columns before
    # this are KPI name/label columns and should not be treated as values.
    value_start_col = @first_date_col
    denomination_multiplier = DENOMINATION_MULTIPLIERS.fetch(investor_kpi_mapping.denomination.to_s, 1)

    raw_row[value_start_col..].to_a.each_with_index do |raw_value, offset|
      col_index = offset + value_start_col
      period_info = @sheet_periods[col_index]
      # Blank / unrecognised header column, or blank cell → nothing to read
      next if period_info.nil?
      next if raw_value.nil? || (raw_value.is_a?(String) && raw_value.strip.empty?)

      period = period_info[:raw]
      parsed_period = period_info[:parsed_period]
      period_type = period_info[:period_type]
      effective_tag = period_info[:tag]

      cell = {
        sheet: sheet, row: row_index, col: col_index, ref: "#{sheet}!#{col_letter(col_index)}#{row_index}",
        kpi: raw_kpi_name, standard_kpi: investor_kpi_mapping.standard_kpi_name, mapping_id: investor_kpi_mapping.id,
        period: period, parsed_period: parsed_period, period_type: period_type, tag: effective_tag,
        raw: raw_value.is_a?(Float) && raw_value == raw_value.floor && raw_value.abs < 1e15 ? raw_value.to_i.to_s : raw_value.to_s,
        stored: nil, applied: [], status: 'ok', code: nil, old_value: nil, changed: false
      }

      parsed = KpiValueNormalizer.parse(raw_value, data_type: investor_kpi_mapping.data_type,
                                                   denomination_multiplier: denomination_multiplier,
                                                   locale: @locale_by_sheet[sheet] || :western)
      cell[:applied] = parsed.applied || []

      if parsed.error?
        cell[:status] = 'error'
        cell[:code] = parsed.code.to_s
        add_issue(:error, parsed.code, "#{cell[:ref]} (#{raw_kpi_name}, #{period}): #{parsed.message}",
                  sheet: sheet, row: row_index, col: col_index, kpi: raw_kpi_name, period: period)
        @cells << cell
        next
      end

      if parsed.skip?
        # Placeholder text ("n/a", "TBD", "—") — treated as blank, but say so once per cell.
        cell[:status] = 'skipped'
        cell[:code] = parsed.code.to_s
        if parsed.code == :placeholder
          add_issue(:warning, :placeholder_blank, "#{cell[:ref]} (#{raw_kpi_name}, #{period}): #{parsed.message}.",
                    sheet: sheet, row: row_index, col: col_index, kpi: raw_kpi_name, period: period)
        end
        @cells << cell
        next
      end

      value = parsed.value
      cell[:stored] = value
      cell[:unit_override] = parsed.unit_override
      cell[:percent_applied] = parsed.percent_applied
      parsed.warnings.each do |code|
        text = case code
               when :percent_on_non_percentage then "#{cell[:ref]} (#{raw_kpi_name}, #{period}): has a % sign but this KPI is not a percentage — stored as #{format_number(value)}."
               when :unit_overrides_denomination then "#{cell[:ref]} (#{raw_kpi_name}, #{period}): the cell's own unit was used instead of the mapping's denomination (#{investor_kpi_mapping.denomination})."
               else "#{cell[:ref]}: #{code}"
               end
        add_issue(:warning, code, text, sheet: sheet, row: row_index, col: col_index, kpi: raw_kpi_name, period: period)
      end

      # Skip future 'Actual' KPIs — but say so (once per column) instead of silently dropping them (§2.5).
      if effective_tag&.include?('Actual') && parsed_period > Date.current
        Rails.logger.debug { "Skipping future 'Actual' KPI for period: #{period}, parsed_period: #{parsed_period}" }
        add_issue_once([:future, sheet, col_index], :warning, :future_period_skipped,
                       "Sheet '#{sheet}', column #{col_letter(col_index)}: '#{period}' was read as #{parsed_period.strftime('%d-%b-%Y')}, which is in the future — Actual values under it are ignored.",
                       sheet: sheet, col: col_index, period: period)
        cell[:status] = 'future'
        @cells << cell
        next
      end

      # Check for duplicate periods in the same row (scoped by tag so same period
      # for ACT + BUDGET columns don't collide — they go to separate KpiReports)
      dedup_key = "#{parsed_period}:#{period_type}:#{effective_tag}"
      if seen_periods[dedup_key].present?
        add_issue_once([:dup_period, sheet, col_index], :error, :duplicate_period,
                       "Sheet '#{sheet}': period '#{period}' appears more than once in the header (columns #{col_letter(seen_periods[dedup_key])} and #{col_letter(col_index)}) — remove or tag one of them.",
                       sheet: sheet, col: col_index, period: period)
        cell[:status] = 'duplicate'
        @cells << cell
        next
      else
        seen_periods[dedup_key] = col_index
      end

      # Same KPI on more than one row (or sheet) for the same period: conflicting values are an
      # error (we cannot know which was meant); identical values are a warning (§2.6).
      seen_key = [investor_kpi_mapping.id, parsed_period, period_type, effective_tag]
      if (prev = @seen_values[seen_key])
        if prev[:value] == value
          add_issue_once([:dup_kpi_same, seen_key], :warning, :duplicate_kpi_row_identical,
                         "'#{raw_kpi_name}' for #{period} appears more than once (#{prev[:ref]}, #{cell[:ref]}) with the same value — imported once.",
                         sheet: sheet, row: row_index, col: col_index, kpi: raw_kpi_name, period: period)
        else
          add_issue(:error, :duplicate_kpi_row,
                    "'#{raw_kpi_name}' for #{period} appears at #{prev[:ref]} (#{format_number(prev[:value])}) and #{cell[:ref]} (#{format_number(value)}) with different values — keep one.",
                    sheet: sheet, row: row_index, col: col_index, kpi: raw_kpi_name, period: period)
          cell[:status] = 'duplicate'
        end
      else
        @seen_values[seen_key] = { value: value, ref: cell[:ref] }
      end

      # Compare with what the fund has already approved for this KPI/period (§2.5 c).
      approved = approved_value_for(investor_kpi_mapping.id, parsed_period, period_type, effective_tag)
      if approved.present?
        cell[:old_value] = approved
        cell[:changed] = approved.to_d.round(6) != value.to_d.round(6)
      end

      plausibility_checks(cell, investor_kpi_mapping, value, parsed_period, period_type, effective_tag, parsed)

      @cells << cell
      next if @dry_run || cell[:status] == 'duplicate'

      # Find or create a KPI report for the parsed period and tag
      kpi_report = find_or_create_kpi_report(parsed_period, period, tag: effective_tag)
      # Save the KPI entry into the database, passing the already-resolved mapping
      # so save_kpi_entry doesn't need to re-lookup (and risk picking the wrong
      # mapping when duplicate reported_kpi_names exist under different parents)
      save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row_index, col_index,
                     mapping: investor_kpi_mapping)
    end
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
  # The value arrives already normalised (BigDecimal, denomination/unit applied) from
  # KpiValueNormalizer — this method no longer coerces text itself.
  #
  # @param kpi_report [KpiReport] the target report for this period
  # @param raw_kpi_name [String] the KPI name as it appears in the Excel cell
  # @param value [BigDecimal] the normalised value
  # @param sheet [String] sheet name
  # @param period [String] the raw period string from the header
  # @param parsed_period [Date] the parsed date for this period
  # @param row_index [Integer] 1-based row index
  # @param col_index [Integer] 0-based column index
  # @param mapping [InvestorKpiMapping] the pre-resolved mapping for this KPI row
  def save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row_index, col_index, mapping: nil)
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

    # FX conversion: convert from portco's kpi_currency to fund's base currency.
    # Denomination scaling is already applied upstream by KpiValueNormalizer —
    # this step converts the currency using the mapping's fx_conversion_method.
    fx_rate = @fx_converter.resolve_fx_rate(investor_kpi_mapping, kpi_report)
    original_value = nil
    if fx_rate
      original_value = value.to_d
      value = value.to_d * fx_rate
    elsif investor_kpi_mapping.present? && !investor_kpi_mapping.fx_not_applicable? && @fx_converter.conversion_needed?
      kpi_currency = @fx_converter.kpi_currency
      fund_currency = @fx_converter.fund_currency
      if kpi_currency.present? && kpi_currency != fund_currency
        msg = "Missing FX rate for #{kpi_currency}→#{fund_currency} on #{kpi_report.as_of}, storing unconverted"
        Rails.logger.warn(msg)
        @error_msg << { msg: msg, portfolio_company: @portfolio_company.name, document: @document.name,
                        document_id: @document.id, kpi_name: raw_kpi_name, sheet: sheet, period: period,
                        parsed_period: parsed_period, old_value: nil, new_value: nil, row: row_index, col: col_index }
      end
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

    # Assign attributes to the KPI entry.
    # original_value: pre-conversion value in portco's kpi_currency (nil if no conversion).
    # fx_rate_used: the FX rate applied for audit trail and re-computation (nil if no conversion).
    kpi.assign_attributes(
      value: value,
      display_value: value,
      original_value: original_value,
      fx_rate_used: fx_rate,
      investor_kpi_mapping_id: investor_kpi_mapping&.id,
      notes: "Imported from Document #{@document&.id}, Sheet: #{sheet}, Period: #{period}, Date: #{parsed_period}, Row: #{row_index}, Col: #{col_index}"
    )

    kpi.save if kpi.changed?
  end

  # ---------------------------------------------------------------------------
  # Post-parse checks: things that can only be judged once the whole workbook is read
  # ---------------------------------------------------------------------------

  def post_checks
    return if @issues.any? { |i| FATAL_CODES.include?(i.code) }

    # Not a single sheet had a usable header → nothing can be read from this file at all.
    if @header_row_by_sheet.values.compact.empty?
      add_issue(:error, :no_header,
                "No sheet in the file has a header row with at least two period columns (e.g. Jan 2026, Feb 2026 or Q1 FY26, Q2 FY26). Please make sure the first row of your KPI table shows the periods and the first column the KPI names.")
      return
    end

    log_missing_target_kpis
    check_nothing_matched
    check_requested_period
    check_historic_periods
    check_children_sums
  end

  # Parent/child mappings: when a parent and ALL of its children carry a value for the same period,
  # the children should add up to the parent (within 1 %). A mismatch is a hint, not a blocker —
  # partial breakdowns (some children missing) are not checked at all.
  def check_children_sums
    ok_cells = @cells.select { |c| c[:status] == 'ok' }
    return if ok_cells.empty?

    by_mapping_period = ok_cells.group_by { |c| [c[:mapping_id], c[:parsed_period], c[:period_type], c[:tag]] }
    parents = @kpi_mappings.select { |m| m.parent_id.blank? && @kpi_mappings.count { |c| c.parent_id == m.id } >= 2 }
    parents.each do |parent|
      # A single mapped child is rarely the whole breakdown — only check parents with 2+ children
      children = @kpi_mappings.select { |m| m.parent_id == parent.id }
      by_mapping_period.each do |(mapping_id, period, type, tag), cells|
        next unless mapping_id == parent.id

        child_cells = children.map { |ch| by_mapping_period[[ch.id, period, type, tag]]&.first }
        next if child_cells.any?(&:nil?) # not every child reported for this period → no check

        parent_value = cells.first[:stored].to_d
        sum = child_cells.sum { |c| c[:stored].to_d }
        tolerance = [parent_value.abs * 0.01, 0.5].max
        next if (parent_value - sum).abs <= tolerance

        add_issue(:warning, :children_sum_mismatch,
                  "#{cells.first[:ref]} (#{parent.reported_kpi_name}, #{cells.first[:period]}): #{format_number(parent_value)} but its #{children.size} components add up to #{format_number(sum)} (#{children.map(&:reported_kpi_name).join(' + ')}). Please check.",
                  sheet: cells.first[:sheet], row: cells.first[:row], col: cells.first[:col], kpi: parent.reported_kpi_name, period: cells.first[:period])
      end
    end
  end

  # A header was found somewhere but no row matched any mapping — usually the names in the sheet
  # differ from reported_kpi_name.
  def check_nothing_matched
    return unless @found_kpis.empty?

    add_issue(:error, :no_kpis_matched,
              "None of the #{@kpi_mappings.size} KPI names your fund expects were found in the file. Expected names include: #{@kpi_mappings.first(8).map(&:reported_kpi_name).join(', ')}#{', …' if @kpi_mappings.size > 8}.")
  end

  # The shell asked for a specific period (as_of + period). Is it in the file, and is it filled? (§2.5)
  def check_requested_period
    return if @kpi_report.as_of.blank? || @kpi_report.period.blank?
    return if @found_kpis.empty? # nothing matched at all — no_kpis_matched already covers it

    req_as_of = requested_as_of
    req_type = @kpi_report.period
    req_tag = @kpi_report.tag_list
    label = requested_period_label
    # "The request" only has teeth for portco self-reporting shells; a fund user creating a report
    # and uploading a whole MIS gets the same finding as a warning, not a blocker.
    severity = @kpi_report.enable_portco_upload ? :error : :warning

    present = @periods_found.any? { |p| p[:parsed_period] == req_as_of && p[:period_type] == req_type && (req_tag.blank? || same_tag?(p[:tag], req_tag)) }

    # A Quarter / Half Year / Year request answered with MONTHLY columns that end on the requested date:
    # not the column we asked for, but KpiCumulateJob derives the longer period for mappings with
    # `cumulate` autofill. Accept with a warning naming the KPIs that will NOT be derived.
    if !present && req_type != 'Month' && @periods_found.any? { |p| p[:parsed_period] == req_as_of && p[:period_type] == 'Month' && (req_tag.blank? || same_tag?(p[:tag], req_tag)) }
      not_derived = @kpi_mappings.reject { |m| m.autofill == 'cumulate' }.map(&:reported_kpi_name)
      text = "You were asked for #{label} but the file has monthly columns instead. Monthly values will be imported and #{req_type.downcase} figures derived where your fund has configured cumulation."
      text += " Not derived (no cumulation configured): #{not_derived.first(15).join(', ')}#{', …' if not_derived.size > 15}." if not_derived.any?
      add_issue(:warning, :requested_period_derived, text, period: label)
      return
    end

    unless present
      found = @periods_found.select { |p| req_tag.blank? || same_tag?(p[:tag], req_tag) }.pluck(:raw).uniq
      add_issue(severity, :requested_period_missing,
                "#{@kpi_report.enable_portco_upload ? 'You were asked for' : 'This report is for'} #{label}, but no column in the file is that period. Periods found: #{found.first(12).join(', ')}#{', …' if found.size > 12}.",
                period: label)
      return
    end

    at_requested = @cells.select { |c| c[:parsed_period] == req_as_of && c[:period_type] == req_type && (req_tag.blank? || same_tag?(c[:tag], req_tag)) }
    filled_ids = at_requested.select { |c| c[:status] == 'ok' }.pluck(:mapping_id).uniq
    if filled_ids.empty?
      add_issue(severity, :requested_period_blank,
                "The column for #{label} is present but none of the expected KPIs has a value in it.",
                period: label)
      return
    end

    # KPIs that ARE in the file (somewhere) but blank at the requested period
    found_mapping_ids = @cells.pluck(:mapping_id).uniq
    blank_names = @kpi_mappings.select { |m| found_mapping_ids.include?(m.id) && filled_ids.exclude?(m.id) }.map(&:reported_kpi_name)
    return if blank_names.empty?

    add_issue(:warning, :requested_period_partial,
              "#{blank_names.size} KPI#{'s' if blank_names.size > 1} blank for #{label}: #{blank_names.first(15).join(', ')}#{', …' if blank_names.size > 15}.",
              period: label)
  end

  # Everything else the file touches — always imported (§2.5 decision), but shown, and flagged when a
  # touched period is already reviewed or when values differ from approved figures.
  def check_historic_periods
    ok_cells = @cells.select { |c| c[:status] == 'ok' }
    return if ok_cells.empty?

    others = ok_cells.map { |c| [c[:parsed_period], c[:period_type], c[:tag]] }.uniq.reject { |k| requested_key?(k) }
    if others.any?
      statuses = report_statuses
      reviewed = others.select { |k| statuses[k] == 'reviewed' }
      labels = others.sort_by(&:first).map { |as_of, type, tag| period_label(as_of, type, tag) }
      text = "This file also updates #{others.size} other period#{'s' if others.size > 1}: #{labels.first(12).join(', ')}#{', …' if labels.size > 12}. New values are staged for your fund to approve."
      text += " #{reviewed.size} of them #{reviewed.size == 1 ? 'is' : 'are'} already reviewed by the fund." if reviewed.any?
      add_issue(:warning, :historic_periods_touched, text)
    end

    changed = ok_cells.count { |c| c[:changed] }
    return unless changed.positive?

    add_issue(:warning, :historic_value_changed,
              "#{changed} value#{'s' if changed > 1} differ#{'s' if changed == 1} from figures your fund has already approved — see the 'How we read your file' table (old → new). They will need re-approval.")
  end

  # ---------------------------------------------------------------------------
  # Plausibility (§2.9) — warnings only
  # ---------------------------------------------------------------------------

  def plausibility_checks(cell, mapping, value, parsed_period, period_type, tag, parsed)
    ctx = { sheet: cell[:sheet], row: cell[:row], col: cell[:col], kpi: cell[:kpi], period: cell[:period] }
    prefix = "#{cell[:ref]} (#{cell[:kpi]}, #{cell[:period]})"
    history = history_before(mapping.id, period_type, tag, parsed_period)
    prev = history.last # [as_of, value] of the most recent prior approved period

    # RAG vs the configured comparator (Budget by default, prior period, or none for a flat
    # threshold) for the same period — independent of the denomination/jump history checks below.
    # See docs/technical/kpi_rag_rules_redesign.md and its "Addendum: prior-period comparator".
    if mapping.rag_configured? && same_tag?(tag, 'Actual')
      comparator_value = nil
      skip_rag = false
      if mapping.rag_comparator_prior_period?
        # `prev` was already computed above (history_before, same tag as this row) for the
        # jump/denomination checks — reuse it rather than re-querying.
        comparator_value = prev&.last
        skip_rag = comparator_value.blank? || comparator_value.to_d.zero?
      elsif mapping.rag_comparator_tag.present?
        comparator_value = approved_value_for(mapping.id, parsed_period, period_type, mapping.rag_comparator_tag)
        skip_rag = comparator_value.blank? || comparator_value.to_d.zero?
      end

      unless skip_rag
        status = begin
          RagStatusEvaluator.call(value: value.to_d, comparator_value: comparator_value, mapping: mapping)[:status]
        rescue StandardError => e
          Rails.logger.warn("KpiWorkbookReader: RAG rules on mapping #{mapping.id} could not be evaluated: #{e.message}")
          nil
        end
        comparator_phrase =
          if mapping.rag_comparator_prior_period?
            " against the prior period (#{format_number(comparator_value)})"
          elsif mapping.rag_comparator_tag.present?
            " against #{mapping.rag_comparator_tag} (#{format_number(comparator_value)})"
          else
            ''
          end
        case status
        when 'red'
          add_issue(:warning, :rag_red, "#{prefix}: #{format_number(value)} is in the red RAG band#{comparator_phrase}.", **ctx)
        when 'amber'
          add_issue(:warning, :rag_amber, "#{prefix}: #{format_number(value)} is in the amber RAG band#{comparator_phrase}.", **ctx)
        end
      end
    end

    return if prev.nil? # brand-new KPI: no history-based checks

    prev_value = prev[1].to_d
    fired = false

    # Denomination: a jump of ≥3 orders of magnitude with no explicit unit in the cell smells like
    # "sheet in rupees, mapping in crores" (or vice versa). Fires first and suppresses outlier/threshold.
    if !parsed.unit_override && !prev_value.zero? && !value.zero?
      ratio = (value.to_d / prev_value).abs
      if ratio >= DENOMINATION_SUSPECT_RATIO || ratio <= (1.to_d / DENOMINATION_SUSPECT_RATIO)
        denom = mapping.denomination.presence || 'absolute units'
        add_issue(:warning, :denomination_suspect,
                  "#{prefix}: will be stored as #{format_number(value)} — #{ratio >= 1 ? "#{format_number(ratio.round)}×" : "1/#{format_number((1 / ratio).round)} of"} the last approved value (#{format_number(prev_value)}). Your fund expects this KPI in #{denom}; is the sheet in #{denom}?",
                  **ctx)
        fired = true
      end
    end

    # Percentage scale: bare number on a percentage KPI whose magnitude class differs from history.
    if mapping.data_type == 'percentage' && !parsed.percent_applied
      hist_small = history.last(HISTORY_LOOKBACK).all? { |_, v| v.to_d.abs <= 1 }
      hist_big = history.last(HISTORY_LOOKBACK).all? { |_, v| v.to_d.abs > 1 }
      if (hist_small && value.abs > 1) || (hist_big && value.abs <= 1)
        add_issue(:warning, :percentage_scale_suspect,
                  "#{prefix}: #{format_number(value)} will display as #{format_number(value * 100)}%; previous values were around #{format_number(prev_value * 100)}%. Did you mean #{format_number(value / 100)} (#{format_number(value)}%)?",
                  **ctx)
      end
    end

    # Sign flip vs all recent history.
    recent = history.last(HISTORY_LOOKBACK).map { |_, v| v.to_d }
    if recent.size >= 2 && recent.none?(&:zero?) && !value.zero? && recent.all? { |v| v.positive? != value.positive? }
      add_issue(:warning, :sign_flip, "#{prefix}: #{format_number(value)} — previous values were all #{recent.first.positive? ? 'positive' : 'negative'}.", **ctx)
    end

    return if fired || prev_value.zero?

    # Threshold / outlier on % change vs the previous period.
    pct_change = ((value.to_d - prev_value) / prev_value.abs * 100).round(1)
    lower = mapping.lower_threshold.to_d
    upper = mapping.upper_threshold.to_d
    if lower.positive? || upper.positive?
      breached = (lower.positive? && pct_change < -lower) || (upper.positive? && pct_change > upper)
      add_issue(:warning, :threshold_breach, "#{prefix}: #{pct_change}% vs #{prev[0].strftime('%b %Y')} (#{format_number(prev_value)}) — outside the range your fund flags (−#{lower.to_i}% / +#{upper.to_i}%). Please confirm.", **ctx) if breached
    elsif pct_change.abs > OUTLIER_DEFAULT_PCT
      add_issue(:warning, :outlier, "#{prefix}: #{pct_change}% vs #{prev[0].strftime('%b %Y')} (#{format_number(prev_value)}) — please confirm.", **ctx)
    end
  end

  # ---------------------------------------------------------------------------
  # Approved-value lookups (one query, cached)
  # ---------------------------------------------------------------------------

  # { [mapping_id, as_of, period_type, tag] => value } for every approved KPI of this portco under this fund.
  def approved_index
    @approved_index ||= begin
      idx = {}
      hist = Hash.new { |h, k| h[k] = [] }
      Kpi.approved.joins(:kpi_report)
         .where(portfolio_company_id: @portfolio_company_id, investor_kpi_mapping_id: @kpi_mappings.map(&:id))
         .where(kpi_reports: { entity_id: @kpi_report.entity_id })
         .pluck(:investor_kpi_mapping_id, 'kpi_reports.as_of', 'kpi_reports.period', 'kpi_reports.tag_list', :value)
         .each do |mapping_id, as_of, period_type, tag, value|
           idx[[mapping_id, as_of, period_type, tag]] = value
           hist[[mapping_id, period_type, tag]] << [as_of, value]
         end
      hist.each_value { |arr| arr.sort_by!(&:first) }
      @approved_history = hist
      idx
    end
  end

  def approved_value_for(mapping_id, as_of, period_type, tag)
    approved_index[[mapping_id, as_of, period_type, tag]]
  end

  # Approved [as_of, value] pairs for the mapping/period-type/tag strictly before `before`, limited to
  # the last HISTORY_MAX_AGE so a 2026 upload is not judged against a 2022 figure.
  def history_before(mapping_id, period_type, tag, before)
    approved_index
    (@approved_history[[mapping_id, period_type, tag]] || []).select { |as_of, _| as_of < before && as_of >= before - HISTORY_MAX_AGE }
  end

  # { [as_of, period, tag_list] => status } for this portco's reports (to flag reviewed periods).
  def report_statuses
    @report_statuses ||= KpiReport.where(entity_id: @kpi_report.entity_id, portfolio_company_id: @portfolio_company_id)
                                  .pluck(:as_of, :period, :tag_list, :status)
                                  .to_h { |as_of, period, tag, status| [[as_of, period, tag], status] }
  end

  # Tags detected from a tag row keep the sheet's own text ("ACT", "Budget Case"); the shell uses the
  # canonical "Actual"/"Budget"/"IC". Compare through TAG_SYNONYMS so "ACT" matches an "Actual" request.
  def canonical_tag(tag)
    key = tag.to_s.strip.downcase.gsub(/\s+/, ' ').gsub(/\s*case\b/, '')
    TAG_SYNONYMS[key] || tag.to_s.strip
  end

  def same_tag?(a, b)
    canonical_tag(a) == canonical_tag(b)
  end

  # ---------------------------------------------------------------------------
  # Issue bookkeeping
  # ---------------------------------------------------------------------------

  def add_issue(severity, code, message, sheet: nil, row: nil, col: nil, kpi: nil, period: nil)
    @issues << Issue.new(severity: severity, code: code, message: message, sheet: sheet, row: row, col: col, kpi: kpi, period: period)
    (severity == :error ? Rails.logger.warn(message) : Rails.logger.debug(message))
    # Legacy shape for the job's email report — errors, plus the warnings the old importer emailed
    return unless severity == :error || LEGACY_EMAIL_WARNING_CODES.include?(code)

    @error_msg << { msg: message, portfolio_company: @portfolio_company.name, document: @file_name, document_id: @document&.id,
                    kpi_name: kpi, sheet: sheet, period: period, parsed_period: nil, old_value: nil, new_value: nil, row: row, col: col,
                    severity: severity.to_s }
  end

  # Adds the issue only the first time `key` is seen — for per-column findings hit on every KPI row.
  def add_issue_once(key, severity, code, message, **)
    return if @once_keys.include?(key)

    @once_keys << key
    add_issue(severity, code, message, **)
  end

  # ---------------------------------------------------------------------------
  # Summary / serialisation
  # ---------------------------------------------------------------------------

  def summary
    expected = @kpi_mappings.map(&:reported_kpi_name).uniq
    found = @kpi_mappings.select { |m| @found_kpis.include?(normalize_kpi_name(m.reported_kpi_name)) }.map(&:reported_kpi_name).uniq
    ok_cells = @cells.select { |c| c[:status] == 'ok' }
    req = requested_period_summary
    {
      'file_name' => @file_name,
      'sheets' => @header_row_by_sheet.keys,
      'hidden_sheets' => @hidden_sheets,
      'header_row_by_sheet' => @header_row_by_sheet,
      'locale_by_sheet' => @locale_by_sheet.transform_values(&:to_s),
      'fiscal_year_start_month' => @fiscal_year_start_month,
      'kpis_expected' => expected,
      'kpis_found' => found,
      'kpis_missing' => expected - found,
      'periods_found' => @periods_found.map { |p| period_label(p[:parsed_period], p[:period_type], p[:tag]) }.uniq,
      'requested_period' => req,
      'cells_ok' => ok_cells.size,
      'cells_error' => @cells.count { |c| c[:status] == 'error' },
      'cells_skipped' => @cells.count { |c| c[:status] == 'skipped' },
      'cells_future' => @cells.count { |c| c[:status] == 'future' },
      'cells_changed' => ok_cells.count { |c| c[:changed] },
      'other_periods' => ok_cells.map { |c| [c[:parsed_period], c[:period_type], c[:tag]] }.uniq
                                 .reject { |k| requested_key?(k) }
                                 .sort_by(&:first).map { |as_of, type, tag| period_label(as_of, type, tag) }
    }
  end

  def requested_period_summary
    return nil if @kpi_report.as_of.blank? || @kpi_report.period.blank?

    present = @periods_found.any? { |p| requested_key?([p[:parsed_period], p[:period_type], p[:tag]]) }
    at = @cells.select { |c| requested_key?([c[:parsed_period], c[:period_type], c[:tag]]) && c[:status] == 'ok' }
    {
      'label' => requested_period_label,
      'as_of' => @kpi_report.as_of.to_s,
      'period' => @kpi_report.period,
      'present' => present,
      'kpis_filled' => at.pluck(:standard_kpi).uniq.size,
      'kpis_expected' => @kpi_mappings.size
    }
  end

  def requested_period_label
    period_label(@kpi_report.as_of, @kpi_report.period, @kpi_report.tag_list)
  end

  # Is [as_of, period_type, tag] the period the shell asked for? Parsed periods are always end-of-month
  # dates, so compare against the shell's as_of normalised the same way (a shell created on the 18th
  # still means "the month ending …").
  def requested_key?(key)
    as_of, type, tag = key
    as_of == requested_as_of && type == @kpi_report.period && (@kpi_report.tag_list.blank? || same_tag?(tag, @kpi_report.tag_list))
  end

  def requested_as_of
    @requested_as_of ||= @kpi_report.as_of&.end_of_month
  end

  # "Jun 2026 (Month)" / "Mar 2026 (Quarter, Budget)"
  def period_label(as_of, type, tag)
    extra = [type, (tag if tag.present? && tag != 'Actual')].compact.join(', ')
    "#{as_of.strftime('%b %Y')} (#{extra})"
  end

  def serialize_cell(cell)
    {
      'ref' => cell[:ref], 'sheet' => cell[:sheet], 'row' => cell[:row], 'col' => cell[:col],
      'kpi' => cell[:kpi], 'standard_kpi' => cell[:standard_kpi], 'mapping_id' => cell[:mapping_id],
      'period' => cell[:period], 'parsed_period' => cell[:parsed_period]&.to_s, 'period_type' => cell[:period_type], 'tag' => cell[:tag],
      'raw' => cell[:raw], 'stored' => cell[:stored]&.to_d&.to_s('F'), 'applied' => cell[:applied],
      'status' => cell[:status], 'code' => cell[:code],
      'old_value' => cell[:old_value]&.to_d&.to_s('F'), 'changed' => cell[:changed] ? true : false,
      'is_requested' => requested_key?([cell[:parsed_period], cell[:period_type], cell[:tag]])
    }
  end

  def format_number(value)
    ActiveSupport::NumberHelper.number_to_delimited(value.to_d.round(2).to_s('F').sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\1'))
  end

  # 0-based column index → Excel letter(s)
  def col_letter(idx)
    s = +''
    n = idx.to_i + 1
    while n.positive?
      n, r = (n - 1).divmod(26)
      s.prepend((65 + r).chr)
    end
    s
  end

  # ---------------------------------------------------------------------------
  # Fiscal year
  # ---------------------------------------------------------------------------

  # See KpiDateUtils.resolve_fiscal_year_start_month for the resolution order
  # (portco json_fields → fund's EntitySetting → geo default).
  def resolve_fiscal_year_start_month
    KpiDateUtils.resolve_fiscal_year_start_month(@portfolio_company, @kpi_report.entity_id)
  end

  # ---------------------------------------------------------------------------
  # Helpers carried over unchanged
  # ---------------------------------------------------------------------------

  # Strips and normalizes a row's values
  def clean_row(row)
    # Convert each cell to a string, strip whitespace, and handle nil values
    row.to_a.map { |cell| cell&.to_s&.strip }
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

    # Single mapping — but still verify parent context when available.
    # If @current_parent_mapping is set and this mapping belongs to a different
    # parent, skip it. E.g., "North" has one mapping under Revenue, but the
    # parser is currently inside Contribution — importing would overwrite
    # Revenue-North's value with Contribution-North's value.
    if mappings.size == 1
      mapping = mappings.first
      if @current_parent_mapping && mapping.parent_id.present? && mapping.parent_id != @current_parent_mapping.id
        Rails.logger.debug do
          "KpiWorkbookReader: Skipping '#{kpi_name}' — belongs to parent " \
            "'#{mapping.parent&.standard_kpi_name}', not current parent '#{@current_parent_mapping.standard_kpi_name}'."
        end
        return nil
      end
      return mapping
    end

    # Multiple mappings with same reported_kpi_name but different parents.
    # Use @current_parent_mapping to pick the correct one.
    if @current_parent_mapping
      parent_match = mappings.find { |m| m.parent_id == @current_parent_mapping.id }
      return parent_match if parent_match
    end

    # Parent context exists but no mapping matched — this KPI name belongs to a
    # different (unmapped) parent section. Skip it to avoid overwriting the correct
    # mapped parent's child value. E.g., "North" under Contribution (unmapped)
    # must not overwrite "Revenue - North" saved earlier from the Revenue section.
    if @current_parent_mapping
      Rails.logger.debug do
        "KpiWorkbookReader: Skipping '#{kpi_name}' — current parent " \
          "'#{@current_parent_mapping.standard_kpi_name}' has no matching child mapping."
      end
      return nil
    end

    # No parent context at all — genuinely ambiguous. Refuse to guess (§ parent/child hardening):
    # tell the user which parents this name lives under and skip the row.
    add_issue_once([:parent_unknown, kpi_name], :warning, :parent_context_unknown,
                   "'#{mappings.first.reported_kpi_name}' is mapped under #{mappings.filter_map { |m| m.parent&.standard_kpi_name }.join(' and ')}, but the sheet does not show which section this row belongs to — row skipped. Put it under its parent row.",
                   kpi: mappings.first.reported_kpi_name)
    nil
  end

  # FX rate resolution and period start date calculation are delegated to KpiFxConverter
  # (initialized as @fx_converter) so the same logic is reusable by KpiCurrencyRecomputeJob.

  # From all mapping matches on one row (label columns only), decide which one the row represents:
  # - a parent and one of its own children on the same row → the child (filled-down layout), and the
  #   parent becomes the current context;
  # - otherwise the leftmost match, resolved against the current parent context (unchanged behaviour).
  # Returns [raw_name, normalized_name, mapping] — mapping nil when the row should be skipped.
  def pick_row_mapping(matches, _sheet, _row_index)
    # Parents named on this row (a name is a parent if some mapping with that name has no parent_id)
    matches.each do |_pcol, _pcell, pnorm|
      parent = (@kpi_name_to_kpi_mappings[pnorm] || []).find { |m| m.parent_id.blank? }
      next unless parent

      matches.each do |_ccol, ccell, cnorm|
        next if cnorm == pnorm

        child = (@kpi_name_to_kpi_mappings[cnorm] || []).find { |m| m.parent_id == parent.id }
        next unless child

        # The parent label on this row is context for the child; remember it and use the child.
        @current_parent_mapping = parent
        return [ccell, cnorm, child]
      end
    end

    _col, cell, normalized = matches.first
    mapping = resolve_mapping(normalized)
    # Update parent tracking: if this mapping has no parent (it IS a parent), remember it so
    # subsequent child rows can be disambiguated.
    @current_parent_mapping = mapping if mapping && mapping.parent_id.blank?
    [cell, normalized, mapping]
  end

  # Checks for target KPIs that were not found in any sheet and records a warning for each.
  # Called after all sheets have been processed to report which configured
  # KPI mappings had no matching rows in the uploaded Excel file.
  # A missing KPI is a warning (not blocking) — the fund decides whether partial reports are acceptable.
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

      add_issue(:warning, :kpi_missing, "Target KPI '#{original_kpi_name}' not found in any sheet of the KPI import file.", kpi: original_kpi_name)
    end
  end
end
