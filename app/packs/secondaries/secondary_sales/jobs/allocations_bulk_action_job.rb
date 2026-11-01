class AllocationsBulkActionJob < BulkActionJob
  # H6 step 3 — bulk_action → the policy query each row is checked with, the same as the single
  # allocation's buttons: verify / unverify are an edit of the allocation, generate docs is generate_docs?
  ACTIONS = { "verify" => :update?, "unverify" => :update?, "generate all docs" => :generate_docs? }.freeze

  def perform_action(allocation, user_id, bulk_action, params: {})
    msg = "#{bulk_action}: #{allocation}"
    Rails.logger.info "Performing #{msg} with #{params}"
    send_notification(msg, user_id, :success)

    # H6 step 3 — per row: an LP or a user without update on the sale changes nothing and gets a
    # "Not authorized" line in the errors email. Tests H6-2, H6-S1, H6-SH —
    # features/security/bulk_actions_authorization.feature
    query = ACTIONS[bulk_action.to_s.downcase]
    if query && !Pundit.policy!(@user, allocation).public_send(query)
      @error_msg << { msg: "Not authorized to #{bulk_action.to_s.downcase}", id: allocation.id, Allocation: allocation }
      return
    end

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

  def record_includes
    %i[offer interest entity secondary_sale form_type documents]
  end
end
