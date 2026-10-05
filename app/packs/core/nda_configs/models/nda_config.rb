# frozen_string_literal: true

# @description Polymorphic NDA configuration for any model that includes WithNda.
#   Stores the NDA toggle, uploaded PDF document, validity settings, acceptance method,
#   and notification preferences. Soft-deleted via Trackable (acts_as_paranoid).
#
# Changed: Renamed from FolderNdaConfig, moved from core/folders/ to core/nda_configs/.
# Why: Reviewer feedback on PR #1750 — NdaConfig should attach to any model via
#   polymorphic belongs_to :owner, not just Folder.
#
# @see WithNda
# @see NdaConfigPolicy
class NdaConfig < ApplicationRecord
  include Trackable.new
  include FileUploader::Attachment(:nda_document)

  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\z/

  VALIDITY_TYPES = %w[until_revoked fixed_period specific_date].freeze
  ACCEPTANCE_METHODS = %w[click_through esign].freeze
  VALIDITY_DAY_OPTIONS = [30, 90, 180, 365].freeze

  # Changed: belongs_to :folder → belongs_to :owner, polymorphic: true.
  # Why: Allows NDA attachment to any model (Folder, InvestmentOpportunity, etc.).
  belongs_to :owner, polymorphic: true
  belongs_to :entity
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  # Changed: Added has_many :nda_acceptances association.
  # Why: Module 2 LP Acceptance — tracks accept/decline records per NdaConfig.
  has_many :nda_acceptances, dependent: :destroy

  # Changed: Added has_many :nda_exemptions association.
  # Why: Module 3 GP Dashboard — tracks user-level NDA exemptions per NdaConfig.
  has_many :nda_exemptions, dependent: :destroy

  # Changed: Added has_many :nda_signatories association.
  # Why: Module 3 GP Dashboard — tracks per-NDA signatory designations (replaces entity-wide tag_list).
  has_many :nda_signatories, dependent: :destroy

  validates :validity_type, inclusion: { in: VALIDITY_TYPES }
  validates :acceptance_method, inclusion: { in: ACCEPTANCE_METHODS }
  validates :validity_days, inclusion: { in: VALIDITY_DAY_OPTIONS }, if: -> { validity_type == "fixed_period" }
  validates :validity_days, presence: true, if: -> { validity_type == "fixed_period" }
  validates :validity_date, presence: true, if: -> { validity_type == "specific_date" }
  validates :contact_email, format: { with: EMAIL_FORMAT }, allow_blank: true

  validate :nda_document_must_be_pdf
  validate :validity_date_must_be_future, if: -> { validity_type == "specific_date" && validity_date.present? }
  validate :notification_emails_must_be_valid

  # Changed: set_entity_from_folder → set_entity_from_owner.
  # Why: Entity is now derived from the polymorphic owner, not a direct folder reference.
  before_validation :set_entity_from_owner
  before_validation :normalize_notification_emails

  private

  # @return [void] Sets entity_id from the polymorphic owner's entity.
  def set_entity_from_owner
    self.entity_id = owner&.entity_id if owner
  end

  # @return [void] Converts comma-separated email string from the form into a JSON array.
  def normalize_notification_emails
    return if notification_emails.blank?
    return if notification_emails.start_with?("[")

    emails = notification_emails.split(",").map(&:strip).compact_blank
    self.notification_emails = emails.to_json
  end

  # @return [void] Validates that the NDA document is a PDF when NDA is enabled.
  def nda_document_must_be_pdf
    return unless enabled?

    if nda_document.nil?
      errors.add(:nda_document, "is required when NDA is enabled")
      return
    end

    mime = nda_document&.mime_type
    errors.add(:nda_document, "must be a PDF") if mime.present? && mime != "application/pdf"
  end

  # @return [void] Validates that the validity date is in the future.
  def validity_date_must_be_future
    errors.add(:validity_date, "must be in the future") if validity_date <= Date.current
  end

  # @return [void] Validates that all notification emails are valid email addresses.
  def notification_emails_must_be_valid
    return if notification_emails.blank?

    begin
      parsed = JSON.parse(notification_emails)
    rescue JSON::ParserError
      errors.add(:notification_emails, "must be a valid list of email addresses")
      return
    end

    unless parsed.is_a?(Array)
      errors.add(:notification_emails, "must be a valid list of email addresses")
      return
    end

    invalid = parsed.reject { |e| e.is_a?(String) && e.match?(EMAIL_FORMAT) }
    errors.add(:notification_emails, "contains invalid email addresses: #{invalid.join(', ')}") if invalid.any?
  end
end
