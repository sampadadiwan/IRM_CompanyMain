# SendGrid (login using support@caphive.com) is used to route incoming emails to our app
# We have setup godaddy domain to route emails to SendGrid
# email@local.caphive.app, email@dev.caphive.app and email@prod.caphive.app are all routed to SendGrid
# SendGrid then forwards the email to our app with the original email address as the recipient
# 2 Use cases:
# 1. We parse the email address to get the owner_id and owner_type - this use case is to attach incoming emails to the owner Example: deal.1@prod.caphive.app or individual_kyc.23@prod.caphive.app
# 2. We also get incoming emails from potential portfolio companies with the investor presentation to the fund

class IncomingEmail < ApplicationRecord
  include WithFolder

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :entity

  def to_s
    "From: #{from}, Subj: #{subject}"
  end

  # This is used to check if the incoming email is sent to an entities mailbox
  before_validation :match_mailbox
  def match_mailbox
    self.entity ||= Entity.joins(:entity_setting).where('entity_settings.mailbox': to).first
    if self.entity.present?
      # Find the investor in this entity that matches the subject
      self.owner ||= entity.investors.where(investor_name: subject.strip).first
    end
  end

  # Note self.to is set to the email address of the owner
  # Example: deal.1@prod.caphive.app or individual_kyc.23@prod.caphive.app
  # see WithIncomingEmail#incoming_email_address
  before_validation :set_owner, if: -> { entity.nil? }
  def set_owner
    match_data = to.match(/(?<owner_type>[\w_]+)\.(?<owner_id>\d+)@(?<subdomain>[\w-]+)\.(?<domain>[\w.-]+)/)
    return nil unless match_data

    # Check if the email is sent to the investor presentations email
    fund_entity = Entity.joins(:entity_setting).where(entity_settings: { investor_presentations_email: to }).first

    if match_data[:owner_type].present? && match_data[:owner_id].present?
      # This email is sent by a user, to a specific owner model
      self.owner ||= match_data[:owner_type].camelize.constantize.find(match_data[:owner_id])
      self.entity_id ||= owner.entity_id
    elsif fund_entity.present?
      # This email is sent by a potential portfolio company, with the investor presentation to the fund.
      self.owner ||= fund_entity
      self.entity_id ||= fund_entity.id
    else
      errors.add(:to, "Invalid email address, does not belong to any owner.")
    end
  rescue StandardError => e
    Rails.logger.error "Error setting owner for incoming email: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
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

  after_create_commit :perform_summarization
  def perform_summarization
    fund_entity = Entity.joins(:entity_setting).where(entity_settings: { investor_presentations_email: to }).first
    # This email is sent by a potential portfolio company, with the investor presentation to the fund.
    if fund_entity.present?
      # Summarize the documents and create a report for the fund
      FolderLlmReportJob.perform_later(folder_id, document_folder_id, report_template_name: "Investor Presentation Template")
      # Also run Fabric to extract wisdom
    end
  end

  # Move the email to the owner's folder
  def folder_path
    "#{owner.folder_path}/Incoming Emails/#{from}"
  end
end
