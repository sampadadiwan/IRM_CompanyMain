# frozen_string_literal: true

# Turns a raw spreadsheet cell into the number the portco meant.
#
# Principle (docs/technical/kpi_portco_upload_validation_review.md §2.4): interpret formatting,
# store the intended number, and never silently store 0. Understands thousands separators
# (Western and Indian grouping), accounting negatives, currency prefixes/suffixes, unit
# suffixes (K/L/M/Cr/B), and percent signs. Placeholders are skipped with a warning; Excel
# error cells and genuinely ambiguous text are errors that the caller surfaces to the user.
#
# Usage:
#   result = KpiValueNormalizer.parse("₹ 12,50,000", data_type: "money", denomination_multiplier: 1)
#   result.ok?      # => true
#   result.value    # => 0.125e7 (BigDecimal)
#   result.applied  # => ["stripped currency", "stripped thousands separators"]
#
# Every rule is documented inline because these decisions are user-visible ("no surprises").
class KpiValueNormalizer
  # status: :ok (value present), :skip (blank/placeholder — nothing to store), :error (must be fixed)
  Result = Struct.new(:status, :value, :applied, :code, :message, :unit_override, :percent_applied, :warnings, keyword_init: true) do
    def ok?
      status == :ok
    end

    def skip?
      status == :skip
    end

    def error?
      status == :error
    end
  end

  # Text that means "no value" — skipped with a warning so the portco knows the cell was ignored.
  # Configurable per call; this is the default list (today's importer only knew n/a and na).
  DEFAULT_PLACEHOLDERS = %w[n/a na n.a. n.a - -- — – nm n.m. n.m tbd nil none pending null ..].freeze

  # Excel error literals — Roo hands these back as strings. Always an error: the source formula is broken.
  EXCEL_ERRORS = %w[#div/0! #ref! #n/a #value! #name? #num! #null! #spill! #calc! #getting_data].freeze

  # Unit suffixes → multiplier. An explicit unit in the cell overrides the mapping's denomination
  # (a "1.2 Cr" cell on a crores-denominated mapping is 1.2 crore, not 1.2 crore crores).
  UNIT_MULTIPLIERS = {
    'k' => 1_000, 'thousand' => 1_000, 'thousands' => 1_000,
    'l' => 100_000, 'lac' => 100_000, 'lacs' => 100_000, 'lakh' => 100_000, 'lakhs' => 100_000,
    'm' => 1_000_000, 'mn' => 1_000_000, 'mm' => 1_000_000, 'mio' => 1_000_000, 'million' => 1_000_000, 'millions' => 1_000_000,
    'cr' => 10_000_000, 'crore' => 10_000_000, 'crores' => 10_000_000,
    'b' => 1_000_000_000, 'bn' => 1_000_000_000, 'billion' => 1_000_000_000, 'billions' => 1_000_000_000
  }.freeze

  # Longest alternatives first so "mn" wins over "m" and "crores" over "cr".
  UNIT_REGEX = /\s*(#{UNIT_MULTIPLIERS.keys.sort_by { |k| -k.length }.map { |k| Regexp.escape(k) }.join('|')})\.?\z/i

  # Currency symbols and ISO/colloquial codes, as prefix or suffix.
  CURRENCY_PREFIX = /\A(?:₹|\$|€|£|¥|rs\.?|inr|usd|eur|gbp|sgd|aed|jpy|cad|aud)\s*/i
  CURRENCY_SUFFIX = /\s*(?:₹|\$|€|£|¥|rs\.?|inr|usd|eur|gbp|sgd|aed|jpy|cad|aud)\z/i

  # Strong locale signatures used by detect_locale. A cell like "1.234,56" can only be
  # European; "1,234.56" or "12,50,000" can only be Western/Indian.
  EUROPEAN_SIGNATURE = /\d\.\d{3},\d/
  WESTERN_SIGNATURE = /\d,\d{3}\.\d|\d,\d{2},\d{3}/

  class << self
    # Detects the decimal/thousands convention for a whole sheet from its value cells.
    # Per-sheet (not per-cell) so "1,234" is never misread inside a consistently-European sheet.
    #
    # @param strings [Enumerable<String>] raw string cells from the sheet's data area
    # @return [Symbol] :western (default), :european, or :mixed (both signatures present → ambiguous)
    def detect_locale(strings)
      european = false
      western = false
      strings.each do |s|
        next unless s.is_a?(String)

        european ||= s.match?(EUROPEAN_SIGNATURE)
        western ||= s.match?(WESTERN_SIGNATURE)
        break if european && western
      end
      return :mixed if european && western
      return :european if european

      :western
    end

    # Parses one cell.
    #
    # @param raw [Object] the cell as returned by Roo (Numeric, String, Date, nil)
    # @param data_type [String, nil] the mapping's data_type ("money"/"numeric"/"percentage")
    # @param denomination_multiplier [Numeric] multiplier from the mapping's denomination (1 if none)
    # @param locale [Symbol] :western / :european / :mixed (see detect_locale)
    # @param placeholders [Array<String>] lowercase strings treated as "no value"
    # @return [Result]
    def parse(raw, data_type: nil, denomination_multiplier: 1, locale: :western, placeholders: DEFAULT_PLACEHOLDERS)
      applied = []
      warnings = []

      # Numeric cells are the common case: Roo gives Float/Integer for real numeric cells.
      # Excel native % cells arrive already as fractions (12% → 0.12), so nothing to do there.
      if raw.is_a?(Numeric)
        value = raw.to_d
        value, applied = apply_denomination(value, denomination_multiplier, applied)
        return Result.new(status: :ok, value: value, applied: applied, unit_override: false, percent_applied: false, warnings: warnings)
      end

      # Dates in a value column are never a KPI value.
      return error(:non_numeric_value, "'#{raw}' is a date, not a number") if raw.is_a?(Date) || raw.is_a?(Time)

      str = raw.to_s.strip
      # Normalise unicode minus, non-breaking spaces and thin spaces so the regexes below see plain ASCII.
      str = str.tr("−   ", "-   ")
      return Result.new(status: :skip, code: :blank, applied: applied, warnings: warnings) if str.empty?

      lower = str.downcase
      return error(:excel_error_cell, "Excel error '#{str}' — the formula in this cell is broken") if EXCEL_ERRORS.include?(lower)
      return Result.new(status: :skip, code: :placeholder, message: "'#{str}' treated as blank", applied: ['placeholder → blank'], warnings: warnings) if placeholders.include?(lower)

      negative = false
      body = str

      # Accounting negatives "(500)" and trailing-minus "500-".
      if (m = body.match(/\A\((.+)\)\z/))
        negative = true
        body = m[1].strip
        applied << 'parentheses → negative'
      elsif (m = body.match(/\A(.+\d)\s*-\z/))
        negative = true
        body = m[1].strip
        applied << 'trailing minus → negative'
      end

      # Leading sign (after currency, e.g. "-₹500" or "₹-500" both occur).
      if (m = body.match(/\A([+-])\s*(.+)\z/))
        negative ^= (m[1] == '-')
        body = m[2].strip
      end
      if body.match?(CURRENCY_PREFIX)
        body = body.sub(CURRENCY_PREFIX, '')
        applied << 'stripped currency'
      end
      if (m = body.match(/\A([+-])\s*(.+)\z/))
        negative ^= (m[1] == '-')
        body = m[2].strip
      end
      if body.match?(CURRENCY_SUFFIX)
        body = body.sub(CURRENCY_SUFFIX, '')
        applied << 'stripped currency'
      end

      # Percent sign.
      percent = false
      if body.match?(/\s*%\z/)
        percent = true
        body = body.sub(/\s*%\z/, '')
      end

      # Unit suffix (K/L/M/Cr/B …). Only when the remainder is numeric-looking, so a KPI value
      # like "12 months" isn't mistaken for 12 million (months isn't a unit, but be defensive).
      unit_multiplier = nil
      if (m = body.match(UNIT_REGEX)) && body.sub(UNIT_REGEX, '').match?(/\d\z/)
        unit_multiplier = UNIT_MULTIPLIERS[m[1].downcase]
        body = body.sub(UNIT_REGEX, '')
        applied << "unit '#{m[1]}' × #{unit_multiplier}"
      end

      body = body.strip
      number = parse_number_body(body, locale, applied)
      return number if number.is_a?(Result) # error bubbled up

      value = number
      value = -value if negative

      if percent
        if data_type.to_s == 'percentage'
          # Consistent with Excel native % cells (0.12) and KpisHelper displaying value*100.
          value /= 100
          applied << 'percent → fraction (÷100)'
        else
          # Percent sign on a KPI the fund does not treat as a percentage: keep the number, flag it.
          applied << 'percent sign ignored'
          warnings << :percent_on_non_percentage
        end
      end

      if unit_multiplier
        # Explicit unit in the cell wins over the mapping denomination — never stacked.
        value *= unit_multiplier
        warnings << :unit_overrides_denomination if denomination_multiplier.to_d != 1
      else
        value, applied = apply_denomination(value, denomination_multiplier, applied)
      end

      Result.new(status: :ok, value: value, applied: applied, unit_override: unit_multiplier.present?, percent_applied: percent, warnings: warnings)
    end

    private

    def error(code, message)
      Result.new(status: :error, code: code, message: message, applied: [], warnings: [])
    end

    def apply_denomination(value, multiplier, applied)
      return [value, applied] if multiplier.nil? || multiplier.to_d == 1

      applied << "denomination × #{multiplier.to_i}"
      [value * multiplier.to_d, applied]
    end

    # Parses the digits/separators part. Returns a BigDecimal, or a Result(:error) when the
    # separators cannot be read unambiguously under the sheet's locale.
    def parse_number_body(body, locale, applied)
      return error(:non_numeric_value, "'#{body}' is not a number") if body.empty? || !body.match?(/\d/)

      # Anything other than digits, separators and whitespace at this point is text. Two number
      # runs separated by text ("10 (prev 8)", "12 / 15") are ambiguous — we cannot know which one
      # was meant; a single run wrapped in text ("ten", "see note 5") is simply not a number.
      unless body.match?(/\A[\d.,'\s]+\z/)
        return error(:ambiguous_value, "'#{body}' contains more than one number") if body.scan(/\d[\d.,']*/).length > 1

        return error(:non_numeric_value, "'#{body}' is not a number")
      end

      # Spaces and apostrophes are only ever thousands separators (Swiss/French styles).
      if body.match?(/[\s']/)
        return error(:ambiguous_value, "'#{body}' has irregular grouping") unless body.match?(/\A\d{1,3}([\s']\d{3})+([.,]\d+)?\z/)

        body = body.gsub(/[\s']/, '')
        applied << 'stripped thousands separators'
      end

      has_comma = body.include?(',')
      has_dot = body.include?('.')

      case locale
      when :mixed
        # The sheet uses both "1.234,56" and "1,234.56" — refuse to guess for any cell with separators.
        return error(:ambiguous_value, "'#{body}' — this sheet mixes European and Western number formats") if has_comma || has_dot

        to_decimal(body)
      when :european
        # "." groups thousands, "," is the decimal point.
        return error(:ambiguous_value, "'#{body}' has irregular grouping for a European-format sheet") if has_dot && !body.match?(/\A\d{1,3}(\.\d{3})+(,\d+)?\z|\A\d+(,\d+)?\z/)

        applied << 'stripped thousands separators' if has_dot
        to_decimal(body.delete('.').tr(',', '.'))
      else
        parse_western(body, has_comma, has_dot, applied)
      end
    end

    # Western/Indian: "," (or Indian 2-2-3 grouping) is thousands, "." is decimal.
    def parse_western(body, has_comma, has_dot, applied)
      # "1.234,56" inside a Western sheet — European-looking, refuse to guess.
      return error(:ambiguous_value, "'#{body}' looks European (1.234,56) but the sheet is Western — please use one format") if has_comma && has_dot && body.rindex(',') > body.rindex('.')

      if has_comma
        int_part, dec_part = body.split('.', 2)
        # Comma must be a grouping separator: Western (groups of 3) or Indian (2-2-3).
        groups = int_part.split(',', -1)
        western_ok = groups[1..].all? { |g| g.length == 3 } && groups[0].length.between?(1, 3)
        indian_ok = groups.length >= 3 && groups.last.length == 3 && groups[1..-2].all? { |g| g.length == 2 } && groups[0].length.between?(1, 2)
        unless western_ok || indian_ok
          # "12,34" / "1,2" — could be a decimal comma; not safe to guess in a Western sheet.
          return error(:ambiguous_value, "'#{body}' — comma could be a decimal or thousands separator")
        end

        applied << 'stripped thousands separators'
        body = dec_part ? "#{int_part.delete(',')}.#{dec_part}" : int_part.delete(',')
      end

      # More than one dot ("1.234.567") is European grouping in a Western sheet — ambiguous.
      return error(:ambiguous_value, "'#{body}' has more than one decimal point") if body.count('.') > 1

      to_decimal(body)
    end

    def to_decimal(str)
      str = "0#{str}" if str.start_with?('.')
      str = str.chomp('.')
      BigDecimal(str)
    rescue ArgumentError
      error(:non_numeric_value, "'#{str}' is not a number")
    end
  end
end
