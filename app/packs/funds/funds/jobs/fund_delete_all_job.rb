class FundDeleteAllJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1
  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, delete_class_name, user_id = nil, really_destroy: false)
    fund = Fund.find(fund_id)
    send_notification("Started deleting #{delete_class_name} for fund #{fund.name}", user_id, :info)

    refused = []
    failed = false
    Chewy.strategy(:sidekiq) do
      # Delete the required associations
      if delete_class_name.present?
        refused = delete(fund, delete_class_name)
        # Fix counter cache
        fix_counter_cache(fund, delete_class_name)
      else
        really_destroy ? fund.really_destroy! : fund.destroy
      end
    rescue StandardError => e
      msg = "Failed deleting #{delete_class_name} for fund #{fund.name} with error #{e.message}"
      ErrorReport.notify(e, job: self, fund_id: fund.id, entity_id: fund.entity_id, message: msg)
      Rails.logger.error(msg)
      send_notification(msg, user_id, :error)
      failed = true
    end
    # The error above already said how it ended - a "Completed" after it would contradict it.
    return if failed

    if refused.any?
      send_notification("Deleted #{delete_class_name} for fund #{fund.name}, except #{refused.size} that could not be deleted: " \
                        "#{refused.uniq.first(3).join('; ')}", user_id, :error)
    else
      send_notification("Completed deleting #{delete_class_name} for fund #{fund.name}", user_id, :success)
    end
  end

  # Destroys every record of the fund's association. A record's before_destroy guard can refuse
  # (e.g. BlocksDestroyWithFundUnits while units are allocated): destroy then returns false rather
  # than raising, so collect why instead of reporting the whole run as done.
  # @return [Array<String>] one error message per record that was not deleted
  def delete(fund, delete_class_name)
    refused = []
    # find_each, not each: these tables can be large and each would load the whole association.
    fund.send(delete_class_name.underscore.pluralize).find_each do |record|
      next if record.destroy

      refused << (record.errors.full_messages.join(", ").presence || "#{delete_class_name} ##{record.id}")
    end
    refused
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
