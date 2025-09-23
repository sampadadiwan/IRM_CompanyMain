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

  def money_to_currency(money, params = {}, ignore_units = false, view_cookies: nil, decimals: 2)
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
                raw_units
              end

      cookies[:currency_units] = units if cookies
    end
    if money.is_a?(Money)
      display(money, sanf, units, decimals:)
    else
      # Its just a number
      number_with_delimiter(money.round(decimals))
    end
  end

  def display(money, sanf, units, decimals: 2)
    display_val = case money.currency.iso_code
                  when "INR"
                    money.format(format: FORMAT, south_asian_number_formatting: sanf)
                  else
                    money.format(format: FORMAT)
                  end

    units.present? ? "#{display_val} #{units}" : display_val
    # val = val + "(#{money.to_i.rupees.humanize})"
  end

  def currency_from_cents(cents, currency, params)
    money_to_currency Money.new(cents, currency), params
  end
end
