class TrackingCurrencyJob < ApplicationJob
  queue_as :low

  def perform(fund_id: nil, user_id: nil)
    Chewy.strategy(:sidekiq) do
      funds = if fund_id.nil?
                # This is run daily, to compute for all funds that have tracking currency
                Fund.where("tracking_currency <> currency")
              else
                # This is run when a specific fund needs to be updated
                Fund.where(id: fund_id)
              end

      funds.each do |fund|
        update_fund(fund, user_id)
      end
    end
  end

  def update_fund(fund, user_id)
    Audited.audit_class.as_user("TrackingCurrencyJob") do
      if fund.tracking_currency.present?
        # Convert account entry
        send_notification("Updating tracking currency for account entries", user_id)
        fund.account_entries.where(tracking_amount_cents: 0).find_each do |ae|
          ae.tracking_amount_cents = ae.amount_cents * ae.tracking_exchange_rate.rate
          ae.save
        end

        # Convert remittance payments
        send_notification("Updating tracking currency for remittance payments", user_id)
        fund.capital_remittance_payments.where(tracking_amount_cents: 0).find_each do |crp|
          crp.tracking_amount_cents = crp.amount_cents * crp.tracking_exchange_rate.rate
          crp.save
        end

        # Convert remittances
        send_notification("Updating tracking currency for remittances", user_id)
        fund.capital_remittances.where(tracking_call_amount_cents: 0).find_each do |cr|
          cr.tracking_call_amount_cents = cr.call_amount_cents * cr.tracking_exchange_rate.rate
          cr.save
        end

        # Convert distributions
        send_notification("Updating tracking currency for distribution payments", user_id)
        fund.capital_distribution_payments.where(tracking_net_payable_cents: 0).find_each do |cdp|
          cdp.tracking_net_payable_cents = cdp.net_payable_cents * cdp.tracking_exchange_rate.rate
          cdp.save
        end

        msg = "Tracking currency updated for fund #{fund.name}"
        send_notification(msg, user_id)
      else
        msg = "#{fund.name} tracking currency not present, skipping conversion to tracking currency"
        send_notification(msg, user_id, :info)
        Rails.logger.debug {}
      end
    end
  end
end
