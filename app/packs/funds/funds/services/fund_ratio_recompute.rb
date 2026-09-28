# Re-queues FundRatiosJob for every end date the fund already has ratios for, fund level and per
# folio, after something has rewritten the numbers those ratios were computed from (a change of
# fund currency or of tracking currency).
#
# Stale ratios need no separate delete: FundRatiosJob#_delete_previous_fund_ratios removes every
# ratio for (fund, capital_commitment, end_date) before writing the new set. That includes ratios
# whose names carry the old tracking currency ("XIRR (EUR)"), and investor-KYC-level ratios, which
# are stored against the commitment they were computed through.
#
#   FundRatioRecompute.call(fund, user_id) # => number of end dates queued
class FundRatioRecompute
  # @param fund [Fund]
  # @param user_id [Integer, nil] who is notified as each job finishes
  # @return [Integer] how many end dates were queued
  def self.call(fund, user_id)
    end_dates = fund.fund_ratios.distinct.pluck(:end_date).compact
    end_dates.each do |end_date|
      FundRatiosJob.perform_later(fund.id, nil, end_date, user_id, true)
    end
    end_dates.size
  end
end
