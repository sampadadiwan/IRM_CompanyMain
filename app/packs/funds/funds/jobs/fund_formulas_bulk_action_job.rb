class FundFormulasBulkActionJob < BulkActionJob
  # H6 step 3 — bulk_action → the policy query the single-formula Enable / Disable authorises with
  ACTIONS = { "enable" => :enable_formulas?, "disable" => :enable_formulas? }.freeze

  def perform_action(fund_formula, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on FundFormula #{fund_formula.id} - #{params}")
    msg = "#{bulk_action}: FundFormula #{fund_formula.name}"
    send_notification(msg, user_id, :success)

    # H6 step 3 — update on the formula's fund, per row: with update on fund A only, a bulk disable over
    # A and B changes A's formulas and reports B's as "Not authorized". Tests H6-3, H6-X1 —
    # features/security/bulk_actions_authorization.feature
    query = ACTIONS[bulk_action.to_s.downcase]
    if query && !Pundit.policy!(@user, fund_formula).public_send(query)
      @error_msg << { msg: "Not authorized to #{bulk_action.to_s.downcase}", formula: "#{fund_formula.sequence} - #{fund_formula.name}" }
      return
    end

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
