# == Schema Information
#
# Table name: documents
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  visible_to        :string(255)      default("--- []\n")
#  text              :string(255)      default("--- []\n")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  file_file_name    :string(255)
#  file_content_type :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  entity_id         :integer          not null
#  deleted_at        :datetime
#  folder_id         :integer          not null
#  impressions_count :integer          default("0")
#  properties        :text(65535)
#  form_type_id      :integer
#  download          :boolean          default("0")
#  printing          :boolean          default("0")
#  file_data         :text(65535)
#  owner_type        :string(255)
#  owner_id          :integer
#  owner_tag         :string(20)
#  orignal           :boolean          default("0")
#  user_id           :integer          not null
#

require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
