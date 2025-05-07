class ESignature < ApplicationRecord
  belongs_to :entity
  # If the user is nil, then its a template for use, which is filled in by the owner
  belongs_to :user, optional: true
  # self.ignored_columns = ["user_id"]
  # Is the offer, commitment etc whose document needs to be signed
  belongs_to :document
  acts_as_list scope: :document

  # validates_presence_of :email, if: -> { !document.template }
  validates_format_of :email, with: URI::MailTo::EMAIL_REGEXP, multiline: true, if: -> { email.present? }
  validates_uniqueness_of :email, scope: :document_id, allow_blank: true, allow_nil: true, if: -> { email.present? }
  validates_uniqueness_of :label, scope: %i[document_id signature_type],
                                  if: -> { document.template? && label.present? && label != "Other" }

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

  def add_api_update(update_data)
    if api_updates.present?
      api_updates + update_data.to_s
    else
      self.api_updates = update_data.to_s
    end
  end

  def update_esign_response(payload_status, payload)
    # DIGIO sometimes sends us old callbacks
    if new_status?(payload_status)
      add_api_update(payload)
      message = "Document - #{document.name}'s eSign status updated"
      logger.info message
    else
      e = StandardError.new("eSign already has status #{status} for #{document.name} - #{payload}")
      logger.error e.message
    end
  end

  def new_status?(payload_status)
    esigns = ESignature.where(id:)
    esigns.where.not(status: [payload_status, "signed", "expired"]).or(esigns.where(status: nil)).update_all(status: payload_status).positive?
  end

  # status can be [nil, "signed", "failed", "requested", "cancelled", "voided", "expired", "sent"]
  def status_badge
    case status&.downcase
    when "signed", "completed"
      "success"
    when "failed", "cancelled", "expired", "voided"
      "danger"
    when "requested"
      "warning"
    when "sent"
      "info"
    else
      "secondary"
    end
  end
end
