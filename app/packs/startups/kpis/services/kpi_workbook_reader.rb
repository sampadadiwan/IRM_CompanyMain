class KpiWorkbookReader
  # Struct to hold extracted KPI values
  KpiEntry = Struct.new(:worksheet, :kpi_name, :period, :value)

  def initialize(file_path, target_kpis)
    @workbook = Roo::Spreadsheet.open(file_path)
    @target_kpis = target_kpis.map { |kpi| normalize_kpi_name(kpi) }
    @results = {}
  end

  def extract_kpis
    @workbook.sheets.each do |sheet|
      Rails.logger.debug { "Processing sheet: #{sheet}" }

      begin
        @workbook.default_sheet = sheet
        header_row_index = detect_header_row
        unless header_row_index
          Rails.logger.warn("No valid header found in sheet: #{sheet}")
          next
        end

        header = clean_row(@workbook.row(header_row_index))
        process_data_rows(sheet, header_row_index + 1, header)
      rescue StandardError => e
        Rails.logger.error("Failed to process sheet #{sheet}: #{e.message}")
        next
      end
    end

    @results
  end

  private

  # Scans first N rows to find a header row that contains 2+ date-like values
  def detect_header_row
    max_scan_rows = 10

    (1..[max_scan_rows, @workbook.last_row].min).each do |i|
      row = clean_row(@workbook.row(i))
      period_candidates = row[1..] # Exclude first column (KPI label)

      date_like_count = period_candidates.count { |val| date_like?(val) }

      return i if date_like_count >= 2
    end

    nil
  end

  # Main logic to process rows of KPI data beneath the header
  def process_data_rows(sheet, start_row, header)
    seen_periods = {}

    (start_row..@workbook.last_row).each do |row_index|
      row = clean_row(@workbook.row(row_index))

      # Skip completely empty or meaningless rows
      next if row.empty? || row.all? { |cell| cell.to_s.strip.empty? }

      raw_kpi_name = row[0]
      kpi_name = normalize_kpi_name(raw_kpi_name)
      next unless @target_kpis.include?(kpi_name)

      @results[kpi_name] ||= []

      row[1..].each_with_index do |value, col_index|
        raw_period = header[col_index + 1] # Shift by 1 because row[0] is KPI name
        period = raw_period&.to_s&.strip
        next if period.blank? || value.nil? || value.to_s.strip.empty?

        # Handle duplicate periods by suffixing them
        unique_period = ensure_unique_period(period, seen_periods)

        @results[kpi_name] << KpiEntry.new(sheet, raw_kpi_name, unique_period, value)
      end
    end
  end

  # Ensures that repeated period headers don't overwrite each other
  def ensure_unique_period(period, seen_periods)
    seen_periods[period] ||= 0
    seen_periods[period] += 1

    return period if seen_periods[period] == 1

    "#{period} (#{seen_periods[period]})"
  end

  # Strips and normalizes a row's values
  def clean_row(row)
    row.map { |cell| cell&.to_s&.strip }
  end

  # Determines if a string looks like a date or period label
  def date_like?(string)
    return false if string.blank?

    patterns = [
      /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-' ]?\d{2,4}\b/i, # Jan-24, Feb 2023
      %r{\b\d{4}[-/]\d{1,2}\b}, # 2024-01 or 2024/1
      /\bQ[1-4][-' ]?\d{2,4}\b/i # Q1-24
    ]

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
    kpi.to_s.downcase.gsub(/\s+/, '') # You can also .gsub('%', '') if needed
  end
end
