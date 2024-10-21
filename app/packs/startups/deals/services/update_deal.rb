class UpdateDeal < DealActions
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
end
