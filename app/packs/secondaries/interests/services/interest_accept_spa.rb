class InterestAcceptSpa < InterestAction
  step :accept_spa
  step :save
  left :handle_errors
  step :notify_accept_spa

  def accept_spa(_ctx, interest:, **)
    interest.final_agreement_user = current_user
    interest.final_agreement = true
  end

  def notify_accept_spa(_ctx, interest:, **)
    interest.notify_accept_spa
  end
end
