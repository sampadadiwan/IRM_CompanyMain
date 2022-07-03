# == Schema Information
#
# Table name: permissions
#
#  id            :integer          not null, primary key
#  user_id       :integer
#  owner_type    :string(255)      not null
#  owner_id      :integer          not null
#  email         :string(255)
#  permissions   :integer
#  entity_id     :integer          not null
#  granted_by_id :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

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

  after_create :add_role
  def add_role
    user&.add_role(:consultant)
  end
end
