class Approval < ApplicationRecord
  include WithFolder

  belongs_to :entity
  has_rich_text :agreements_reference
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  has_many :approval_responses, dependent: :destroy

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  def name
    title
  end

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, title, [])
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

  after_save :send_notification
  def send_notification
    if saved_change_to_approved? && approved
      generate_responses
      ApprovalMailer.with(id:).notify_new_approval.deliver_later
    end
  end

  def access_rights_changed(access_right_id)
    generate_responses
    ApprovalMailer.with(id:, access_right_id:).notify_new_approval.deliver_later
  end
end
