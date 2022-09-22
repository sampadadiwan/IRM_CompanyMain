# == Schema Information
#
# Table name: holding_audit_trails
#
#  id         :integer          not null, primary key
#  action     :string(100)
#  parent_id  :string(50)
#  owner      :string(30)
#  quantity   :integer
#  operation  :integer
#  completed  :boolean          default("0")
#  ref_type   :string(255)      not null
#  ref_id     :integer          not null
#  comments   :text(65535)
#  entity_id  :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

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
