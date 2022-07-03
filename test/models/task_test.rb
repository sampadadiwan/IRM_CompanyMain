# == Schema Information
#
# Table name: tasks
#
#  id            :integer          not null, primary key
#  details       :text(65535)
#  entity_id     :integer          not null
#  for_entity_id :integer
#  completed     :boolean          default("0")
#  user_id       :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  owner_type    :string(255)
#  owner_id      :integer
#  form_type_id  :integer
#

require "test_helper"

class TaskTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
