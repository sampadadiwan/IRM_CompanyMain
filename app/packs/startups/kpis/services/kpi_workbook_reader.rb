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
  attr_reader :error_msg

  def initialize(document, target_kpis, user, portfolio_company)
    @document = document
    Rails.logger.debug { "Document: #{@document.name}" }
    # Normalize target KPI names for consistent matching
    @target_kpis = target_kpis.map { |kpi| normalize_kpi_name(kpi) }
    Rails.logger.debug { "Target KPIs: #{@target_kpis.inspect}" }
    @user = user

    @portfolio_company = portfolio_company
    @portfolio_company_id = portfolio_company.id
    Rails.logger.debug { "Portfolio Company: #{@portfolio_company.name}" }
    # Initialize results hash to store extracted KPI data
    @results = {}
    # Initialize error messages array to store processing errors
    @error_msg = []
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
            @error_msg << { msg:, portfolio_company: @portfolio_company, document: @document.name, document_id: @document.id }
            next
          end

          Rails.logger.debug { "Header row index: #{header_row_index}" }
          # Clean and normalize the header row
          header = clean_row(@workbook.row(header_row_index))
          # Process the data rows below the header
          process_data_rows(sheet, header_row_index + 1, header)
        rescue StandardError => e
          Rails.logger.debug e.backtrace
          # Log an error if processing the sheet fails
          msg = "Failed to process sheet '#{sheet}' in KPI import file: #{e.message}"
          Rails.logger.error(msg)
          @error_msg << { msg:, portfolio_company: @portfolio_company, document: @document.name, document_id: @document.id }
          next
        end
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
      date_like_count = period_candidates.count { |val| KpiDateUtils.date_like?(val) }

      # Return the row index if it contains 2+ date-like values
      return i if date_like_count >= 2
    end

    # Return nil if no valid header row is found
    nil
  end

  # Processes rows of KPI data beneath the header
  def process_data_rows(sheet, start_row, header)
    (start_row..@workbook.last_row).each do |row_index|
      Rails.logger.debug { "Row index: #{row_index},  #{@workbook.row(row_index)}" }
      row = clean_row(@workbook.row(row_index))
      next if row.empty? || row.all?(&:blank?)

      kpi_col = detect_kpi_name_column(start_row)
      raw_kpi_name = row[kpi_col]
      kpi_name = normalize_kpi_name(raw_kpi_name)
      next unless @target_kpis.include?(kpi_name)

      process_kpi_row(sheet, row, header, raw_kpi_name, kpi_name)
    end
  end

  def process_kpi_row(sheet, row, header, raw_kpi_name, _kpi_name)
    seen_periods = {}

    row[1..].each_with_index do |value, col_index|
      raw_period = header[col_index + 1]
      period = raw_period&.to_s&.strip
      next if period.blank? || value.blank? || value.downcase == "n/a" || value.downcase == "na"

      if seen_periods[period]
        log_duplicate_period_warning(sheet, period)
        next
      end
      seen_periods[period] = true

      parsed_period = KpiDateUtils.parse_period(period, raise_error: false)
      next unless parsed_period

      kpi_report = find_or_create_kpi_report(parsed_period)
      save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period)
    end
  end

  def log_duplicate_period_warning(sheet, period)
    msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping."
    Rails.logger.debug msg
    @error_msg << { msg:, document: @document.name, document_id: @document.id }
  end

  def find_or_create_kpi_report(parsed_period)
    @results[parsed_period] ||= KpiReport.where(
      entity_id: @portfolio_company&.entity_id,
      as_of: parsed_period,
      portfolio_company_id: @portfolio_company_id
    ).first_or_create.tap do |report|
      report.user ||= @user
      report.save! unless report.persisted?
    end
  end

  def save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period)
    kpi = kpi_report.kpis.where(
      name: raw_kpi_name,
      portfolio_company_id: @portfolio_company_id,
      entity_id: @portfolio_company&.entity_id
    ).first_or_initialize

    Rails.logger.debug { "#{kpi.persisted? ? 'Updating' : 'Creating'} KPI: #{kpi.name}, value: #{value}, for period: #{period} #{parsed_period}" }

    kpi.assign_attributes(
      value: value,
      display_value: value,
      source: "Document #{@document.id}, Sheet: #{sheet}, Period: #{period}, Date: #{parsed_period}"
    )
    kpi.save
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
