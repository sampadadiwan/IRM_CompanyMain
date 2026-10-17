class Approval < ApplicationRecord
  include Workflowable

  # Auto-assignment rules use ransackable_attributes (end of file) plus the approval forms' custom fields
  workflow_rule_fields
  include Trackable.new
  include WithFolder
  include WithCustomField
  include InvestorsGrantedAccess
  include WithCustomNotifications
  include WithIncomingEmail
  include ForInvestor

  belongs_to :entity
  # Associated owner such as Fund, Deal etc. The AccessRights of the owner will be copied over to the approval post creation
  belongs_to :owner, polymorphic: true, optional: true

  has_rich_text :agreements_reference
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :approval_investors, through: :approval_responses, class_name: "Investor", source: :investor
  has_many :pending_investors, -> { where('approval_responses.status': "Pending") }, through: :approval_responses, class_name: "Investor", source: :investor

  validates :title, :due_date, :response_status, presence: true

  def initialize(*)
    super
    self.due_date ||= Time.zone.today + 7.days
    default_response_status
  end

  def name
    title
  end

  def to_s
    title
  end

  # Workflowable interface uses all defaults from the concern:
  #   workflow_display_name → to_s (→ title)
  #   workflow_url          → approval_path(self)
  #   workflow_attachable_files → []

  def default_response_status
    self.response_status ||= "Approved,Pending,Rejected"
  end

  def folder_path
    "/Approvals/#{title.delete('/')}-#{id_or_random_int}"
  end

  def self.for_investor(user)
    Approval
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.investor_list_filter(user)) # B3-3: personal grants only for a switched advisor
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end

  def generate_responses
    investors.each do |inv|
      if owner
        # Generate a response for each investor's folio in the fund
        owner.approval_for(inv.id).each do |approval_response_owner|
          create_response(inv, approval_response_owner:)
        end
      else
        # Generate a response for each investor
        create_response(inv)
      end
    end
    nil
  end

  def create_response(inv, approval_response_owner: nil)
    ar = if approval_response_owner
           ApprovalResponse.find_or_initialize_by(entity_id:, investor_id: inv.id, owner: approval_response_owner,
                                                  response_entity_id: inv.investor_entity_id, approval_id: id)
         else
           ApprovalResponse.find_or_initialize_by(entity_id:, investor_id: inv.id, owner: nil,
                                                  response_entity_id: inv.investor_entity_id, approval_id: id)
         end

    if ar.new_record?
      ar.status = "Pending"
      ar.save
      logger.debug "Creating pending ApprovalResponse for #{inv.investor_name}"
    else
      logger.debug "ApprovalResponse already exists for #{inv.investor_name}"
    end
  end

  def send_notification(reminder: false)
    # Send notification to all investors once its approved
    if approved && !destroyed?
      approval_responses.pending.includes(investor: :approved_users).find_each do |ar|
        ar.send_notification(reminder:)
      end
      logger.debug "Approval #{id} send_notification completed"
    else
      logger.debug "Approval #{id} send_notification skipped"
    end
  end

  def access_rights_changed(access_right)
    access_right = AccessRight.where(id: access_right.id).first
    if access_right
      logger.debug "Added new Access Rights for Approval #{id}"
      generate_responses
    end
  end

  def setup_owner_access_rights
    if owner.present?
      owner.access_rights.each do |ar|
        new_ar = ar.dup
        new_ar.entity_id = entity_id
        new_ar.owner = self
        new_ar.save
      end
    else
      Rails.logger.debug "No access rights to setup"
    end
    true
  end

  # Approvals had no Ransack allowlist, so nothing could be searched or tested by an auto-assignment
  # rule; these are the approval's own routing-relevant columns (workflow-rule-condition-builder card 1)
  def self.ransackable_attributes(_auth_object = nil)
    %w[approved due_date locked owner_type response_status title]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
