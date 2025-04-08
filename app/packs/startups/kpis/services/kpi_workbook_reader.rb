class KpiWorkbookReader
  KpiEntry = Struct.new(:worksheet, :kpi_name, :period, :value)

  def initialize(file_path, target_kpis)
    @workbook = Roo::Spreadsheet.open(file_path)
    @target_kpis = target_kpis.map(&:strip).map(&:downcase)
    @results = {}
  end

  def extract_kpis
    @workbook.sheets.each do |sheet|
      Rails.logger.debug { "Processing sheet: #{sheet}" }
      @workbook.default_sheet = sheet
      header_row_index = detect_header_row
      next unless header_row_index

      header = @workbook.row(header_row_index)


      (2..@workbook.last_row).each do |row_index|
        row = @workbook.row(row_index)
        # puts "Processing row: #{row[0]}"
        # Skip completely blank rows or rows where all values are nil or empty
        next if row.compact.empty? || row.all? { |cell| cell.to_s.strip.empty? }

        kpi_name = row[0]&.to_s&.strip&.downcase
        next unless @target_kpis.include?(kpi_name)
        @results[kpi_name] ||= []

        row[1..].each_with_index do |value, col_index|
          period = header[col_index + 1] # +1 because first col is KPI name
          next if period.nil? || value.nil? || value.to_s.strip.empty?
          
          @results[kpi_name] << KpiEntry.new(sheet, row[0], period, value)
        end
      end
    end

    @results
  end

  def detect_header_row
    max_scan_rows = 10 # You can increase if needed

    (1..[max_scan_rows, @workbook.last_row].min).each do |i|
      row = @workbook.row(i)
      period_candidates = row[1..].compact.map(&:to_s).map(&:strip)

      date_like_values = period_candidates.count { |val| date_like?(val) }

      return i if date_like_values >= 2
    end

    nil # couldn't find header
  end

  def date_like?(string)
    return false if string.nil?

    patterns = [
      /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[-' ]?\d{2,4}\b/i, # Jan-24, Feb 2023
      %r{\b\d{4}[-/]\d{1,2}\b}, # 2024-01 or 2024/1
      /\bQ[1-4][-' ]?\d{2,4}\b/i # Q1-24
    ]

    return true if patterns.any? { |pat| string =~ pat }

    # Fallback: Try parsing as date
    begin
      Date.parse(string)
    rescue StandardError
      false
    end
  end
end
