class InterestShortList < InterestAction
  step :short_list
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  # step :notify_shortlist

  def short_list(_ctx, interest:, short_listed_status:, **)
    interest.short_listed_status = short_listed_status
    interest.valid?
  end

  # def notify_shortlist(_ctx, interest:, **)
  #   interest.notify_shortlist
  # end
end
