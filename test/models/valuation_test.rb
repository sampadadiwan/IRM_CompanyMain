# == Schema Information
#
# Table name: valuations
#
#  id                        :integer          not null, primary key
#  entity_id                 :integer          not null
#  valuation_date            :date
#  pre_money_valuation_cents :decimal(20, 2)   default("0.00")
#  per_share_value_cents     :decimal(15, 2)   default("0.00")
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  form_type_id              :integer
#

require "test_helper"

class ValuationTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
