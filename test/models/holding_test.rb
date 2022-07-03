# == Schema Information
#
# Table name: holdings
#
#  id                                :integer          not null, primary key
#  user_id                           :integer
#  entity_id                         :integer          not null
#  quantity                          :integer          default("0")
#  value_cents                       :decimal(20, 2)   default("0.00")
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  investment_instrument             :string(100)
#  investor_id                       :integer          not null
#  holding_type                      :string(15)       not null
#  investment_id                     :integer
#  price_cents                       :decimal(20, 2)   default("0.00")
#  funding_round_id                  :integer          not null
#  option_pool_id                    :integer
#  excercised_quantity               :integer          default("0")
#  grant_date                        :date
#  vested_quantity                   :integer          default("0")
#  lapsed                            :boolean          default("0")
#  employee_id                       :string(20)
#  import_upload_id                  :integer
#  fully_vested                      :boolean          default("0")
#  lapsed_quantity                   :integer          default("0")
#  orig_grant_quantity               :integer          default("0")
#  sold_quantity                     :integer          default("0")
#  created_from_excercise_id         :integer
#  cancelled                         :boolean          default("0")
#  approved                          :boolean          default("0")
#  approved_by_user_id               :integer
#  emp_ack                           :boolean          default("0")
#  emp_ack_date                      :date
#  uncancelled_quantity              :integer          default("0")
#  cancelled_quantity                :integer          default("0")
#  gross_avail_to_excercise_quantity :integer          default("0")
#  unexcercised_cancelled_quantity   :integer          default("0")
#  net_avail_to_excercise_quantity   :integer          default("0")
#  gross_unvested_quantity           :integer          default("0")
#  unvested_cancelled_quantity       :integer          default("0")
#  net_unvested_quantity             :integer          default("0")
#  manual_vesting                    :boolean          default("0")
#  properties                        :text(65535)
#  form_type_id                      :integer
#

require "test_helper"

class HoldingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
