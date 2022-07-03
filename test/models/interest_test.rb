# == Schema Information
#
# Table name: interests
#
#  id                      :integer          not null, primary key
#  entity_id               :integer
#  quantity                :integer
#  price                   :decimal(10, )
#  user_id                 :integer          not null
#  interest_entity_id      :integer
#  secondary_sale_id       :integer          not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  short_listed            :boolean          default("0")
#  escrow_deposited        :boolean          default("0")
#  final_price             :decimal(10, 2)   default("0.00")
#  amount_cents            :decimal(20, 2)   default("0.00")
#  allocation_quantity     :integer          default("0")
#  allocation_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_percentage   :decimal(5, 2)    default("0.00")
#  finalized               :boolean          default("0")
#  buyer_entity_name       :string(100)
#  address                 :text(65535)
#  contact_name            :string(50)
#  email                   :string(40)
#  PAN                     :string(15)
#  final_agreement         :boolean          default("0")
#  properties              :text(65535)
#  form_type_id            :integer
#  offer_quantity          :integer          default("0")
#  verified                :boolean          default("0")
#  comments                :text(65535)
#  spa_data                :text(65535)
#

require "test_helper"

class InterestTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
