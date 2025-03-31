class SyncRecord < ApplicationRecord
  belongs_to :syncable, polymorphic: true

  scope :for_type, ->(klass) { where(syncable_type: klass.to_s) }
  scope :synced_ids_for, ->(klass) { for_type(klass).pluck(:syncable_id) }
end
