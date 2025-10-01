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

  def initialize(kpi_report, document, kpi_mappings, user, portfolio_company)
    @kpi_report = kpi_report
    @document = document
    @kpi_mappings = kpi_mappings
    @user = user
    # We need to cleanup the file before processing it to remove blank/hidden rows & cols. Note this will update the file on S3
    ConvertKpiToCsvJob.perform_now(@kpi_report.id, @user.id, @document.id, action: 'cleanup')

    # Index the @kpi_mappings by normalized KPI names for quick lookup
    @kpi_name_to_kpi_mappings = @kpi_mappings.index_by { |mapping| normalize_kpi_name(mapping.reported_kpi_name) }

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
      # After processing all sheets, check for target KPIs that were not found
      log_missing_target_kpis
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
    # Detect the column containing KPI names
    kpi_col = detect_kpi_name_column(start_row)

    (start_row..@workbook.last_row).each do |row_index|
      Rails.logger.debug { "Row index: #{row_index},  #{@workbook.row(row_index)}" }
      row = clean_row(@workbook.row(row_index))
      # Skip empty rows or rows where all cells are blank
      next if row.empty? || row.all?(&:blank?)

      raw_kpi_name = row[kpi_col]
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
    row[1..].each_with_index do |value, col_index|
      raw_period = header[col_index + 1]
      period = raw_period&.to_s&.strip
      # Skip blank periods, blank values, or invalid values like "n/a"
      next if period.blank? || value.blank? || value.downcase == "n/a" || value.downcase == "na"

      # Parse the period into a date object
      parsed_period = KpiDateUtils.parse_period(period, raise_error: false)
      unless parsed_period
        # Log a warning if the period format is unrecognized
        msg = "Unrecognized period format: '#{period}' in sheet '#{sheet}', skipping"
        Rails.logger.debug msg
        @error_msg << { msg:, document: @document.name, document_id: @document.id }
        next
      end

      period_type = KpiDateUtils.detect_period_type(period)

      # Check for duplicate periods in the same row
      if seen_periods[parsed_period.to_s + period_type.to_s].present?
        log_duplicate_period_warning(sheet, period, header)
        next
      else
        seen_periods[parsed_period.to_s + period_type.to_s] = true
      end

      # Find or create a KPI report for the parsed period
      kpi_report = find_or_create_kpi_report(parsed_period, period)
      # Save the KPI entry into the database
      save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row, row_index, col_index)
    end
  end

  # Logs a warning for duplicate periods in the same row
  def log_duplicate_period_warning(sheet, period, header)
    msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping. Header: #{header.join(', ')}"
    Rails.logger.debug msg
    @error_msg << { msg:, document: @document.name, document_id: @document.id }
  end

  # Finds or creates a KPI report for the given period
  def find_or_create_kpi_report(parsed_period, period)
    # Detect the type of period (e.g., month, quarter, year)
    period_type = KpiDateUtils.detect_period_type(period)

    key = parsed_period.to_s + period_type.to_s
    # Find or create a KPI report for the portfolio company and period
    @results[key] ||= KpiReport.where(
      entity_id: @kpi_report.entity_id,
      tag_list: @kpi_report.tag_list,
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

  # rubocop:disable Metrics/ParameterLists
  # Saves a KPI entry into the database
  def save_kpi_entry(kpi_report, raw_kpi_name, value, sheet, period, parsed_period, row, row_index, col_index)
    investor_kpi_mapping = @kpi_name_to_kpi_mappings[normalize_kpi_name(raw_kpi_name)]

    # Find or initialize a KPI entry for the given report and KPI name
    kpi = kpi_report.kpis.where(
      name: @kpi_name_to_kpi_mappings[normalize_kpi_name(raw_kpi_name)].standard_kpi_name,
      portfolio_company_id: @portfolio_company_id,
      entity_id: @portfolio_company&.entity_id
    ).first_or_initialize

    kpi.investor_kpi_mapping = investor_kpi_mapping if investor_kpi_mapping.present?

    Rails.logger.debug { "#{kpi.persisted? ? 'Updating' : 'Creating'} KPI: #{kpi.name}, value: #{value}, for period: #{period} #{parsed_period} #{row} #{col_index}" }

    # Check if the value has changed
    if kpi.persisted? && kpi.value != value.to_d
      msg = "KPI value for #{kpi.name} #{kpi.kpi_report.as_of} changed from #{kpi.value} to #{value} at row #{row_index} col #{col_index}"
      Rails.logger.debug msg
      @error_msg << { msg:, document: @document.name, document_id: @document.id }
    end
    # Assign attributes to the KPI entry
    kpi.assign_attributes(
      value: value,
      display_value: value,
      notes: "Document #{@document.id}, Sheet: #{sheet}, Period: #{period}, Date: #{parsed_period}, Row: #{row_index}, Col: #{col_index}"
    )
    # Save the KPI entry
    kpi.save
  end
  # rubocop:enable Metrics/ParameterLists

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
        # Increment the count for non-empty cells in the column
        column_counts[col_index] += 1 unless cell.nil? || cell.to_s.strip.empty?
      end
    end

    # Return the column index (0-based) with the most non-empty values
    column_counts.max_by { |_, count| count }&.first || 0
  end
end

# Checks for target KPIs that were not found in any sheet and logs errors
def log_missing_target_kpis
  # Determine which target KPIs were not found in the processed sheets
  missing_kpis = @target_kpis - @found_kpis.to_a

  if missing_kpis.any?
    missing_kpis.each do |missing_kpi|
      # Find the original reported KPI name for the missing normalized KPI
      original_kpi_mapping = @kpi_mappings.find { |mapping| normalize_kpi_name(mapping.reported_kpi_name) == missing_kpi }
      original_kpi_name = original_kpi_mapping&.reported_kpi_name || missing_kpi

      msg = "Target KPI '#{original_kpi_name}' not found in any sheet of the KPI import file."
      Rails.logger.error(msg)
      @error_msg << { msg:, portfolio_company: @portfolio_company, document: @document.name, document_id: @document.id }
    end
  end
end
