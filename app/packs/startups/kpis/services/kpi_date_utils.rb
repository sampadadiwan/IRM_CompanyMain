class KpiDateUtils

    
  # rubocop:disable Metrics/MethodLength
  # Parses a raw period string into a Date object
  def self.parse_period(raw_period, fiscal_year_start_month: 4)
    return nil if raw_period.blank?
  
    str = raw_period.to_s.strip.upcase.gsub(/\s+/, ' ')
  
    # === Month Formats ===
    if str =~ /\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)\s+(\d{2,4})\z/
      month = Date::ABBR_MONTHNAMES.index(::Regexp.last_match(1).capitalize)
      year = normalize_year(::Regexp.last_match(2))
      return Date.new(year, month, 1)
    end
  
    if str =~ /\A(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(\d{2,4})\z/
      month = Date::MONTHNAMES.index(::Regexp.last_match(1).capitalize)
      year = normalize_year(::Regexp.last_match(2))
      return Date.new(year, month, 1)
    end
  
    # === Quarter Formats ===
  
    # Q[1-4] FYyy or Q[1-4]FYyy
    if str =~ /\AQ([1-4])\s*FY\s*(\d{2,4})\z/ || str =~ /\AQ([1-4])FY(\d{2,4})\z/
      quarter = ::Regexp.last_match(1).to_i
      fy = normalize_year(::Regexp.last_match(2))
      return start_of_fiscal_quarter(fy, quarter, fiscal_year_start_month)
    end
  
    # Q[1-4] YYYY (e.g., "Q1 2024")
    if str =~ /\AQ([1-4])\s+(\d{2,4})\z/
      quarter = ::Regexp.last_match(1).to_i
      year = normalize_year(::Regexp.last_match(2))
      return start_of_fiscal_quarter(year, quarter, fiscal_year_start_month)
    end
  
    # Jan-Mar 2021, Apr-Jun 2021, etc.
    if str =~ /\A(JAN|APR|JUL|OCT)-[A-Z]{3,4}\s+(\d{2,4})\z/
      quarter_start_month = {
        "JAN" => 1, "APR" => 4, "JUL" => 7, "OCT" => 10
      }[::Regexp.last_match(1)]
      year = normalize_year(::Regexp.last_match(2))
      return Date.new(year, quarter_start_month, 1)
    end
  
    # JFM 2021, AMJ 21, etc.
    if str =~ /\A(JFM|AMJ|JAS|OND)\s+(\d{2,4})\z/
      quarter_start_month = {
        "JFM" => 1, "AMJ" => 4, "JAS" => 7, "OND" => 10
      }[::Regexp.last_match(1)]
      year = normalize_year(::Regexp.last_match(2))
      return Date.new(year, quarter_start_month, 1)
    end
  
    # === Year Formats ===
    if str =~ /\A(?:CY|FY)?\s*(\d{2,4})\z/
      year = normalize_year(::Regexp.last_match(1))
      type = str.start_with?("FY") ? "FY" : "CY"
      return type == "FY" ? Date.new(year - 1, fiscal_year_start_month, 1) : Date.new(year, 1, 1)
    end
  
    # === Fallback to Date.parse ===
    begin
      return Date.parse(raw_period.to_s)
    rescue ArgumentError
      raise "Unrecognized period format: '#{raw_period}'"
    end
  end
  
  # rubocop:enable Metrics/MethodLength

  
  def self.normalize_year(year)
    year = year.to_i
    year < 100 ? (year >= 50 ? 1900 + year : 2000 + year) : year
  end
  
  def self.start_of_fiscal_quarter(fy, quarter, fiscal_start_month)
    start_month = ((fiscal_start_month - 1) + (quarter - 1) * 3) % 12 + 1
    year = start_month >= fiscal_start_month ? fy - 1 : fy
    Date.new(year, start_month, 1)
  end
    

end
