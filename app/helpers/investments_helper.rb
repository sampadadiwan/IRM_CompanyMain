module InvestmentsHelper
  FORMAT = I18n.t :format, scope: 'number.currency.format'

  INDIA_FORMAT = /(\d+?)(?=(\d\d)+(\d)(?!\d))/

  def custom_format_number(number, params = {}, ignore_units = false)
    raw_units = params[:units].presence || (cookies && cookies[:currency_units])

    if raw_units.present? && !ignore_units

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

  def money_to_currency(money, params = {}, ignore_units = false)
    sanf = true
    money = money.clone

    units = ""
    raw_units = params[:units].presence || (cookies && cookies[:currency_units])

    if raw_units.present? && !ignore_units

      units = case raw_units
              when "Crores"
                money /= 10_000_000
                sanf = true
                raw_units
              when "Lakhs"
                money /= 100_000
                sanf = true
                raw_units
              when "Million"
                money /= 1_000_000
                sanf = false
                raw_units
              end

      cookies[:currency_units] = units
    end

    display(money, sanf, units)
  end

  def display(money, sanf, units)
    display_val = case money.currency.iso_code
                  when "INR"
                    money.format(format: FORMAT, south_asian_number_formatting: sanf)
                  when "SGD"
                    money.format(format: FORMAT)
                  when "USD"
                    money.format(format: FORMAT)
                  else
                    money.format(format: FORMAT, south_asian_number_formatting: sanf)
                  end

    units.present? ? "#{display_val} #{units}" : display_val
  end
end
