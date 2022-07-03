# == Schema Information
#
# Table name: deals
#
#  id                :integer          not null, primary key
#  entity_id         :integer          not null
#  name              :string(255)
#  amount_cents      :decimal(20, 2)   default("0.00")
#  status            :string(20)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  activity_list     :text(65535)
#  start_date        :date
#  end_date          :date
#  deleted_at        :datetime
#  impressions_count :integer          default("0")
#  archived          :boolean          default("0")
#  currency          :string(10)
#  units             :string(15)
#  properties        :text(65535)
#  form_type_id      :integer
#

require "test_helper"

class DealTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
