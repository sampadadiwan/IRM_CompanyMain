class Approval < ApplicationRecord
  include WithFolder

  belongs_to :entity
  has_rich_text :agreements_reference
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :approval_investors, through: :approval_responses, class_name: "Investor", source: :investor
  has_many :pending_investors, -> { where('approval_responses.status': "Pending") }, through: :approval_responses, class_name: "Investor", source: :investor

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :title, :due_date, presence: true

  def name
    title
  end

  def folder_path
    "/Approvals/#{title}-#{id}"
  end

  def self.for_investor(user)
    Approval
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end

  def generate_responses
    investors.each do |inv|
      existing = approval_responses.select { |resp| resp.response_entity_id == inv.investor_entity_id }

      if existing.present?
        logger.debug "Skipping ApprovalResponse creation, already exists #{existing}"
      else
        ApprovalResponse.create(entity_id:,
                                investor_id: inv.id, response_entity_id: inv.investor_entity_id,
                                response_user_id: nil, approval_id: id, status: "Pending")
        logger.debug "Creating pending ApprovalResponse for #{inv.investor_name}"
      end
    end
    nil
  end

  after_commit :send_notification
  def send_notification
    generate_responses
    ApprovalMailer.with(id:).notify_new_approval.deliver_later if saved_change_to_approved?
  end

  def access_rights_changed(access_right)
    access_right = AccessRight.where(id: access_right.id).first
    if access_right
      logger.debug "Added new Access Rights for Approval #{id}"
      generate_responses
      ApprovalMailer.with(id:, access_right_id: access_right.id).notify_new_approval.deliver_later
    end
  end

  def investor_users(metadata = nil)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end
end
