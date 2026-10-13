# Moves units after a settlement record of a dealing date changes (design card ⑦): allots units for a
# verified subscription on a confirmed dealing date, cancels exact units for a paid redemption.
# Retries are safe — EvergreenAllotment skips fills whose units already moved.
# Worked examples H23, H24, H25 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingSettlementSyncJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(record_type, record_id, user_id = nil)
    EvergreenAllotment.sync(record_type, record_id, user_id)
  end
end
