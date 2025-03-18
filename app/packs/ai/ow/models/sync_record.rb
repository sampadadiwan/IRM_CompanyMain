class SyncRecord < ApplicationRecord
  belongs_to :syncable, polymorphic: true
end
