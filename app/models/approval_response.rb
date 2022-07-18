class ApprovalResponse < ApplicationRecord
  belongs_to :entity
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User"
  belongs_to :approval
  has_rich_text :details
end
