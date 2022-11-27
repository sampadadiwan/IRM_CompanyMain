class HoldingAuditTrail < ApplicationRecord
  update_index('holding_audit_trail') { self }

  enum operation: { create_record: 0, add: 1, subtract: 2, modify: 3, na: 4 }

  belongs_to :ref, polymorphic: true
  belongs_to :entity

  after_initialize :init_dates

  def init_dates
    self.created_at = Time.zone.now
    self.updated_at = Time.zone.now
  end
end
