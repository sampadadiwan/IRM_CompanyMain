# == Schema Information
#
# Table name: aggregate_investments
#
#  id                      :integer          not null, primary key
#  entity_id               :integer          not null
#  shareholder             :string(255)
#  investor_id             :integer          not null
#  equity                  :integer          default("0")
#  preferred               :integer          default("0")
#  options                 :integer          default("0")
#  percentage              :decimal(5, 2)    default("0.00")
#  full_diluted_percentage :decimal(5, 2)    default("0.00")
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#

require "test_helper"

class AggregateInvestmentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
