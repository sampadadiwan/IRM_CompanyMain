class LapseHolding < HoldingAction
  step :lapse_holding
  step :update_trust_holdings
  left :handle_error

  def lapse_holding(_ctx, holding:, **)
    check_lapsed(holding)
  end

  def notify_holding_lapse(_ctx, holding:, **)
    holding.notify_lapse
    true
  end

  LAPSE_WARNING_DAYS = [30, 20, 10, 5].freeze
  def check_lapsed(holding)
    # Check if the Options have lapsed
    if holding.lapsed?
      holding.lapse
      holding.reload.notify_lapsed
    elsif LAPSE_WARNING_DAYS.include?(holding.days_to_lapse)
      holding.notify_lapse_upcoming
    end
  end
end
