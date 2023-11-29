class FundDeleteAllJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1
  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, delete_class_name, user_id = nil)
    fund = Fund.find(fund_id)
    send_notification("Started deleting #{delete_class_name} for fund #{fund.name}", user_id, :info)

    Chewy.strategy(:sidekiq) do
      delete(fund, delete_class_name)
    rescue StandardError => e
      Rails.logger.error(e.backtrace.join("\n"))
      msg = "Failed deleting #{delete_class_name} for fund #{fund.name} with error #{e.message}"
      Rails.logger.error(msg)
      send_notification(msg, user_id, :error)
    end

    send_notification("Completed deleting #{delete_class_name} for fund #{fund.name}", user_id, :success)
  end

  def delete
    case delete_class_name
    when "CapitalCall"
      fund.capital_calls.each(&:destroy)
    when "CapitalCommitment"
      fund.capital_commitments.each(&:destroy)
    when "CapitalRemittance"
      fund.capital_remittances.each(&:destroy)
    when "CapitalRemittancePayment"
      fund.capital_remittance_payments.each(&:destroy)
    when "CapitalDistribution"
      fund.capital_distributions.each(&:destroy)
    when "CapitalDistributionPayment"
      fund.capital_distribution_payments.each(&:destroy)
    else
      raise "Cannot delete #{delete_class_name} for #{fund.name}"
    end
  end
end
