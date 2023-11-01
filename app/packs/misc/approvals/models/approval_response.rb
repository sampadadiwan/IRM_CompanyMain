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
          if reminder
            # msg = "This is a reminder that #{approval.entity.name} has requested your approval for #{approval.title}. Please use your registered email id to access your account. The password is your PAN (in lower case). You can also log in without a password by sending a link to your registered email id."
            msg = 'Reminder for approval for Change in Investment Manager for SiriusOne Capital Fund. We are proposing to appoint Cumulative Asset Management LLP (CAML) as the new Investment Manager for SiriusOne Capital Fund, in compliance with SEBI regulations. The partners of SiriusOne Capital LLP are also partners in the Proposed Investment Manager i.e. CAML. Your user id is your email provided to SiriusOne Capital Fund and Password is PAN in LOWERCASE.'
            # msg = "Reminder for approval required for #{approval.entity.name} : #{approval.title}."
            ApprovalNotification.with(entity_id:, approval_response: self, email_method: :approval_reminder, msg:).deliver_later(user) unless notification_sent
          else
            # msg = "#{approval.entity.name} has requested your approval for #{approval.title}.Please use your registered email id to access your account. The password is your PAN (in lower case). You can also log in without a password by sending a link to your registered email id."
            msg = 'Approval required for Change in Investment Manager for SiriusOne Capital Fund. We are proposing to appoint Cumulative Asset Management LLP (CAML) as the new Investment Manager for SiriusOne Capital Fund, in compliance with SEBI regulations. The partners of SiriusOne Capital LLP are also partners in the Proposed Investment Manager i.e. CAML. Your user id is your email provided to SiriusOne Capital Fund and Password is PAN in LOWERCASE.'
            # msg = "Approval required for #{approval.entity.name} : #{approval.title}."
            ApprovalNotification.with(entity_id:, approval_response: self, email_method: :notify_new_approval, msg:).deliver_later(user) unless notification_sent
          end
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
