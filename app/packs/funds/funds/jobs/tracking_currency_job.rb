class TrackingCurrencyJob < ApplicationJob
  queue_as :low

  def perform(fund_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      # Need to compute the tracking currency conversions for the fund
      fund = Fund.find(fund_id)

      Audited.audit_class.as_user("TrackingCurrencyJob") do
        if fund.tracking_currency.present?
          # Convert account entry
          fund.account_entries.where(tracking_amount_cents: 0).find_each do |ae|
            ae.tracking_amount_cents = ae.amount_cents * ae.tracking_exchange_rate.rate
            ae.save
          end

          # Convert remittance payments
          fund.capital_remittance_payments.where(tracking_amount_cents: 0).find_each do |crp|
            crp.tracking_amount_cents = crp.amount_cents * crp.tracking_exchange_rate.rate
            crp.save
          end

          # Convert remittances
          fund.capital_remittances.where(tracking_call_amount_cents: 0).find_each do |cr|
            cr.tracking_call_amount_cents = cr.call_amount_cents * cr.tracking_exchange_rate.rate
            cr.save
          end

          # Convert distributions
          fund.capital_distribution_payments.where(tracking_net_payable_cents: 0).find_each do |cdp|
            cdp.tracking_net_payable_cents = cdp.net_payable_cents * cdp.tracking_exchange_rate.rate
            cdp.save
          end

          UserAlert.new(user_id:, message: "Tracking currency updated for fund #{fund.name}", level: "info").broadcast
        else
          Rails.logger.debug { "#{fund.name} tracking currency not present, skipping conversion to tracking currency" }
        end
      end
    end
  end
end
