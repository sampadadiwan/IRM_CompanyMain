class InterestShortList < InterestAction
  step :short_list
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  # step :notify_shortlist

  def short_list(ctx, interest:, short_listed_status:, current_user:, **)
    # Only owners can short_list
    if SecondarySalePolicy.new(current_user, interest.secondary_sale).owner?
      interest.short_listed_status = short_listed_status
    elsif short_listed_status == Interest::STATUS_WITHDRAWN
      interest.short_listed_status = short_listed_status
    else
      interest.errors.add(:short_listed_status, "You are not authorized to #{short_listed_status} this interest")
    end
    ctx[:validate] = false
    interest.valid?
  end

  # def notify_shortlist(_ctx, interest:, **)
  #   interest.notify_shortlist
  # end
end
