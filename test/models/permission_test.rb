# == Schema Information
#
# Table name: permissions
#
#  id            :integer          not null, primary key
#  user_id       :integer
#  owner_type    :string(255)      not null
#  owner_id      :integer          not null
#  email         :string(255)
#  permissions   :integer
#  entity_id     :integer          not null
#  granted_by_id :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

require "test_helper"

class PermissionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
