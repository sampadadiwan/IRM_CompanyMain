class ApprovalResponse < ApplicationRecord
  has_paper_trail

  belongs_to :entity
  belongs_to :investor
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User", optional: true
  belongs_to :approval, touch: true
  has_rich_text :details

  counter_culture :approval, column_name: proc { |resp| resp.status == 'Approved' ? 'approved_count' : nil }
  counter_culture :approval, column_name: proc { |resp| resp.status == 'Rejected' ? 'rejected_count' : nil }
  counter_culture :approval, column_name: proc { |resp| resp.status == 'Pending' ? 'pending_count' : nil }

  validate :already_exists, on: :create
  validates :status, length: { maximum: 50 }

  scope :pending, -> { where("approval_responses.status=?", "Pending") }

  def already_exists
    errors.add(:approval, "Approval Response for this investor and approval already exists. Please delete of edit the existing response") if approval.approval_responses.where(response_entity_id:).count.positive?
  end

  after_commit :send_notification
  def send_notification
    # send notification to the investor only if the approval is approved
    if approval.approved

      if status == "Pending"
        investor.approved_users.each do |user|
          ApprovalNotification.with(approval_response_id: id, email_method: :notify_new_approval, msg: "Approval Required: #{approval.title}").deliver_later(user) unless notification_sent
        end
      else
        investor.approved_users.each do |user|
          ApprovalNotification.with(approval_response_id: id, email_method: :notify_approval_response, msg: "Approval #{status} by #{investor.investor_name}: #{approval.title}").deliver_later(user)
        end
      end

    end
  end
end
