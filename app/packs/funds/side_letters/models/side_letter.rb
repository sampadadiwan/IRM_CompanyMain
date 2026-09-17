# A side letter negotiated for one capital commitment. The commitment is the
# anchor (it already carries fund + investor + folio and the document folder);
# fund/investor are always reached through it. The referenced Document is the
# executed side letter PDF uploaded to the commitment.
class SideLetter < ApplicationRecord
  belongs_to :entity
  belongs_to :capital_commitment
  belongs_to :document

  has_many :side_letter_obligations, dependent: :destroy

  delegate :fund, :investor, to: :capital_commitment

  # pending           — created, nothing extracted yet
  # ai_extracted      — SideLetterObligationAgent has produced pending obligations
  # manually_entered  — obligations were entered by hand (no AI pass)
  # counsel_reviewed  — every extracted obligation has been approved or rejected
  enum :extraction_status, {
    pending: "pending",
    ai_extracted: "ai_extracted",
    manually_entered: "manually_entered",
    counsel_reviewed: "counsel_reviewed"
  }

  validates :capital_commitment_id, uniqueness: { scope: :document_id }
  # Params are not to be trusted: the linked PDF must actually live on this commitment
  validate :document_belongs_to_commitment

  def document_belongs_to_commitment
    return if document.blank? || capital_commitment.blank?
    return if document.owner_type == "CapitalCommitment" && document.owner_id == capital_commitment_id

    errors.add(:document_id, "does not belong to this commitment")
  end

  # Flip to counsel_reviewed once no obligation is left awaiting review —
  # called after each approve/reject so the matrix reflects review completion.
  def refresh_extraction_status!
    return if side_letter_obligations.where(review_status: "pending_review").exists?

    update!(extraction_status: "counsel_reviewed") if ai_extracted?
  end

  # Display label for pickers (e.g. the obligation form's side letter select)
  def to_s
    "#{capital_commitment.investor_name} — #{document.name} (#{fund.name})"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[executed_at extraction_status]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment side_letter_obligations]
  end
end
