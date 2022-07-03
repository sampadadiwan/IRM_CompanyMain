# == Schema Information
#
# Table name: offers
#
#  id                      :integer          not null, primary key
#  user_id                 :integer          not null
#  entity_id               :integer          not null
#  secondary_sale_id       :integer          not null
#  quantity                :integer          default("0")
#  percentage              :decimal(10, )    default("0")
#  notes                   :text(65535)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  holding_id              :integer          not null
#  approved                :boolean          default("0")
#  granted_by_user_id      :integer
#  investor_id             :integer          not null
#  offer_type              :string(15)
#  first_name              :string(255)
#  middle_name             :string(255)
#  last_name               :string(255)
#  PAN                     :string(15)
#  address                 :text(65535)
#  bank_account_number     :string(40)
#  bank_name               :string(50)
#  bank_routing_info       :text(65535)
#  buyer_confirmation      :string(10)
#  buyer_notes             :text(65535)
#  buyer_id                :integer
#  final_price             :decimal(10, 2)   default("0.00")
#  amount_cents            :decimal(20, 2)   default("0.00")
#  allocation_quantity     :integer          default("0")
#  allocation_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_percentage   :decimal(5, 2)    default("0.00")
#  acquirer_name           :string(255)
#  verified                :boolean          default("0")
#  comments                :text(65535)
#  final_agreement         :boolean          default("0")
#  interest_id             :integer
#  properties              :text(65535)
#  form_type_id            :integer
#  signature_data          :text(65535)
#  spa_data                :text(65535)
#  id_proof_data           :text(65535)
#  address_proof_data      :text(65535)
#

require "test_helper"

class OfferTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
