class AllocationsBulkActionJob < BulkActionJob
  def perform_action(allocation, user_id, bulk_action, params: {})
    msg = "#{bulk_action}: #{allocation}"
    Rails.logger.info "Performing #{msg} with #{params}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      allocation.verified = true
      allocation.save!
    when "unverify"
      allocation.verified = false
      allocation.save!
    when "generate all docs"
      if allocation.verified
        AllocationSpaJob.perform_now(allocation.secondary_sale_id, allocation.id, user_id, template_id: nil)
      else
        msg = "Allocation not verified"
        raise msg
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  rescue StandardError => e
    msg = "Error in #{bulk_action} for #{allocation} #{e.message}"
    send_notification(msg, user_id, "danger")
    @error_msg << { msg:, id: allocation.id, Allocation: allocation }
  end

  def get_class
    Allocation
  end
end
