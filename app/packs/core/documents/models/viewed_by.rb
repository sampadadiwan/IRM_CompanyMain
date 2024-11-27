class ViewedBy < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :user, optional: true
  belongs_to :entity
end
