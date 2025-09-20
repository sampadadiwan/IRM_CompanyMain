class ApprovalResponse < ApplicationRecord
  include Trackable.new
  include WithCustomField
  include WithIncomingEmail
  include WithFolder
  include ForInvestor

  belongs_to :entity
  belongs_to :investor
  # This is the folio, offer, deal_investor
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User", optional: true
  belongs_to :approval, touch: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  has_rich_text :details

  counter_culture :approval, column_name: proc { |resp| resp.status == 'Approved' ? 'approved_count' : nil }
  counter_culture :approval, column_name: proc { |resp| resp.status == 'Rejected' ? 'rejected_count' : nil }
  counter_culture :approval, column_name: proc { |resp| %w[Approved Rejected].include?(resp.status) ? nil : 'pending_count' }

  # validate :already_exists, on: :create
  validates :status, length: { maximum: 50 }
  validates :investor_id, uniqueness: { scope: %i[approval_id owner_type owner_id], message: "Investor already has a response for this approval" }

  scope :pending, -> { where("approval_responses.status=?", "Pending") }

  validate :no_pending_response, if: proc { |r| !r.new_record? }
  def no_pending_response
    errors.add(:status, 'You need to select a response other than Pending') if status == "Pending"
  end

  def to_s
    "#{investor.investor_name} - #{status}"
  end

  def folder_path
    "#{approval.folder_path}/Responses/#{investor.investor_name}-#{id_or_random_int}"
  end

  after_commit :send_notification, unless: proc { |r| r.destroyed? || r.deleted_at.present? }
  def send_notification(reminder: false)
    # send notification to the investor only if the approval is approved
    if approval.approved

      if status == "Pending"
        investor.notification_users.each do |user|
          email_method = reminder ? :approval_reminder : :notify_new_approval
          ApprovalNotifier.with(record: self, investor_id: investor.id, email_method:).deliver_later(user) unless notification_sent
        end
      else
        msg = "Your response for Approval #{approval.title} has been registered as #{status}"
        # msg = "#{approval.entity.name} : #{status} for #{approval.title}"
        investor.notification_users.each do |user|
          ApprovalNotifier.with(record: self, investor_id: investor.id, email_method: :notify_approval_response, msg:).deliver_later(user)
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
