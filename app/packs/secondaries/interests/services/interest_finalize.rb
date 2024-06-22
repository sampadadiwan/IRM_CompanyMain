class InterestFinalize < InterestAction
  step :finalize
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :notify_finalized

  def finalize(_ctx, interest:, **)
    interest.finalized = true
  end

  def notify_finalized(_ctx, interest:, **)
    interest.notify_finalized
  end
end
