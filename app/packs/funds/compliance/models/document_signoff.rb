# ⑦ Wet-ink sign-off: a person marks an uploaded scan as signed and enters the date it was signed.
# Timing tests use this signed date, never the upload date (H23, E26, X27, R35).
class DocumentSignoff < ApplicationRecord
  belongs_to :entity
  belongs_to :document
  belongs_to :marked_by, class_name: "User"

  # Audit changes and deletions only — the row itself records its creation (who/when columns, created_at) (R177)

  audited on: %i[update destroy]
  attr_readonly :entity_id

  validates :signed_on, presence: true
  validates :document_id, uniqueness: true
  validate :signed_on_not_in_future
  validate :document_in_same_firm

  private

  # X27: "Signed date cannot be in the future"
  def signed_on_not_in_future
    errors.add(:base, "Signed date cannot be in the future") if signed_on.present? && signed_on > Time.zone.today
  end

  def document_in_same_firm
    errors.add(:base, "Document not found") if document && document.entity_id != entity_id
  end
end
