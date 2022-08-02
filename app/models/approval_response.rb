class ApprovalResponse < ApplicationRecord
  belongs_to :entity
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User"
  belongs_to :approval, touch: true
  has_rich_text :details

  counter_culture :approval, column_name: proc { |resp| resp.status == 'Approved' ? 'approved_count' : nil }
  counter_culture :approval, column_name: proc { |resp| resp.status == 'Rejected' ? 'rejected_count' : nil }

  validate :already_responded

  def already_responded
    errors.add(:approval, "Already responded to this approval. Please delete of edit the existing response") if approval.approval_responses.where(response_entity_id:).count.positive?
  end
end
