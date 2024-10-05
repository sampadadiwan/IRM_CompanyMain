class InterestUpdate < InterestAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :validate_bank
  step :validate_pan_card

  def notify_interest(_ctx, interest:, **)
    interest.notify_interest
  end
end
