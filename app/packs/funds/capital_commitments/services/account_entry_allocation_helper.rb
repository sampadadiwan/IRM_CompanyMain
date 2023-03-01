class AccountEntryAllocationHelper
  def initialize(fund, start_date, end_date, user_id: nil)
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
  end

  def cleaup_prev_allocation
    # Remove all prev allocations for this period, as we will recompute it
    AccountEntry.where(fund_id: @fund.id, generated: true, reporting_date: @start_date..).where(reporting_date: ..@end_date).where.not(capital_commitment_id: nil).delete_all
    notify("Cleaned up prev allocated entries", :success, @user_id)
  end

  def generate_soa(template_name)
    @fund.capital_commitments.each do |capital_commitment|
      CapitalCommitmentSoaJob.perform_now(capital_commitment.id, @start_date, @end_date, user_id: @user_id, template_name:)
    end
    notify("Done Genrating SOAs for #{@start_date} - #{@end_date}", :success, @user_id)
  end

  def generate_fund_ratios
    FundRatiosJob.perform_now(@fund.id, nil, @end_date, @user_id, true)
    notify("Done generating fund ratios for #{@start_date} - #{@end_date}", :success, @user_id)
  end

  def notify(message, level, user_id)
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
  end
end
