# == Schema Information
#
# Table name: secondary_sales
#
#  id                               :integer          not null, primary key
#  name                             :string(255)
#  entity_id                        :integer          not null
#  start_date                       :date
#  end_date                         :date
#  percent_allowed                  :integer          default("0")
#  min_price                        :decimal(20, 2)
#  max_price                        :decimal(20, 2)
#  active                           :boolean          default("1")
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  total_offered_quantity           :integer          default("0")
#  visible_externally               :boolean          default("0")
#  deleted_at                       :datetime
#  final_price                      :decimal(10, 2)   default("0.00")
#  total_offered_amount_cents       :decimal(20, 2)   default("0.00")
#  total_interest_amount_cents      :decimal(20, 2)   default("0.00")
#  total_interest_quantity          :integer          default("0")
#  offer_allocation_quantity        :integer          default("0")
#  interest_allocation_quantity     :integer          default("0")
#  allocation_percentage            :decimal(7, 4)    default("0.0000")
#  allocation_offer_amount_cents    :decimal(20, 2)   default("0.00")
#  allocation_interest_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_status                :string(10)
#  price_type                       :string(15)
#  finalized                        :boolean          default("0")
#  seller_doc_list                  :text(65535)
#  seller_transaction_fees_pct      :decimal(5, 2)
#  properties                       :text(65535)
#  form_type_id                     :integer
#  lock_allocations                 :boolean          default("0")
#

require "test_helper"

class SecondarySaleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
