class InterestCreate < InterestAction
  step :save
  left :handle_errors
  step :notify_interest

  def notify_interest(_ctx, interest:, **)
    interest.notify_interest
  end
end
