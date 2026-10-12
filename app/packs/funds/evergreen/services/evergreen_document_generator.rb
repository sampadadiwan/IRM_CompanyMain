# The figures on a contract note / redemption advice: used as the `evergreen.*` fields of the fund's
# Word templates (EvergreenDocTemplateGenerator), by the investor's Transactions tab and by tests.
# (The built-in HexaPDF layout is retired: without a template the investor gets the email only.)
# Worked examples H25, E32, E51 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenDocumentGenerator
  TITLES = { contract_note: "Contract Note", redemption_advice: "Redemption Advice" }.freeze

  def initialize(fill, kind)
    @fill = fill
    @kind = kind
    @order = fill.dealing_order
    @folio = @order.capital_commitment
    @fund = fill.fund
  end

  # The rows printed on the document, [label, value], in the fund's wording ("Folio" / "Account",
  # "NAV per unit" / "NAV per share") — also used by tests and the investor's Transactions tab
  def rows
    entries.map { |_field, label, value| [label, value] }
  end

  # The same values under fixed template field names ({{evergreen.units_allotted}}, {{evergreen.folio}}),
  # so a fund's Word template keeps working whatever its labels say
  def fields
    values = entries.to_h { |field, _label, value| [field.to_s, value] }
    # Templates made before the fixed keys used the parameterised label "Early-redemption fee",
    # i.e. {{evergreen.early-redemption_fee}} — keep that name working too
    values["early-redemption_fee"] = values["early_redemption_fee"] if values.key?("early_redemption_fee")
    values
  end

  private

  # [template field, printed label, value] for each row
  def entries
    money = ->(cents) { Money.new(cents.to_d, @fund.currency).format(south_asian_number_formatting: @fund.currency == "INR") }
    date = ->(d) { I18n.l(d, format: :email, locale: :en) }
    units = ->(u) { ActiveSupport::NumberHelper.number_to_rounded(u, precision: 4, delimiter: ",") }
    label = ->(key) { EvergreenLabels.t(key, fund: @fund) }
    # The date this fill was dealt on, named for its kind ("Subscription date" / "Redemption date")
    deal_date = label.call(@kind == :contract_note ? :subscription_date : :redemption_date)
    base = [[:fund, "Fund", @fund.name], [:folio, label.call(:capital_commitment), @folio.folio_id],
            [:investor, "Investor", @order.investor.investor_name], [:class, "Class", @fill.unit_type],
            [:nav_date, "NAV date", date.call(@fill.fund_nav.nav_date)], [:dealing_date, deal_date, date.call(@fill.dealing_date.date)],
            [:nav_per_unit, label.call(:nav_per_unit), money.call(@fill.nav_per_unit_cents)]]
    if @kind == :contract_note
      rows = base + [[:units_allotted, "#{label.call(:Units)} allotted", units.call(@fill.units)], [:amount, "Amount", money.call(@fill.amount_cents)]]
      # Accepted at the amount received (§ Accept received amount)
      rows << [:subscription_reduced_from, "Subscription reduced from", money.call(@order.original_amount_cents)] if @order.amount_reduced?
      rows
    else
      payment = @fill.capital_distribution_payment
      base + [[:units_cancelled, "#{label.call(:Units)} cancelled", units.call(@fill.units)], [:gross_amount, "Gross amount", money.call(@fill.amount_cents)],
              [:early_redemption_fee, label.call(:early_fee), money.call(@fill.early_fee_cents)],
              [:net_paid, "Net paid", money.call(@fill.net_payment_cents)], [:payment_date, "Payment date", date.call(payment.payment_date)]]
    end
  end
end
