class InterestShortList < InterestAction
  step :short_list
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :notify_shortlist

  def short_list(ctx, interest:, short_listed_status:, current_user:, **)
    if SecondarySalePolicy.new(current_user, interest.secondary_sale).owner?
      # Only owners can change the short list status
      interest.short_listed_status = short_listed_status
    elsif short_listed_status == Interest::STATUS_WITHDRAWN
      # RMs and investors can only withdraw the interests
      interest.short_listed_status = Interest::STATUS_WITHDRAWN
    else
      interest.errors.add(:short_listed_status, "You are not authorized to #{short_listed_status} this interest")
    end

    interest.status_updated_by = current_user
    interest.status_updated_at = Time.zone.now

    ctx[:validate] = false
    interest.valid?
  end

  def notify_shortlist(_ctx, interest:, **)
    interest.notify_shortlist
  end
end
