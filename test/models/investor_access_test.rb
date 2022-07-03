# == Schema Information
#
# Table name: investor_accesses
#
#  id          :integer          not null, primary key
#  investor_id :integer
#  user_id     :integer
#  email       :string(255)
#  approved    :boolean
#  granted_by  :integer
#  entity_id   :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  deleted_at  :datetime
#  first_name  :string(20)
#  last_name   :string(20)
#

require "test_helper"

class InvestorAccessTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
