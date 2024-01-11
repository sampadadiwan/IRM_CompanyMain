class CapitalRemittancesBulkActionJob < ApplicationJob
  queue_as :low

  def perform(capital_remittance_ids, user_id, bulk_action)
    Chewy.strategy(:sidekiq) do
      capital_remittances = CapitalRemittance.where(id: capital_remittance_ids)
      capital_remittances.each do |doc|
        perform_action(doc, user_id, bulk_action)
      end
    end

    sleep(5)
    msg = "#{bulk_action} completed for #{capital_remittance_ids.count} capital_remittances"
    send_notification(msg, user_id, :success)
  end

  def perform_action(capital_remittance, user_id, bulk_action)
    msg = "#{bulk_action}: #{capital_remittance}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      capital_remittance.verify_remittance
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
