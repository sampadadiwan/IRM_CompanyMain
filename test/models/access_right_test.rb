# == Schema Information
#
# Table name: access_rights
#
#  id                    :integer          not null, primary key
#  owner_type            :string(255)      not null
#  owner_id              :integer          not null
#  access_to_email       :string(30)
#  access_to_investor_id :integer
#  access_type           :string(15)
#  metadata              :string(255)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  entity_id             :integer          not null
#  access_to_category    :string(20)
#  deleted_at            :datetime
#  cascade               :boolean          default("0")
#

require "test_helper"

class AccessRightTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
