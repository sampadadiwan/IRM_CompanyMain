# == Schema Information
#
# Table name: folders
#
#  id               :integer          not null, primary key
#  name             :string(255)
#  parent_folder_id :integer
#  full_path        :text(65535)
#  level            :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  entity_id        :integer          not null
#  documents_count  :integer          default("0"), not null
#  path_ids         :string(255)
#  folder_type      :integer          default("0")
#  owner_type       :string(255)
#  owner_id         :integer
#  deleted_at       :datetime
#

require "test_helper"

class FolderTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
