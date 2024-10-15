class NewAllocationJob < ApplicationJob
  queue_as :high

  def perform(secondary_sale_id, user_id, engine_name, priority:, matching_priority:)
    secondary_sale = SecondarySale.find(secondary_sale_id)
    case engine_name
    when "Default Allocation Engine"
      send_notification("Allocation started", user_id)
      SecondarySaleAllocationEngine.new(secondary_sale, priority:, user_id:, matching_priority:).match
      send_notification("Allocation completed", user_id)
    else
      message = "Unknown allocation engine: #{engine_name}"
      send_notification(message, user_id, "error")
      Rails.logger.debug { message }
    end
  end
end
