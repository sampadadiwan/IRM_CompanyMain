class CapitalRemittancesCountersJob < BulkActionJob
  def perform(entity_id, user_id, _params: {})
    send_notification("Recalculating counters for Capital Remittances ....", user_id, :info) if user_id
    CapitalRemittance.counter_culture_fix_counts where: { entity_id: }
    send_notification("Recalculating counters completed for Capital Remittances", user_id, :success) if user_id
  end
end
