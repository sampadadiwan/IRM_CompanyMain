class KpiDateUtils
  # 1-based fiscal-year-start month for a KPI report's period labels. Same precedence used by
  # KpiWorkbookReader and KpiTemplateGenerate: the portco's own json_fields override wins, then
  # the fund's EntitySetting, then the geo default (EntitySetting.geo_default_month_offset_for_fy).
  def self.resolve_fiscal_year_start_month(portco, entity_id)
    offset = portco.try(:json_fields)&.dig("month_offset_for_fy").presence
    offset ||= EntitySetting.find_by(entity_id:)&.month_offset_for_fy.presence
    (offset.presence || EntitySetting.geo_default_month_offset_for_fy).to_i + 1
  end

  # Determines if a raw_period looks like a date or period label
  def self.date_like?(string)
    return false if string.blank?

    normalized = string.strip.squeeze(" ").upcase

    patterns = [
      # Half-year formats like H1 2023, H2FY23, H1 FY2023
      /\bH[12](?:\s?FY)?\s?\d{2,4}\b/i,

      # Quarters like Q1 FY21 or Q3CY22
      /\bQ[1-4][-' ]?(?:FY|CY)?\d{2,4}\b/i,

      # Fiscal year ranges like FY2020-21 or FY 20-21
      /\bFY\s?\d{2,4}[-–]\d{2,4}\b/i,

      # CY/FY + year, with optional space (e.g. CY2024, CY 2025, FY 2023)
      /\b(?:FY|CY)\s?\d{2,4}\b/i,

      # Month + year (short and full). [\s']* instead of \s* so that
      # apostrophe-delimited formats like "Apr'25" or "May'25" match
      # directly rather than falling through to the lenient Date.local_parse fallback.
      /(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|
    Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|
    Nov(?:ember)?|Dec(?:ember)?)[\s']*\d{2,4}/ix,

      # Quarter shorthands like JFM 2021, AMJ 2022
      /(?:JFM|AMJ|JAS|OND)\s*\d{2,4}/i,

      # Month ranges like Jan-Mar 2021, Apr-Jun 2022
      /(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)
         -(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\s*\d{4}/ix,

      # Date format like 01-11-2023 or 03/11/2022
      %r{\b\d{2}[-/]\d{2}[-/]\d{2,4}\b},

      # Plain year (e.g., 2023)
      /\b\d{4}\b/
    ]

    return true if patterns.any? { |pat| normalized =~ pat }

    # Fallback to Date.local_parse; rescue only date-parsing errors, not programming mistakes.
    begin
      Date.local_parse(normalized)
      true
    rescue ArgumentError
      false
    end
  end

  # Parses a raw period string into a Date object
  def self.parse_period(raw_period, fiscal_year_start_month: 4, raise_error: true)
    return nil if raw_period.blank? || !date_like?(raw_period)

    # G25: "Q1 FY27 (Apr-Jun'26)" is the quarter, not the April the lenient fallback finds in the note
    raw_period = strip_period_note(raw_period)
    str = normalize_input(raw_period)

    parse_month(str) ||
      parse_quarter(str, fiscal_year_start_month) ||
      parse_year(str, fiscal_year_start_month) ||
      parse_ytd(str) ||
      parse_half_year(str, fiscal_year_start_month) ||
      fallback_parse(raw_period, raise_error)
  end

  # G25 (client onboarding): a period heading with a note on a second line or in trailing brackets —
  # Ayati's "Q1 FY27\n(Apr-Jun'26)". The note is dropped when what is left is still a period on its own;
  # anything else ("Actual (Apr 2026)", a bare "(Apr-Jun'26)") is returned unchanged.
  def self.strip_period_note(raw_period)
    return raw_period unless raw_period.is_a?(String)

    # First line only, then any bracketed note at its end
    head = raw_period.split(/\r?\n/).first.to_s.sub(/\s*\([^()]*\)\s*\z/, '').strip
    head.present? && head != raw_period.strip && date_like?(head) ? head : raw_period
  end

  # G25: a heading that starts with a quarter, half-year, YTD or fiscal-year token ("Q1 …", "H2 …", "Q5 …",
  # "YTD …", "FY …"). If detect_period_type still calls such a heading a Month, no rule read it — the
  # Month is only detect_period_type's fallback, and storing a quarter's total as one month is wrong.
  def self.names_longer_period?(raw_period)
    head = strip_period_note(raw_period.to_s).strip
    return true if head.match?(/\A(?:Q\d|H\d|YTD|FY)/i)

    # G35: a month range covering more than one month ("Apr - May'25")
    range = month_range(head.upcase.gsub(/[\s']/, ''))
    range.present? && range[:months] != 1
  end

  def self.normalize_input(raw_period)
    str = raw_period.to_s.strip.upcase
    # Replace apostrophes with spaces so "Apr'25" becomes "APR 25",
    # which then matches parse_month's \A(JAN|...)\s+(\d{2,4})\z regex.
    # Without this, "APR'25" falls through all named parsers into the
    # lenient Date.local_parse fallback.
    str = str.tr("'", ' ')
             .gsub(/\s+/, ' ')
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

    # Removed dead block: \d{2} is already covered by \d{2,4} above.

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

    # === Case 4: month ranges — Jan-Mar 2021, Apr-Sep 2025, Apr-Mar 25. The trailing year is the END
    # month's year (what KpiTemplateGenerate#period_label writes), so a wrapping range like "Dec-Feb 2026"
    # ends 28-Feb-2026. G35: the end month decides the date — it used to be start + 2 whatever the range
    # said, so "Apr - Mar'25" (a full year) came out as 30-Jun-2025. Spans other than 1/3/6/12 months
    # are not a period we store (nil).
    if (range = month_range(str))
      return range[:end_date] if RANGE_PERIOD_TYPES.key?(range[:months])

      return nil
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

  # G35: the period type a month range stands for, by the number of months it covers
  RANGE_PERIOD_TYPES = { 1 => "Month", 3 => "Quarter", 6 => "Half Year", 12 => "Year" }.freeze
  MONTH_ABBR = "JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEPT?|OCT|NOV|DEC".freeze
  MONTH_RANGE_REGEX = /\A(#{MONTH_ABBR})[-–](#{MONTH_ABBR})(\d{2,4})\z/

  # G35: "APR-MAR25" (spaces and apostrophes already removed) → { months: 12, end_date: 31-Mar-2025 }.
  # nil when the string is not a month range.
  def self.month_range(str)
    match = str.to_s.match(MONTH_RANGE_REGEX)
    return nil unless match

    start_month = month_abbr_to_month(match[1][0, 3])
    end_month = month_abbr_to_month(match[2][0, 3])
    { months: ((end_month - start_month) % 12) + 1, end_date: Date.new(normalize_year(match[3]), end_month, -1) }
  end

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
    # fiscal_year is the year in which the fiscal year ends (e.g. FY21 → 2021).
    # For cross-calendar fiscal years (e.g. April-start), quarters 1–3 fall in fiscal_year-1,
    # and only quarter 4 falls in fiscal_year. We derive the base year from the quarter's
    # start month: if the start month is before the fiscal year start month the quarter wraps
    # into fiscal_year, otherwise it sits in fiscal_year-1.
    start_month = ((((quarter - 1) * 3) + fiscal_year_start_month - 1) % 12) + 1
    # A start month earlier in the calendar than the fiscal year's opening month means the
    # quarter crosses the fiscal year boundary into fiscal_year; otherwise it's in fiscal_year-1.
    # A January start means the fiscal year IS the calendar year, so every quarter sits in fiscal_year.
    year = start_month < fiscal_year_start_month || fiscal_year_start_month == 1 ? fiscal_year : fiscal_year - 1

    # Move 2 months forward to get the end month of the quarter
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

  # FY labels are named by the calendar year in which the fiscal year ENDS (FY26 = the year
  # ending in 2026). Which month it ends in depends on the entity's fiscal-year start
  # (`month_offset_for_fy` on EntitySetting / json_fields → passed here as a 1-based month).
  # April start → FY26 ends 31-Mar-2026; January start → FY26 ends 31-Dec-2026.
  def self.parse_year(str, fiscal_year_start_month = 4)
    return nil if str.blank?

    str = str.to_s.strip.upcase.gsub(/\s+/, '')

    if (match = str.match(/\AFY(\d{2,4})(?:-?(\d{2}))?\z/))
      start_year = normalize_year(match[1])
      end_year = match[2] ? normalize_year(match[2]) : start_year
      # Use end_year for fiscal year end date
      fiscal_year_end(end_year, fiscal_year_start_month)
    elsif (match = str.match(/\A(?:CY)?(\d{2,4})\z/))
      year = normalize_year(match[1])
      Date.new(year, 12, 31)
    end
  end

  # Last day of the fiscal year that ends in `end_year` for the given 1-based start month.
  # A January start means the fiscal year is the calendar year (ends 31-Dec of end_year).
  def self.fiscal_year_end(end_year, fiscal_year_start_month)
    fiscal_year_start_month = 4 if fiscal_year_start_month.blank?
    return Date.new(end_year, 12, 31) if fiscal_year_start_month.to_i == 1

    Date.new(end_year, fiscal_year_start_month.to_i - 1, -1)
  end

  def self.parse_half_year(str, fiscal_year_start_month = 4)
    # Normalize to remove spaces and upcase
    str = str.to_s.strip.upcase.gsub(/\s+/, '')

    # Match: H1FY2023 or H2FY23 (Fiscal Half Year). H1 ends 6 months after the fiscal year
    # start, H2 at the fiscal year end — both derived from the entity's fiscal-year start month
    # (April start: H1 = Apr–Sep, H2 = Oct–Mar; January start: H1 = Jan–Jun, H2 = Jul–Dec).
    if (match = str.match(/\AH([12])FY(\d{2,4})\z/))
      half = match[1].to_i
      fy_end = fiscal_year_end(normalize_year(match[2]), fiscal_year_start_month)
      return half == 1 ? (fy_end - 6.months).end_of_month : fy_end
    end

    # Match: H1 2023 or H2 2023 (Calendar Half Year)
    if (match = str.match(/\AH([12])(\d{2,4})\z/))
      half = match[1].to_i
      year = normalize_year(match[2])

      if half == 1
        return Date.new(year, 6, 30)  # Jan–Jun
      else
        return Date.new(year, 12, 31) # Jul–Dec
      end
    end

    nil
  end

  def self.parse_ytd(str)
    # Match: YTD Nov 23, YTD-Jan 2022, etc.
    if (match = str.match(/\AYTD[- ]?([A-Z]{3,9})[- ]?(\d{2,4})\z/i))
      month_name = match[1]
      year = normalize_year(match[2])
      month = Date::ABBR_MONTHNAMES.index(month_name.capitalize) || Date::MONTHNAMES.index(month_name.capitalize)
      return Date.new(year, month, -1) if year && month
    end

    # Match: YTD Jan–Sept 2023 (range)
    if (match = str.match(/\AYTD[- ]?[A-Z]{3,9}[- ]?([A-Z]{3,9})[- ]?(\d{2,4})\z/i))
      end_month_abbr = match[1]
      year = normalize_year(match[2])
      month = Date::ABBR_MONTHNAMES.index(end_month_abbr.capitalize) || Date::MONTHNAMES.index(end_month_abbr.capitalize)
      return Date.new(year, month, -1) if year && month
    end

    nil
  end

  def self.fallback_parse(raw_period, raise_error)
    normalized = raw_period.to_s.strip.gsub(/\s+/, ' ')

    begin
      date =
        if /\A[A-Za-z]{3,9}\s+\d{2}\z/.match?(normalized)
          Date.strptime(normalized, "%b %y")
        else
          Date.local_parse(normalized)
        end

      # Always return the end of the month
      date.end_of_month
    rescue ArgumentError
      if Rails.env.test? || !raise_error
        nil
      else
        # Avoid echoing raw user input into the message to keep logs clean.
        raise "Unrecognized period format"
      end
    end
  end

  # Parses a raw period string and returns Month, Quarter, or Year
  def self.detect_period_type(raw_period)
    return nil if raw_period.blank?

    # G25: judge the period, not its note — the same reading parse_period uses
    raw_period = strip_period_note(raw_period)

    # === Normalize input ===
    # Strip ALL whitespace rather than just collapsing/trimming it around symbols, so arbitrary
    # spacing anywhere in the header — "Q1 FY 24", "Q1  FY24", "FY 20 - 21", "H1 FY 2023" — is
    # treated identically to its tightest form ("Q1FY24", "FY20-21", "H1FY2023"). This mirrors
    # parse_quarter's own normalization (below), so type-detection and date-parsing never disagree
    # about what a header means — the bug this fixed: "Q1 FY 25" parsed to a correct quarter-end
    # date but detect_period_type didn't recognise it as a Quarter (no regex allowed a space
    # between "FY" and the year) and silently fell back to "Month".
    str = raw_period.to_s.strip.upcase.gsub(/\s+/, '')

    Rails.logger.debug { "Normalized string: #{str}" }

    # === Half-Year Formats ===
    return "Half Year" if /\AH[12](?:FY)?\d{2,4}\z/.match?(str) # H1 2023, H2FY23, H1 FY2023

    # === YTD Formats ===
    return "YTD" if /\AYTD-?[A-Z]{3,9}-?\d{2,4}\z/.match?(str) # e.g. YTD Nov 23, YTD-Jan 2022
    return "YTD" if /\AYTD-?[A-Z]{3,9}-?[A-Z]{3,9}-?\d{2,4}\z/.match?(str) # e.g. YTD Jan-Sept 2023

    # === Year Formats ===
    return "Year" if /\AFY\d{2,4}[-–]\d{2}\z/.match?(str)         # FY 20-21 or FY20-21
    return "Year" if /\AFY\d{2,4}\z/.match?(str)                  # FY 2021 or FY2021
    return "Year" if /\A(CY)?\d{2,4}\z/.match?(str) # CY2021 or 2021

    # === Month Formats ===
    return "Month" if /\A(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)(\d{2,4})\z/.match?(str) # e.g. JAN 2024
    return "Month" if /\A(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)(\d{2,4})\z/.match?(str) # e.g. JANUARY 2024

    # === Quarter Formats ===
    return "Quarter" if /\AQ([1-4])(FY|CY)?(\d{2,4})\z/.match?(str) # e.g. Q1FY24, Q1 FY24, Q1 FY 24, Q1 2024

    # A month range is the period it spans (G35): "JAN-MAR 2024" / "MAR-MAY 2026" a Quarter, "APR-SEP 25"
    # a Half Year, "Apr - Mar'25" a Year. Quarters not aligned to Jan/Apr/Jul/Oct round-trip too. Any
    # other span falls through to the Month fallback, which names_longer_period? then refuses.
    range = month_range(str.delete("'"))
    return RANGE_PERIOD_TYPES[range[:months]] if range && RANGE_PERIOD_TYPES.key?(range[:months])

    return "Quarter" if /\A(JFM|AMJ|JAS|OND)(\d{2,4})\z/.match?(str) # e.g. JFM 2024

    # === Fallback ===
    "Month"
  end
  # rubocop:enable Metrics/CyclomaticComplexity

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
