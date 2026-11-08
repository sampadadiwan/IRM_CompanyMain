class ApprovalResponse < ApplicationRecord
  include Trackable.new
  include WithCustomField
  include WithIncomingEmail
  include WithFolder
  include ForInvestor

  belongs_to :entity
  belongs_to :investor

  # The Approval Responses list's columns before a firm chooses its own (openspec/changes/grid-columns-inline-settings
  # — D21). Plain attributes only, so the report builder can query them.
  STANDARD_COLUMNS = {
    "Status" => "status",
    "Updated On" => "updated_at"
  }.freeze
  # Exactly what the list showed when it was a hand-built table (ApprovalResponseDecorator cells)
  LIST_COLUMNS = {
    "Investor" => "investor_link",
    "Tag" => "investor_tags",
    "Response By" => "response_user_name",
    "Status" => "status_badge",
    "Updated On" => "updated_on"
  }.freeze
  # List-only cells the columns editor offers (never the report builder)
  GRID_COLUMNS = LIST_COLUMNS.transform_keys { |label| label == "Status" ? "Status (badge)" : label }.freeze
  # This is the folio, offer, deal_investor
  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :response_entity, class_name: "Entity"
  belongs_to :response_user, class_name: "User", optional: true
  belongs_to :approval, touch: true
  attr_readonly :approval_id # never moves to another approval (funds_api_security_policy_plan.md, B)
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

  # An answer must be one of the options the firm offered (approvals.response_status), on every path:
  # the app, the mobile app's approve.json and the emailed links. Pending, the starting state, is
  # always allowed here (no_pending_response refuses it as an answer). Checked only when status
  # changes, so a response whose option was later removed from the approval still saves.
  # Options typed as "Approved, Rejected" reach us as " Rejected" from older links and forms
  normalizes :status, with: ->(status) { status.strip }
  validate :status_is_offered_option, if: :will_save_change_to_status?
  def status_is_offered_option
    return if status == "Pending" || approval.nil?

    errors.add(:status, "#{status} is not a response option for this approval") if approval.offered_statuses.exclude?(status)
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
        investor.notification_users(with_tag: 'Approval').each do |user|
          email_method = reminder ? :approval_reminder : :notify_new_approval
          ApprovalNotifier.with(record: self, investor_id:, entity_id:, email_method:).deliver_later(user) unless notification_sent
        end
      else
        msg = "Your response for Approval #{approval.title} has been registered as #{status}"
        investor.notification_users(with_tag: 'Approval').each do |user|
          ApprovalNotifier.with(record: self, investor_id:, entity_id:, email_method: :notify_approval_response, msg:).deliver_later(user)
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
