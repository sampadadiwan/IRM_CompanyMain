class FundRatiosBulkActionJob < BulkActionJob
  def get_class
    FundRatio
  end

  def record_includes
    [:fund]
  end

  def perform_action(fund_ratio, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on FundRatio #{fund_ratio.id} - #{params}")

    case bulk_action.downcase
    when "delete"
      unless Pundit.policy!(@user, fund_ratio).destroy?
        @error_msg << { msg: "Not authorized to delete", fund_ratio: fund_ratio.to_s }
        return
      end

      msg = "Delete: FundRatio #{fund_ratio}"
      send_notification(msg, user_id, :success)

      # Per-record #destroy (not delete_all/destroy_all) so Trackable's audited/paranoia
      # callbacks fire and the deletion is captured in the audit trail.
      result = fund_ratio.destroy
      unless result
        error = fund_ratio.errors.full_messages.join(", ")
        @error_msg << { msg: error, fund_ratio: fund_ratio.to_s }
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
