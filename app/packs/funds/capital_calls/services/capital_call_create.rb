class CapitalCallCreate < CapitalCallAction
  NO_APPLICABLE_COMMITMENTS_MESSAGE = "No commitments in this fund apply to this call. Add commitments for the selected fund closes before creating a capital call.".freeze

  # Runs first and ends the operation itself: handle_errors re-runs valid?, which would clear this error
  step :check_applicable_commitments, Output(:failure) => End(:failure)
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances

  # A call no commitment applies to would have nobody to collect from (openspec funds/capital-call-creation).
  # Same scope CapitalCallJob#generate walks, except that no closes at all means every commitment: an
  # Upload call from the form arrives with fund_closes [] (all close percentages 0), which applicable_to
  # would read as "none". A missing fund is left to the belongs_to validation in save.
  def check_applicable_commitments(ctx, capital_call:, **)
    return true if capital_call.fund.nil?

    commitments = capital_call.fund_closes.blank? ? capital_call.fund.capital_commitments : capital_call.applicable_to
    return true if commitments.exists?

    capital_call.errors.add(:base, NO_APPLICABLE_COMMITMENTS_MESSAGE)
    ctx[:errors] = capital_call.errors.full_messages.join(", ")
    false
  end
end
