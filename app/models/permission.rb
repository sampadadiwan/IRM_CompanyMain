class Permission < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :owner, polymorphic: true
  belongs_to :entity
  belongs_to :granted_by, class_name: "User"

  flag :permissions, %i[read write]
end
