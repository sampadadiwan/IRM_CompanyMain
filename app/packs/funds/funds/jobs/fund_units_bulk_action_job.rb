class FundUnitsBulkActionJob < BulkActionJob
  def get_class
    FundUnit
  end

  def record_includes
    [:owner]
  end

  def perform_action(fund_unit, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on FundUnit #{fund_unit.id} - #{params}")

    case bulk_action.downcase

    when "delete"
      # A fund unit's real "owner" for destroy purposes is the remittance/distribution payment
      # that generated it (if any) — only allow the delete if the user could destroy that owner.
      unless Pundit.policy!(@user, fund_unit.owner || fund_unit).destroy?
        @error_msg << { msg: "Not authorized to delete (owner: #{fund_unit.owner_type} ##{fund_unit.owner_id})", fund_unit: fund_unit.to_s }
        return
      end

      msg = "Delete: FundUnit #{fund_unit}"
      send_notification(msg, user_id, :success)

      result = fund_unit.destroy
      unless result
        error = fund_unit.errors.full_messages.join(", ")
        @error_msg << { msg: error, fund_unit: fund_unit.to_s }
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
