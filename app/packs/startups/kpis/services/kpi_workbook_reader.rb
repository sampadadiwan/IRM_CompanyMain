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
# is an array of `KpiEntry` structs containing the worksheet name, raw KPI name, raw period, parsed
# period date, and the extracted value.
#
# Error Handling:
# - Logs warnings for missing headers or duplicate periods.
# - Logs errors for exceptions encountered during sheet processing.
# - Collects error messages in an array for further inspection.

class KpiWorkbookReader
  # Struct to hold extracted KPI values
  KpiEntry = Struct.new(:worksheet, :kpi_name, :period_raw, :period_date, :value)

  def initialize(file_path, target_kpis)
    # Open the workbook using Roo gem
    @workbook = Roo::Spreadsheet.open(file_path)
    # Normalize target KPI names for consistent matching
    @target_kpis = target_kpis.map { |kpi| normalize_kpi_name(kpi) }
    # Initialize results hash to store extracted KPI data
    @results = {}
    # Initialize error messages array to store processing errors
    @error_msg = []
  end

  def extract_kpis
    # Iterate through each sheet in the workbook
    @workbook.sheets.each do |sheet|
      Rails.logger.debug { "Processing sheet: #{sheet}" }

      begin
        # Set the current sheet as the default sheet
        @workbook.default_sheet = sheet
        # Detect the header row in the sheet
        header_row_index = detect_header_row
        unless header_row_index
          # Log a warning if no valid header row is found
          msg = "No valid header found in sheet: #{sheet}"
          Rails.logger.warn(msg)
          @error_msg << { msg:, document: document.name, document_id: document.id }
          next
        end

        # Clean and normalize the header row
        header = clean_row(@workbook.row(header_row_index))
        # Process the data rows below the header
        process_data_rows(sheet, header_row_index + 1, header)
      rescue StandardError => e
        # Log an error if processing the sheet fails
        msg = "Failed to process sheet '#{sheet}': #{e.message}"
        Rails.logger.error(msg)
        @error_msg << { msg:, document: document.name, document_id: document.id }
        next
      end
    end

    # Return the extracted results
    @results
  end

  private

  # Scans the first N rows to find a header row containing 2+ date-like values
  def detect_header_row
    max_scan_rows = 10

    # Iterate through the first few rows to detect the header
    (1..[max_scan_rows, @workbook.last_row].min).each do |i|
      row = clean_row(@workbook.row(i))
      # Exclude the first column (assumed to be KPI label) and check the rest
      period_candidates = row[1..]

      # Count the number of date-like values in the row
      date_like_count = period_candidates.count { |val| date_like?(val) }

      # Return the row index if it contains 2+ date-like values
      return i if date_like_count >= 2
    end

    # Return nil if no valid header row is found
    nil
  end

  # Processes rows of KPI data beneath the header
  def process_data_rows(sheet, start_row, header)
    # Iterate through each row starting from the data rows
    (start_row..@workbook.last_row).each do |row_index|
      row = clean_row(@workbook.row(row_index))

      # Skip rows that are completely empty or meaningless
      next if row.empty? || row.all? { |cell| cell.to_s.strip.empty? }

      # Detect the column containing KPI names
      kpi_col = detect_kpi_name_column(start_row)
      raw_kpi_name = row[kpi_col]

      # Normalize the KPI name for matching
      kpi_name = normalize_kpi_name(raw_kpi_name)
      # Skip if the KPI is not in the target list
      next unless @target_kpis.include?(kpi_name)

      # Initialize the results array for this KPI if not already present
      @results[kpi_name] ||= []
      seen_periods = {}

      # Iterate through the remaining columns to extract KPI values
      row[1..].each_with_index do |value, col_index|
        # Get the corresponding period from the header
        raw_period = header[col_index + 1] # Shift by 1 because row[0] is KPI name
        period = raw_period&.to_s&.strip

        # Skip if the period or value is blank
        next if period.blank? || value.nil? || value.to_s.strip.empty?

        # Check for duplicate periods in the same row
        if seen_periods[period]
          msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping."
          Rails.logger.warn(msg)
          @error_msg << { msg:, document: document.name, document_id: document.id }
          next # Skip this column
        end
        seen_periods[period] = true

        # Parse the period into a date object
        parsed_period = parse_period(period)
        # Skip if the period could not be parsed
        next unless parsed_period

        # Add the extracted KPI entry to the results
        @results[kpi_name] << KpiEntry.new(sheet, raw_kpi_name, period, parsed_period, value)
      end
    end
  end

  # Strips and normalizes a row's values
  def clean_row(row)
    # Convert each cell to a string, strip whitespace, and handle nil values
    row.map { |cell| cell&.to_s&.strip }
  end

  # Determines if a string looks like a date or period label
  def date_like?(string)
    return false if string.blank?

    # Define patterns for common date-like formats
    patterns = [
      /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-' ]?\d{2,4}\b/i, # Jan-24, Feb 2023
      %r{\b\d{4}[-/]\d{1,2}\b}, # 2024-01 or 2024/1
      /\bQ[1-4][-' ]?\d{2,4}\b/i # Q1-24
    ]

    # Return true if any pattern matches
    return true if patterns.any? { |pat| string =~ pat }

    # Fallback: Try parsing as a date
    begin
      Date.parse(string)
      true
    rescue StandardError
      false
    end
  end

  # Normalize KPI names for consistent matching
  def normalize_kpi_name(kpi)
    # Convert to lowercase and remove spaces
    kpi.to_s.downcase.gsub(/\s+/, '') # You can also .gsub('%', '') if needed
  end

  # rubocop:disable Metrics/MethodLength
  # Parses a raw period string into a Date object
  def parse_period(raw_period, fiscal_year_start_month: 4)
    return nil if raw_period.blank?

    str = raw_period.to_s.strip

    # Normalize whitespace and casing
    str = str.gsub(/\s+/, ' ').strip

    # Try standard parsing first
    begin
      return Date.parse(str)
    rescue ArgumentError
      # Keep trying below
    end

    # Handle specific period formats (e.g., fiscal quarters, FYs, etc.)
    case str
    when /\A(?:Q([1-4])[- ]?FY(\d{2,4}))\z/i
      # e.g., Q3 FY23 or Q3FY2023
      quarter = ::Regexp.last_match(1).to_i
      fy = normalize_year(::Regexp.last_match(2))
      return start_of_fiscal_quarter(fy, quarter, fiscal_year_start_month)
    when /\A(?:FY(\d{2,4})[- ]?Q([1-4]))\z/i
      # e.g., FY23 Q2
      fy = normalize_year(::Regexp.last_match(1))
      quarter = ::Regexp.last_match(2).to_i
      return start_of_fiscal_quarter(fy, quarter, fiscal_year_start_month)
    when /\A([A-Za-z]{3,})[- ]?FY(\d{2,4})\z/i
      # e.g., Jan FY24
      month_name = ::Regexp.last_match(1)
      fy = normalize_year(::Regexp.last_match(2))
      begin
        return Date.parse("#{month_name} #{fy}")
      rescue ArgumentError
        return nil
      end
    when /\AFY(\d{2,4})\z/i
      # e.g., FY24 => treat as start of FY
      fy = normalize_year(::Regexp.last_match(1))
      return Date.new(fy, fiscal_year_start_month, 1)
    when /\A(?:Q([1-4])\s+(\d{2,4}))\z/i
      # e.g., "Q1 2024"
      quarter = ::Regexp.last_match(1).to_i
      year = normalize_year(::Regexp.last_match(2))
      return start_of_fiscal_quarter(year, quarter, fiscal_year_start_month)
    when /\ACY\s+(\d{2,4})\z/i
      # e.g., "CY 2024"
      year = normalize_year(::Regexp.last_match(1))
      return Date.new(year, 1, 1)
    end

    # Try parsing common date formats
    date_formats = [
      "%b-%y", "%b-%Y", "%B-%y", "%B-%Y",
      "%m-%y", "%m-%Y", "%Y-%m", "%Y/%m",
      "%b %Y", "%b %y", "%B %Y", "%B %y",
      "%m/%Y", "%m/%y", "%Y/%b", "%Y/%B"
    ]

    date_formats.each do |format|
      return Date.strptime(str, format)
    rescue ArgumentError
      next
    end

    # Log a warning if the period format is unrecognized
    Rails.logger.warn("Unrecognized period format: '#{raw_period}'")
    nil
  end
  # rubocop:enable Metrics/MethodLength

  # Normalizes a year (e.g., converts 2-digit years to 4-digit)
  def normalize_year(year)
    year = year.to_i
    if year < 100
      year >= 50 ? 1900 + year : 2000 + year
    else
      year
    end
  end

  # Calculates the start date of a fiscal quarter
  def start_of_fiscal_quarter(fyear, quarter, fiscal_start_month)
    # Calculate the start month of the quarter
    start_month = ((((quarter - 1) * 3) + fiscal_start_month - 1) % 12) + 1
    # Adjust the year based on the fiscal start month
    year = start_month >= fiscal_start_month ? fyear - 1 : fyear
    Date.new(year, start_month, 1)
  end

  # Detects the column containing KPI names
  def detect_kpi_name_column(start_row, max_cols_to_scan = 3, sample_size = 10)
    column_counts = Hash.new(0)

    # Scan a sample of rows to determine the most likely KPI column
    (start_row..[start_row + sample_size, @workbook.last_row].min).each do |row_index|
      row = clean_row(@workbook.row(row_index))
      (0...max_cols_to_scan).each do |col_index|
        cell = row[col_index]
        column_counts[col_index] += 1 unless cell.nil? || cell.to_s.strip.empty?
      end
    end

    # Return the column index (0-based) with the most non-empty values
    column_counts.max_by { |_, count| count }&.first || 0
  end
end
