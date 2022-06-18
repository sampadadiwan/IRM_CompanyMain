# The InvestmentsHelper has these methods, but uses cookies, which are not avial in mailers
# But mailers render the same view. So mailers use this helper instead
module EmailCurrencyHelper
  FORMAT = I18n.t :format, scope: 'number.currency.format'

  INDIA_FORMAT = /(\d+?)(?=(\d\d)+(\d)(?!\d))/

  def custom_format_number(number, _params = {}, _ignore_units: false)
    number_with_delimiter(number)
  end

  def money_to_currency(money, _params = {}, _ignore_units: false)
    sanf = true
    money = money.clone
    units = ""
    display(money, sanf, units)
  end

  def display(money, sanf, units)
    display_val = case money.currency.iso_code
                  when "SGD", "USD"
                    money.format(format: FORMAT)
                  else
                    money.format(format: FORMAT, south_asian_number_formatting: sanf)
                  end

    units.present? ? "#{display_val} #{units}" : display_val
  end
end
