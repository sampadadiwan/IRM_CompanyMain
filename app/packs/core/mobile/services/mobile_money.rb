# How the LP mobile app API sends money: major units as a decimal STRING plus the ISO currency,
# e.g. { amount: "7500000.00", currency: "INR" }. Strings, not floats, so ₹5,00,00,000.00 never
# arrives as 49999999.99999999; the app formats it (lakh/crore grouping for INR).
module MobileMoney
  module_function

  def call(money)
    return nil if money.nil?

    { amount: format("%.2f", money.to_d), currency: money.currency.iso_code }
  end

  def cents(amount_cents, currency)
    { amount: format("%.2f", amount_cents.to_d / 100), currency: currency.to_s }
  end
end
