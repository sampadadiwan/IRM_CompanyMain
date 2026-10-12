# Reminds Fund accounting once, 5 business days (Mon–Fri) before an open contract expires.
# Worked example E57 — openspec/changes/fund-market-data/business-rules.md
class DerivativeExpiryJob < ApplicationJob
  queue_as :low
  BUSINESS_DAYS_AHEAD = 5

  def perform(run_date = nil)
    today = run_date.present? ? Date.parse(run_date.to_s) : Time.zone.today
    target = add_business_days(today, BUSINESS_DAYS_AHEAD)
    DerivativeContract.where(status: "open", expiry_reminded_at: nil, expiry_date: today..target).find_each do |contract|
      recipients = User.where(entity_id: contract.entity_id, active: true).with_tag("FundAccounting").to_a
                       .select { |u| FundPolicy.new(u, contract.fund).show? }
      MarketDataOpsNotifier.with(record: contract, entity_id: contract.entity_id, email_method: "derivative_expiring").deliver_later(recipients) if recipients.any?
      contract.update_columns(expiry_reminded_at: Time.current)
    end
  end

  private

  def add_business_days(date, days)
    days.times do
      date = date.next_day
      date = date.next_day while date.saturday? || date.sunday?
    end
    date
  end
end
