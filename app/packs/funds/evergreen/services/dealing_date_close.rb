# Closes a dealing date once every applicable step before Close is done.
# Worked example H16 (walkthrough row 16) — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingDateClose < Trailblazer::Operation
  step :check
  step :close

  def check(ctx, dealing_date:, **)
    ok = DealingProgress.new(dealing_date).closable?
    ctx[:errors] = "Finish settling this #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: dealing_date.fund))} before closing it" unless ok
    ok
  end

  def close(_ctx, dealing_date:, current_user:, **)
    dealing_date.update!(status: "closed", closed_by: current_user, closed_at: Time.current)
    dealing_date.journey_progress!(actor: current_user)
    true
  end
end
