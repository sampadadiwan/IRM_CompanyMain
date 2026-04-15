module CurrencyHelper
  FORMAT = I18n.t :format, scope: 'number.currency.format'

  INDIA_FORMAT = /(\d+?)(?=(\d\d)+(\d)(?!\d))/

  def custom_format_number(number, params = {}, force_units: true)
    cookies ||= nil
    raw_units = params[:force_units].presence || params[:units].presence || (cookies && cookies[:currency_units]) || force_units

    if raw_units.present?
      case raw_units
      when "Crores"
        number_with_delimiter(number, delimiter_pattern: INDIA_FORMAT)
      when "Lakhs"
        number_with_delimiter(number, delimiter_pattern: INDIA_FORMAT)
      when "Million"
        number_with_delimiter(number)
      else
        number_with_delimiter(number)
      end
    else
      number
    end
  end

  def money_to_currency(money, params = {}, ignore_units = false, view_cookies: nil, decimals: nil, negative_in_parentheses: false)
    decimals ||= params[:decimals]&.to_i || 2

    sanf = true
    money = money.clone

    units = ""
    cookies ||= view_cookies
    raw_units = params[:force_units].presence || params[:units].presence || (cookies && cookies[:currency_units])

    if raw_units.present? && !ignore_units
      units = case raw_units.downcase
              when "crores"
                money /= 10_000_000
                sanf = true
                raw_units
              when "lakhs"
                money /= 100_000
                sanf = true
                raw_units
              when "millions", "million" # inconsistent in some places
                money /= 1_000_000
                sanf = false
                "Million"
              end

      cookies[:currency_units] = units if cookies
    end
    if money.is_a?(Money)
      display(money, sanf, units, decimals:, negative_in_parentheses:)
    else
      # Its just a number
      display_numbers_for_ui(money, precision: decimals, negative_in_parentheses:)
    end
  end

  def display_numbers_for_ui(num, precision: 2, delimiter: ",", negative_in_parentheses: false)
    abs_val = number_with_precision(num.abs, precision: precision, delimiter: delimiter)
    if num.negative?
      negative_in_parentheses ? "(#{abs_val})" : "-#{abs_val}"
    else
      abs_val
    end
  end

  def display(money, sanf, units, decimals:, negative_in_parentheses: false)
    display_val = case money.currency.iso_code
                  when "INR"
                    money.format(format: FORMAT, south_asian_number_formatting: sanf, precision: decimals)
                  else
                    money.format(format: FORMAT, precision: decimals)
                  end

    if negative_in_parentheses && money.negative?
      # money.format outputs "-₹1,234.00" or "-$1,234.00" — rewrite to "(₹1,234.00)"
      display_val = "(#{display_val.delete_prefix('-')})"
    end

    units.present? ? "#{display_val} #{units}" : display_val
    # val = val + "(#{money.to_i.rupees.humanize})"
  end

  def currency_from_cents(cents, currency, params)
    money_to_currency Money.new(cents, currency), params
  end

  # Display negative percentage in parentheses if negative_in_parentheses is true, else with a negative sign. If number is nil, display "-"
  def number_to_percentage_for_ui(number, precision: 2, negative_in_parentheses: false)
    return "-" if number.nil?

    abs_val = number_with_precision(number.abs, precision: precision)
    if negative_in_parentheses && number.negative?
      "(#{abs_val})%"
    else
      number_to_percentage(number, precision: precision)
    end
  end
end
