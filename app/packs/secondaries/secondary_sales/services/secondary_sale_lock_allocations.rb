class SecondarySaleLockAllocations < SecondarySaleAction
  step :lock_allocations
  step :save
  left :handle_errors

  # Run allocation if the sale is finalized and price is changed
  def lock_allocations(ctx, secondary_sale:, **)
    secondary_sale.lock_allocations = !secondary_sale.lock_allocations
    secondary_sale.finalized = !secondary_sale.finalized
    ctx[:label] = secondary_sale.lock_allocations ? "Locked" : "Unlocked"
  end
end
