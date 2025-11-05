# frozen_string_literal: true

class Date
  # Parse a date string using the current (or specified) I18n locale.
  #
  # Example:
  #   Date.local_parse("01/02/2025")                  # uses I18n.locale
  #   Date.local_parse("01/02/2025", locale: :"en-US") # uses explicit locale
  #
  def self.local_parse(str, locale: I18n.locale, fmt_key: "date.formats.default")
    if str.is_a?(Date)
      str
    else
      format = I18n.t(fmt_key, locale: locale)
      Date.strptime(str, format)
    end
  rescue StandardError => e
    Rails.logger.debug { "Date.local_parse date: #{str}, format: #{format}, error: #{e.message}" }
    Date.parse(str) # Fallback to default parse if strptime fails
  end

  def self.end_of_period(period, date = Time.zone.today)
    case period.to_s.downcase
    when 'month'
      date.end_of_month
    when 'quarter'
      quarter = ((date.month - 1) / 3) + 1
      Date.new(date.year, quarter * 3, 1).end_of_month
    when 'half year', 'half_year', 'halfyear'
      if date.month <= 6
        Date.new(date.year, 6, 30)
      else
        Date.new(date.year, 12, 31)
      end
    when 'year'
      date.end_of_year
    else
      raise ArgumentError, "Invalid period: #{period.inspect}"
    end
  end

  def self.previous_end_of_period(period, date = Time.zone.today)
    case period.to_s.downcase
    when 'month'
      (date.beginning_of_month - 1.day).end_of_month
    when 'quarter'
      quarter_start_month = (((date.month - 1) / 3) * 3) + 1
      previous_quarter_end_month = quarter_start_month - 1
      year = date.year
      if previous_quarter_end_month < 1
        previous_quarter_end_month += 12
        year -= 1
      end
      Date.new(year, previous_quarter_end_month, 1).end_of_month
    when 'half year', 'half_year', 'halfyear'
      if date.month <= 6
        Date.new(date.year - 1, 12, 31)
      else
        Date.new(date.year, 6, 30)
      end
    when 'year'
      Date.new(date.year - 1, 12, 31)
    else
      raise ArgumentError, "Invalid period: #{period.inspect}"
    end
  end
end
