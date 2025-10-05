# config/initializers/money_formatter_patch.rb
class Money
  class Formatter
    private

    # override the decimal formatter to respect :precision
    def format_decimal_part(value)
      return nil if currency.decimal_places == 0 && !Money.default_infinite_precision
      return nil if rules[:no_cents]
      return nil if rules[:no_cents_if_whole] && value.to_i == 0

      precision = rules[:precision] || currency.decimal_places

      # pad or trim decimals
      value = value.ljust(precision, '0')[0, precision]

      value.gsub!(/0*$/, '') if rules[:drop_trailing_zeros]
      value.empty? ? nil : value
    end
  end
end
