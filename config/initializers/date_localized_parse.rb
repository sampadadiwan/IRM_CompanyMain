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
end
