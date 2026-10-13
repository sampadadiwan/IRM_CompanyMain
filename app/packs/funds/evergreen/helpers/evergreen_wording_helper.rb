# eg_t(:capital_commitment) in evergreen views and mailers: EvergreenLabels for the page's fund, so the
# fund's unit name and its entity's wording apply. Pass fund: where a partial has no @fund.
module EvergreenWordingHelper
  def eg_t(key, fund: @fund, **)
    EvergreenLabels.t(key, fund:, **)
  end

  # "1,000.0000 units" / "1,000.0000 shares" — a unit count with the fund's unit word
  def eg_units(quantity, fund: @fund, precision: 4, **)
    "#{number_with_precision(quantity, precision:, delimiter: ',', **)} #{eg_t(:units, fund:)}"
  end
end
