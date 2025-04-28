class KpiDateUtils
  # Determines if a string looks like a date or period label
  def self.date_like?(string)
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

  # Parses a raw period string into a Date object
  def self.parse_period(raw_period, fiscal_year_start_month: 4, raise_error: true)
    return nil if raw_period.blank?

    str = normalize_input(raw_period)

    parse_month(str) ||
      parse_quarter(str, fiscal_year_start_month) ||
      parse_year(str, fiscal_year_start_month) ||
      fallback_parse(raw_period, raise_error)
  end

  def self.normalize_input(raw_period)
    str = raw_period.to_s.strip.upcase
    str = str.gsub(/\s+/, ' ')
             .gsub(/\s*([^\w\s])\s*/, '\1')
    str.gsub(/\ASEPT(\b|\s)/, 'SEP\1')
  end

  def self.parse_month(str)
    if (match = str.match(/\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+(\d{2,4})\z/))
      month = Date::ABBR_MONTHNAMES.index(match[1].capitalize)
      year = normalize_year(match[2])
      return Date.new(year, month, -1)
    end

    if (match = str.match(/\A(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(\d{2,4})\z/))
      month = Date::MONTHNAMES.index(match[1].capitalize)
      year = normalize_year(match[2])
      return Date.new(year, month, -1)
    end

    if (match = str.match(/\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+(\d{2})\z/))
      month = Date::ABBR_MONTHNAMES.index(match[1].capitalize)
      year = normalize_year(match[2])
      return Date.new(year, month, -1)
    end

    nil
  end

  def self.parse_quarter(str, fiscal_year_start_month)
    return nil if str.blank?

    str = str.to_s.strip.upcase.gsub(/\s+/, '')

    current_year = Time.zone.today.year

    # === Case 1: Q1FY21
    if (match = str.match(/\AQ([1-4])FY(\d{2,4})\z/))
      quarter = match[1].to_i
      fiscal_year = normalize_year(match[2])
      return end_of_fiscal_quarter(fiscal_year, quarter, fiscal_year_start_month)
    end

    # === Case 2: Q1CY21 or Q1 2021
    if (match = str.match(/\AQ([1-4])(?:CY)?(\d{2,4})\z/))
      quarter = match[1].to_i
      year = normalize_year(match[2])
      return end_of_quarter(year, calendar_quarter_start_month(quarter))
    end

    # === Case 3: Q1 (no year)
    if (match = str.match(/\AQ([1-4])\z/))
      quarter = match[1].to_i
      return end_of_quarter(current_year, calendar_quarter_start_month(quarter))
    end

    # === Case 4: Jan-Mar 2021, Apr-Jun 2022, etc.
    if (match = str.match(/\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)-[A-Z]{3,4}(\d{2,4})\z/))
      start_month = month_abbr_to_month(match[1])
      year = normalize_year(match[2])
      return end_of_quarter(year, start_month)
    end

    # === Case 5: JFM 2021, AMJ 2022, etc.
    if (match = str.match(/\A(JFM|AMJ|JAS|OND)(\d{2,4})\z/))
      start_month = {
        "JFM" => 1, "AMJ" => 4, "JAS" => 7, "OND" => 10
      }[match[1]]
      year = normalize_year(match[2])
      return end_of_quarter(year, start_month)
    end

    nil
  end

  # === Helper Methods

  def self.calendar_quarter_start_month(quarter)
    case quarter
    when 1 then 1
    when 2 then 4
    when 3 then 7
    when 4 then 10
    end
  end

  def self.month_abbr_to_month(abbr)
    {
      "JAN" => 1, "FEB" => 2, "MAR" => 3, "APR" => 4,
      "MAY" => 5, "JUN" => 6, "JUL" => 7, "AUG" => 8,
      "SEP" => 9, "OCT" => 10, "NOV" => 11, "DEC" => 12
    }[abbr]
  end

  def self.end_of_fiscal_quarter(fiscal_year, quarter, fiscal_year_start_month)
    start_month = ((((quarter - 1) * 3) + fiscal_year_start_month - 1) % 12) + 1
    year_adjustment = start_month < fiscal_year_start_month ? 1 : 0
    year = fiscal_year + year_adjustment

    # Move 2 months forward to reach end month
    end_month = ((start_month + 2 - 1) % 12) + 1
    end_year_adjustment = end_month < start_month ? 1 : 0
    end_year = year + end_year_adjustment

    Date.new(end_year, end_month, -1)
  end

  def self.end_of_quarter(year, start_month)
    # Move 2 months forward
    end_month = ((start_month + 2 - 1) % 12) + 1
    end_year_adjustment = end_month < start_month ? 1 : 0
    end_year = year + end_year_adjustment

    Date.new(end_year, end_month, -1)
  end

  def self.parse_year(str, _fiscal_year_start_month)
    return nil if str.blank?

    str = str.to_s.strip.upcase.gsub(/\s+/, '')

    if (match = str.match(/\AFY(\d{2,4})(?:-?(\d{2}))?\z/))
      start_year = normalize_year(match[1])
      end_year = match[2] ? normalize_year(match[2]) : start_year
      # Use end_year for fiscal year end date
      Date.new(end_year, 3, 31)
    elsif (match = str.match(/\A(?:CY)?(\d{2,4})\z/))
      year = normalize_year(match[1])
      Date.new(year, 12, 31)
    end
  end

  def self.fallback_parse(raw_period, raise_error)
    normalized = raw_period.to_s.strip.gsub(/\s+/, ' ')

    begin
      return Date.strptime(normalized, "%b %y") if /\A[A-Za-z]{3,9}\s+\d{2}\z/.match?(normalized)

      Date.parse(normalized)
    rescue ArgumentError
      if Rails.env.test? || !raise_error
        nil
      else
        raise "Unrecognized period format: '#{raw_period}'"
      end
    end
  end

  # Parses a raw period string and returns Month, Quarter, or Year
  def self.detect_period_type(raw_period)
    return nil if raw_period.blank?

    # === Normalize input ===
    str = raw_period.to_s.strip.upcase
    str = str.gsub(/\s+/, ' ') # collapse multiple spaces
             .gsub(/\s*([^\w\s])\s*/, '\1') # remove spaces around symbols, like hyphens

    Rails.logger.debug { "Normalized string: #{str}" }

    # === Month Formats ===
    return "Month" if /\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+(\d{2,4})\z/.match?(str)
    return "Month" if /\A(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(\d{2,4})\z/.match?(str)

    # Special: 3-letter months with 2-digit years
    return "Month" if /\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+(\d{2})\z/.match?(str)
    return "Month" if /\A(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(\d{2})\z/.match?(str)

    # === Quarter Formats ===
    return "Quarter" if /\AQ([1-4])FY(\d{2,4})\z/.match?(str)
    return "Quarter" if /\AQ([1-4])(\d{2,4})\z/.match?(str)
    return "Quarter" if /\AQ([1-4])\s+(\d{2,4})\z/.match?(str)
    return "Quarter" if /\A(JAN|APR|JUL|OCT)-[A-Z]{3,4}\s+(\d{2,4})\z/.match?(str)
    return "Quarter" if /\A(JFM|AMJ|JAS|OND)\s+(\d{2,4})\z/.match?(str)

    # === Year Formats ===
    return "Year" if /\A(CY|FY)?(\d{2,4})\z/.match?(str)

    # === Fallback ===
    nil
  end

  def self.normalize_year(year)
    year = year.to_i
    if year < 100
      year >= 50 ? 1900 + year : 2000 + year
    else
      year
    end
  end

  def self.start_of_fiscal_quarter(fin_year, quarter, fiscal_start_month)
    start_month = (((fiscal_start_month - 1) + ((quarter - 1) * 3)) % 12) + 1
    year = start_month >= fiscal_start_month ? fin_year - 1 : fin_year
    Date.new(year, start_month, 1)
  end
end
