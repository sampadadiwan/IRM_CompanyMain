class ESignature < ApplicationRecord
  belongs_to :entity, optional: true
  validates :entity_id, presence: true
  # If the user is nil, then its a template for use, which is filled in by the owner
  belongs_to :user, optional: true
  # self.ignored_columns = ["user_id"]
  # Is the offer, commitment etc whose document needs to be signed
  belongs_to :document
  attr_readonly :document_id # never moves to another document (funds_api_security_policy_plan.md, B)
  acts_as_list scope: :document

  validates :label, length: { maximum: 50 }
  validates :email, length: { maximum: 60 }, allow_blank: true
  validates :signature_type, length: { maximum: 10 }, allow_blank: true

  # validates_presence_of :email, if: -> { !document.template }
  normalizes :email, with: ->(v) { v&.gsub(/\s+/, '') }
  normalizes :notes, with: ->(v) { v&.strip }
  validate :email_must_be_valid, if: -> { email.present? }
  validates_uniqueness_of :email, scope: :document_id, allow_blank: true, allow_nil: true, if: -> { email.present? }
  validates_uniqueness_of :label, scope: %i[document_id signature_type],
                                  if: -> { document.template? && label.present? && label != "Other" }

  # Signer statuses after which this signature request can no longer be signed in the platform.
  # "failed" is deliberately absent: a failed attempt can be retried while the request is open.
  CLOSED_STATUSES = %w[cancelled expired rejected voided].freeze

  SIGNATURE_METHOD_LABELS = { "aadhaar" => "Aadhaar eSign", "electronic" => "Electronic signature", "dsc" => "Digital signature (DSC)" }.freeze

  scope :in_sequence, -> { order(:position) }
  scope :requested, -> { where(status: "requested") }
  scope :signed, -> { where(status: "signed") }
  scope :not_signed, -> { where.not(status: "signed").or(where(status: nil)) }

  before_validation :setup_entity
  def setup_entity
    self.entity_id = document.entity_id
  end

  before_save :update_status
  def update_status
    self.status = "" if signature_type_changed?
  end

  after_save :update_document
  def update_document
    document.signature_enabled = true
    document.save
  end

  # added email in the error message
  def email_must_be_valid
    errors.add(:email, "#{email} is not valid") unless email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def add_api_update(update_data)
    if api_updates.present?
      api_updates + update_data.to_s
    else
      self.api_updates = update_data.to_s
    end
  end

  # @param payload kept on the signer row when given; Digio's payloads stay in the esign log instead
  def update_esign_response(payload_status, payload = nil)
    # DIGIO sometimes sends us old callbacks
    if new_status?(payload_status)
      add_api_update(payload) if payload
      message = "Document - #{document.name}'s eSign status updated"
      logger.info message
    else
      e = StandardError.new("eSign already has status #{status} for #{document.name} - #{payload}")
      logger.error e.message
    end
  end

  def new_status?(payload_status)
    esigns = ESignature.where(id:)
    unchangeable = %w[signed expired]
    # Digio's status pull has no "rejected", so a later pull would flip it back to "requested". Keep it,
    # unless the signature actually arrives. Re-Send clears the status, which is the way out.
    unchangeable << "rejected" unless payload_status.to_s.casecmp?("signed")
    esigns.where.not(status: [payload_status, *unchangeable]).or(esigns.where(status: nil)).update_all(status: payload_status).positive?
  end

  # Takes the one-time right to notify this signer for the current request. Atomic: of two paths confirming the
  # same signature together (a webhook and a status check, or Digio's retry), exactly one gets true.
  # Re-Send clears the column, so a new request notifies again. Worked example E32, E33.
  # @return [Boolean] true only for the caller that set it
  def claim_signing_notification!
    ESignature.where(id:, signing_notified_at: nil).update_all(signing_notified_at: Time.zone.now).positive?
  end

  # Is this user the person the signature is requested from? Identity only: the login email equals the
  # signer email, ignoring letter case. Entity membership is irrelevant: an investor signs another entity's document.
  # @param user [User, nil]
  # @return [Boolean]
  def signable_by?(user)
    user.present? && email.present? && email.casecmp?(user.email.to_s)
  end

  # Where this signer is in embedded signing. Reads stored statuses only; Digio stays the source of truth.
  # @return [Symbol] :closed (document no longer waiting, or this request is over), :signed,
  #   :waiting_turn (an earlier signer is pending on an ordered document) or :ready
  def signing_state
    return :closed unless document.sent_for_esign && document.esign_status.to_s.casecmp?("requested")
    return :signed if status.to_s.casecmp?("signed")
    return :closed if CLOSED_STATUSES.include?(status.to_s.downcase)
    return :waiting_turn if document.force_esign_order && earlier_signer_pending?

    :ready
  end

  # The signer row on a document that belongs to this user, if any. Document-scoped, so it uses the
  # document_id index and looks at a handful of rows.
  # @param document [Document]
  # @param user [User, nil]
  # @return [ESignature, nil]
  def self.signer_row(document, user)
    return nil if user.blank? || user.email.blank?

    document.e_signatures.find_by("LOWER(e_signatures.email) = ?", user.email.to_s.downcase)
  end

  # @return [String] what the signer reads for the signature method, e.g. "Aadhaar eSign"
  def signature_method_label
    SIGNATURE_METHOD_LABELS.fetch(signature_type.to_s.downcase, signature_type.to_s.titleize)
  end

  # @return [Array<Integer>] this signer's 1-based place and how many signers the document has
  def signer_place
    ids = document.e_signatures.in_sequence.pluck(:id)
    [(ids.index(id) || 0) + 1, ids.size]
  end

  def earlier_signer_pending?
    position.present? && document.e_signatures.not_signed.exists?(position: ...position)
  end

  # status can be [nil, "signed", "failed", "requested", "cancelled", "voided", "expired", "sent"]
  def status_badge
    case status&.downcase
    when "signed", "completed"
      "success"
    when "failed", "cancelled", "expired", "voided", "rejected"
      "danger"
    when "requested"
      "warning"
    when "sent"
      "info"
    else
      "secondary"
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at email label signature_type signer_id status updated_at]
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
