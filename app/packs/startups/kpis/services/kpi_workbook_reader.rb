class KpiWorkbookReader
  # Struct to hold extracted KPI values
  KpiEntry = Struct.new(:worksheet, :kpi_name, :period_raw, :period_date, :value)


  def initialize(file_path, target_kpis)
    @workbook = Roo::Spreadsheet.open(file_path)
    @target_kpis = target_kpis.map { |kpi| normalize_kpi_name(kpi) }
    @results = {}
    @error_msg = []
  end

  def extract_kpis
    @workbook.sheets.each do |sheet|
      Rails.logger.debug { "Processing sheet: #{sheet}" }

      begin
        @workbook.default_sheet = sheet
        header_row_index = detect_header_row
        unless header_row_index
          msg = "No valid header found in sheet: #{sheet}"
          Rails.logger.warn(msg)
          @error_msg << { msg:, document: document.name, document_id: document.id }
          next
        end

        header = clean_row(@workbook.row(header_row_index))
        process_data_rows(sheet, header_row_index + 1, header)
      rescue StandardError => e
        msg = "Failed to process sheet '#{sheet}': #{e.message}"
        Rails.logger.error(msg)
        @error_msg << { msg:, document: document.name, document_id: document.id }
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
    

    (start_row..@workbook.last_row).each do |row_index|
      row = clean_row(@workbook.row(row_index))

      # Skip completely empty or meaningless rows
      next if row.empty? || row.all? { |cell| cell.to_s.strip.empty? }

      raw_kpi_name = row[0]
      kpi_name = normalize_kpi_name(raw_kpi_name)
      next unless @target_kpis.include?(kpi_name)

      @results[kpi_name] ||= []
      seen_periods = {}

      row[1..].each_with_index do |value, col_index|
        raw_period = header[col_index + 1] # Shift by 1 because row[0] is KPI name
        period = raw_period&.to_s&.strip


        next if period.blank? || value.nil? || value.to_s.strip.empty?

        if seen_periods[period]
            msg = "Warning: Duplicate period '#{period}' in sheet '#{sheet}', skipping."
            Rails.logger.warn(msg)
            @error_msg << { msg:, document: document.name, document_id: document.id }
            next # skip this column
        end
        seen_periods[period] = true

        parsed_period = parse_period(period)
        next unless parsed_period

        @results[kpi_name] << KpiEntry.new(sheet, raw_kpi_name, period, parsed_period, value)

      end
    end
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
  
    # Patterns to match:
    case str
    when /\A(?:Q([1-4])[- ]?FY(\d{2,4}))\z/i
      # e.g. Q3 FY23 or Q3FY2023
      quarter, fy = $1.to_i, normalize_year($2)
      return start_of_fiscal_quarter(fy, quarter, fiscal_year_start_month)
    when /\A(?:FY(\d{2,4})[- ]?Q([1-4]))\z/i
      # e.g. FY23 Q2
      fy, quarter = normalize_year($1), $2.to_i
      return start_of_fiscal_quarter(fy, quarter, fiscal_year_start_month)
    when /\A([A-Za-z]{3,})[- ]?FY(\d{2,4})\z/i
      # e.g. Jan FY24
      month_name, fy = $1, normalize_year($2)
      begin
        return Date.parse("#{month_name} #{fy}")
      rescue ArgumentError
        return nil
      end
    when /\AFY(\d{2,4})\z/i
      # e.g. FY24 => treat as start of FY
      fy = normalize_year($1)
      return Date.new(fy, fiscal_year_start_month, 1)
    end
  
    # Try MM/YYYY or MM-YY or YY/MM etc.
    date_formats = [
      "%b-%y", "%b-%Y", "%B-%y", "%B-%Y",
      "%m-%y", "%m-%Y", "%Y-%m", "%Y/%m",
      "%b %Y", "%b %y", "%B %Y", "%B %y",
      "%m/%Y", "%m/%y", "%Y/%b", "%Y/%B"
    ]
  
    date_formats.each do |format|
      begin
        return Date.strptime(str, format)
      rescue ArgumentError
        next
      end
    end
  
    Rails.logger.warn("Unrecognized period format: '#{raw_period}'")
    nil
  end

  def normalize_year(y)
    y = y.to_i
    y < 100 ? (y >= 50 ? 1900 + y : 2000 + y) : y
  end
  
  def start_of_fiscal_quarter(fy, quarter, fiscal_start_month)
    # e.g., FY23 + Q1 with Apr start = Apr-Jun 2022
    start_month = ((quarter - 1) * 3 + fiscal_start_month - 1) % 12 + 1
    year = start_month >= fiscal_start_month ? fy - 1 : fy
    Date.new(year, start_month, 1)
  end
  
  
end
