# SendGrid is used to route incoming emails to our app
# We have setup godaddy domain to route emails to SendGrid
# email@local.caphive.app, email@dev.caphive.app and email@prod.caphive.app are all routed to SendGrid
# SendGrid then forwards the email to our app with the original email address as the recipient
# We parse the email address to get the owner_id and owner_type
class IncomingEmail < ApplicationRecord
  include WithFolder

  belongs_to :owner, polymorphic: true
  belongs_to :entity

  def to_s
    "From: #{from}, Subj: #{subject}"
  end

  # Note self.to is set to the email address of the owner
  # Example: deal.1@prod.caphive.app or individual_kyc.23@prod.caphive.app
  # see WithIncomingEmail#incoming_email_address
  before_validation :set_owner
  def set_owner
    match_data = to.match(/(?<owner_type>[\w_]+)\.(?<owner_id>\d+)@(?<subdomain>[\w-]+)\.(?<domain>[\w.-]+)/)
    return nil unless match_data

    if match_data[:owner_type].present? && match_data[:owner_id].present?
      self.owner = match_data[:owner_type].camelize.constantize.find(match_data[:owner_id])
      self.entity_id = owner.entity_id
    else
      errors.add(:to, "Invalid email address, does not belong to any owner.")
    end
  end

  def save_attachments(params)
    attachment_keys = params.keys.select { |k| k.start_with?("attachment") && params[k].is_a?(ActionDispatch::Http::UploadedFile) }
    # For each attachment, create a document
    attachment_keys.each do |key|
      file = params[key]
      user = User.where(email: from).first || entity.employees.first || User.support_users.first
      document = documents.build(name: file.original_filename, entity:, user:, orignal: true)
      document.file = file.tempfile
      document.save
    end
  end

  # Move the email to the owner's folder
  def folder_path
    "#{owner.folder_path}/Incoming Emails/#{from}"
  end
end
