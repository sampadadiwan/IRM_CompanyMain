# == Schema Information
#
# Table name: payments
#
#  id               :integer          not null, primary key
#  entity_id        :integer          not null
#  amount           :decimal(10, 2)   default("0.00"), not null
#  plan             :string(30)
#  discount         :decimal(10, 2)   default("0.00")
#  reference_number :string(255)
#  user_id          :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  deleted_at       :datetime
#

class Payment < ApplicationRecord
  include Trackable.new

  belongs_to :entity
  belongs_to :user

  validates :amount, :plan, presence: true
  validates :plan, length: { maximum: 30 }
end
