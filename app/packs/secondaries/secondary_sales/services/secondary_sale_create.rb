class SecondarySaleCreate < SecondarySaleAction
  step :save
  left :handle_errors
  step :allocate_sale

  # Run allocation if the sale is finalized and price is changed
  def allocate_sale(_ctx, secondary_sale:, **)
    secondary_sale.allocate_sale if secondary_sale.finalized && secondary_sale.final_price_changed?
    true
  end
end
