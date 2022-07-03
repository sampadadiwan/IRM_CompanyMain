# == Schema Information
#
# Table name: excercises
#
#  id             :integer          not null, primary key
#  entity_id      :integer          not null
#  holding_id     :integer          not null
#  user_id        :integer          not null
#  option_pool_id :integer          not null
#  quantity       :integer          default("0")
#  price_cents    :decimal(20, 2)   default("0.00")
#  amount_cents   :decimal(20, 2)   default("0.00")
#  tax_cents      :decimal(20, 2)   default("0.00")
#  approved       :boolean          default("0")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  tax_rate       :decimal(5, 2)    default("0.00")
#  approved_on    :date
#

require "test_helper"

class ExcerciseTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
