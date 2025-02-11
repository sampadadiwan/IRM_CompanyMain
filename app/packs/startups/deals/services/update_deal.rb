class UpdateDeal < DealActions
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :broadcast_update
end
