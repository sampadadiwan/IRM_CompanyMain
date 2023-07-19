class Notification < ApplicationRecord
  include Noticed::Model
  belongs_to :recipient, polymorphic: true, touch: true
  belongs_to :entity
end
