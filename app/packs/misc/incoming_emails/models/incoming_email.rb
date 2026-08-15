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
  belongs_to :filed_by_user, class_name: 'User', optional: true

  # Blank must become NULL, not "". idx_incoming_emails_dedup is unique across
  # (entity_id, internet_message_id, owner_type, owner_id), and while both MySQL and SQLite
  # allow repeated NULLs in a unique index, they do not allow repeated "". A client that
  # cannot supply a Message-ID sends an empty string, which would otherwise make two
  # completely unrelated emails collide and the second one be reported as "already filed"
  # against the first.
  normalizes :internet_message_id, with: ->(value) { value.presence }
  normalizes :message_id, with: ->(value) { value.presence }

  def to_s
    "From: #{from}, Subj: #{subject}"
  end

  # Removes this filing without taking the shared folder — and other emails' documents —
  # with it.
  #
  # #folder_path resolves to one folder per (owner, sender), and setup_document_folder
  # reuses an existing folder at that path, so every email from the same sender to the same
  # investor shares one Folder. WithFolder then attaches that folder to the email twice
  # over: `belongs_to :document_folder, dependent: :destroy` and
  # `has_many :folders, as: :owner, dependent: :destroy`, where the owner is whichever
  # email most recently materialised it. Folder itself declares
  # `has_many :documents, dependent: :destroy`.
  #
  # So a plain destroy of one filing can delete the shared folder through *either* path and
  # take every document in it, including other emails' attachments. Both links are severed
  # here; the folder is handed to another email that still points at it, or left ownerless
  # rather than deleted. This email's own attachments still cascade through
  # `has_many :documents, as: :owner, dependent: :destroy`, which is intended.
  def destroy_filing!
    folder = document_folder_id.present? ? Folder.find_by(id: document_folder_id) : nil
    update_column(:document_folder_id, nil) if document_folder_id.present?

    if folder && folder.owner_type == self.class.name && folder.owner_id == id
      # document_folder_id is already cleared above, so this cannot find self.
      heir_id = IncomingEmail.where(document_folder_id: folder.id).limit(1).pick(:id)
      folder.update_columns(owner_id: heir_id, owner_type: heir_id ? self.class.name : nil)
    end

    destroy!
  end

  # This is used to check if the incoming email is sent to an entities mailbox
  before_validation :match_mailbox
  def match_mailbox
    return if entity.present?

    self.entity ||= Entity.joins(:entity_setting).where('entity_settings.mailbox': to).first
    if entity.present? && subject.present?
      # subject.present? guard: empty-subject mail is common, and strip on nil raised
      # NoMethodError here, 500ing the SendGrid webhook.
      # matches() generates ILIKE on Postgres and LIKE on SQLite — both case-insensitive
      self.owner ||= entity.investors.where(Investor.arel_table[:investor_name].matches(subject.strip)).first
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
    errors.add(:base, "Could not resolve email owner: #{e.message}")
  end

  # SendGrid posts attachments as attachment1, attachment2, ... alongside the mail fields.
  def save_attachments(params)
    attachment_keys = params.keys.select { |k| k.start_with?("attachment") && params[k].is_a?(ActionDispatch::Http::UploadedFile) }
    return if attachment_keys.empty?

    # Resolve once outside the loop to avoid N+1 queries per attachment
    user = User.where(email: from).first || entity.employees.first || User.support_users.first
    save_uploaded_attachments(attachment_keys.map { |key| params[key] }, user: user)
  end

  # Shared attachment path, used by the SendGrid webhook above and by the Outlook/Gmail
  # add-ins via MailFilingCreate. The add-ins attribute the documents to the filing user;
  # SendGrid has no signed-in user and resolves one from the sender.
  # @param files [Array<ActionDispatch::Http::UploadedFile>]
  # @param user [User] who the resulting Documents are attributed to
  # @return [Array<String>] messages for files that could not be saved, so callers can
  #   report a partial failure instead of a clean success with documents missing
  def save_uploaded_attachments(files, user:)
    Array(files).compact.filter_map do |file|
      document = documents.build(name: file.original_filename, entity:, user:, orignal: true)
      document.file = file.tempfile
      next if document.save

      "#{file.original_filename}: #{document.errors.full_messages.join(', ')}"
    end
  end

  after_create_commit :perform_summarization
  def perform_summarization
    # owner is already resolved by set_owner; no need to re-query entity_settings
    return unless owner.is_a?(Entity)

    FolderLlmReportJob.perform_later(folder_id, document_folder_id, report_template_name: "Investor Presentation Template")
  end

  # Move the email to the owner's folder
  def folder_path
    "#{owner.folder_path}/Incoming Emails/#{from}"
  end
end
