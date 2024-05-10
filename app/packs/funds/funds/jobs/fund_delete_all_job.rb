class FundDeleteAllJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1
  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, delete_class_name, user_id = nil, really_destroy: false)
    fund = Fund.find(fund_id)
    send_notification("Started deleting #{delete_class_name} for fund #{fund.name}", user_id, :info)

    Chewy.strategy(:sidekiq) do
      # Delete the required associations
      if delete_class_name.present?
        delete(fund, delete_class_name)
        # Fix counter cache
        fix_counter_cache(fund, delete_class_name)
      else
        really_destroy ? fund.really_destroy! : fund.destroy
      end
    rescue StandardError => e
      msg = "Failed deleting #{delete_class_name} for fund #{fund.name} with error #{e.message}"
      ExceptionNotifier.notify_exception(e, data: { message: msg })
      Rails.logger.error(msg)
      send_notification(msg, user_id, :error)
    end

    send_notification("Completed deleting #{delete_class_name} for fund #{fund.name}", user_id, :success)
  end

  def delete(fund, delete_class_name)
    # Delete the funds corr association
    fund.send(delete_class_name.underscore.pluralize).each(&:destroy)
  end

  def fix_counter_cache(fund, delete_class_name)
    case delete_class_name
    when "CapitalCall", "CapitalRemittance", "CapitalRemittancePayment"
      CapitalRemittancePayment.counter_culture_fix_counts where: { entity_id: fund.entity_id }
      CapitalRemittance.counter_culture_fix_counts where: { entity_id: fund.entity_id }
    when "CapitalCommitment"
      CapitalRemittancePayment.counter_culture_fix_counts where: { entity_id: fund.entity_id }
      CapitalRemittance.counter_culture_fix_counts where: { entity_id: fund.entity_id }
      CapitalDistributionPayment.counter_culture_fix_counts where: { entity_id: fund.entity_id }
    # CapitalDistribution.counter_culture_fix_counts where: { entity_id: fund.entity_id }
    when "CapitalDistribution", "CapitalDistributionPayment"
      CapitalDistributionPayment.counter_culture_fix_counts where: { entity_id: fund.entity_id }
      # CapitalDistribution.counter_culture_fix_counts where: { entity_id: fund.entity_id }
    end
  end
end
