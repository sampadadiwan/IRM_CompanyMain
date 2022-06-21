class Permission < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :owner, polymorphic: true
  belongs_to :entity
  belongs_to :granted_by, class_name: "User"

  flag :permissions, %i[read write]

  def self.list(klass, user)
    klass.joins(:permissions).where(permissions: { user_id: user.id })
  end

  def self.allow(owner, user)
    Permission.where(user_id: user.id, owner_id: owner.id, owner_type: owner.class.name).first&.permissions
  end
end
