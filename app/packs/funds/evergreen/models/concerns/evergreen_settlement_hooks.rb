# Included in CapitalRemittance and CapitalDistributionPayment: after a commit on a record that an
# evergreen dealing date points at, queue the unit sync. Entities without evergreen funds stop at the
# permissions flag (no query); on evergreen entities the guard is an indexed EXISTS.
# Backward compatibility B5 — openspec/changes/open-ended-funds/design.md#backward-compatibility
module EvergreenSettlementHooks
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_evergreen_sync, on: %i[create update], if: :evergreen_settlement_record?
  end

  def evergreen_settlement_record?
    return false unless entity&.permissions&.enable_evergreen_funds?

    if is_a?(CapitalRemittance)
      DealingFill.exists?(capital_remittance_id: id) || DealingOrder.exists?(capital_remittance_id: id)
    else
      DealingFill.exists?(capital_distribution_payment_id: id)
    end
  end

  def enqueue_evergreen_sync
    DealingSettlementSyncJob.perform_later(self.class.name, id)
  end
end
