module CapitalDistributionPaymentsHelper
  # Label for the net amount of completed distribution payments, worded from the viewer's side:
  # an LP has Received it, the fund team has Paid it. Same figure either way (lp_totals[:received]).
  def distribution_paid_label
    current_user&.curr_role == "investor" ? "Received" : "Paid"
  end

  # Tooltip phrase to match distribution_paid_label - "what you have actually received" vs
  # "what the fund has actually paid out"
  def distribution_paid_phrase
    current_user&.curr_role == "investor" ? "what you have actually received" : "what the fund has actually paid out"
  end
end
