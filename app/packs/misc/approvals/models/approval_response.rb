class ApprovalResponse < ApplicationRecord
  has_paper_trail

  belongs_to :entity
  belongs_to :investor
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User", optional: true
  belongs_to :approval, touch: true
  has_noticed_notifications

  has_rich_text :details

  counter_culture :approval, column_name: proc { |resp| resp.status == 'Approved' ? 'approved_count' : nil }
  counter_culture :approval, column_name: proc { |resp| resp.status == 'Rejected' ? 'rejected_count' : nil }
  counter_culture :approval, column_name: proc { |resp| %w[Approved Rejected].include?(resp.status) ? nil : 'pending_count' }

  validate :already_exists, on: :create
  validates :status, length: { maximum: 50 }

  scope :pending, -> { where("approval_responses.status=?", "Pending") }

  def already_exists
    errors.add(:approval, "Approval Response for this investor and approval already exists. Please delete of edit the existing response") if approval.approval_responses.where(response_entity_id:).count.positive?
  end

  validate :no_pending_response, if: proc { |r| !r.new_record? }
  def no_pending_response
    errors.add(:status, 'You need to select a response other than Pending') if status == "Pending"
  end

  after_commit :send_notification, unless: :destroyed?
  def send_notification(reminder: false)
    # send notification to the investor only if the approval is approved
    if approval.approved

      if status == "Pending"
        investor.approved_users.each do |user|
          email_method = reminder ? :approval_reminder : :notify_new_approval
          ApprovalNotification.with(entity_id:, approval_response: self, email_method:).deliver_later(user) unless notification_sent
        end
      else
        msg = "Your response for Approval #{approval.title} has been registered as #{status}"
        # msg = "#{approval.entity.name} : #{status} for #{approval.title}"
        investor.approved_users.each do |user|
          ApprovalNotification.with(entity_id:, approval_response: self, email_method: :notify_approval_response, msg:).deliver_later(user)
        end
      end

    end

    # Ensure that the investor entity is set to enable approvals
    e = investor.investor_entity

    unless e.enable_approvals
      e.enable_approvals = true
      e.save
    end
  end
end
