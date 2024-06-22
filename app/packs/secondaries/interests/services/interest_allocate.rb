class InterestAllocate < InterestAction
  step :allocate
  step :save
  left :handle_errors, Output(:failure) => End(:failure)

  def allocate(_ctx, interest:, interest_params:, **)
    interest.allocation_quantity = interest_params[:allocation_quantity]
    interest.comments = interest_params[:comments]
    interest.verified = interest_params[:verified]
  end
end
