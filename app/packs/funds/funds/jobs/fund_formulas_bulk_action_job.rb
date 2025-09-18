class FundFormulasBulkActionJob < BulkActionJob
  def perform_action(fund_formula, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on FundFormula #{fund_formula.id} - #{params}")
    msg = "#{bulk_action}: FundFormula #{fund_formula.name}"
    send_notification(msg, user_id, :success)

    case bulk_action.downcase

    when "enable"
      fund_formula.assign_attributes(enabled: true)
      result = fund_formula.save
      unless result
        error = fund_formula.errors.full_messages.join(", ")
        @error_msg << { msg: error, formula: "#{fund_formula.sequence} - #{fund_formula.name}" }
      end
    when "disable"
      fund_formula.assign_attributes(enabled: false)
      result = fund_formula.save
      unless result
        error = fund_formula.errors.full_messages.join(", ")
        @error_msg << { msg: error, formula: "#{fund_formula.sequence} - #{fund_formula.name}" }
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end

  def get_class
    FundFormula
  end
end
