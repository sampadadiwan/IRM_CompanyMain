class InterestShortList < InterestAction
  step :short_list
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :notify_shortlist

  def short_list(_ctx, interest:, **)
    interest.short_listed = !interest.short_listed
    true
  end

  def notify_shortlist(_ctx, interest:, **)
    interest.notify_shortlist
  end
end
