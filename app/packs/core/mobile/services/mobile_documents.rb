# Which documents the LP mobile app lists: those attached to the investor's own records — their
# commitments (statements, SOAs, agreements), capital calls (call notices) and distribution
# payments (advices) — that the website would also show them.
#
# The visibility rule is DocumentPolicy#show?'s owner path, applied in SQL so the list never
# needs a per-row policy call:
#   * the owner is one of the user's records (their Pundit scopes);
#   * the folder is not private;
#   * a generated document is shown only once approved (signed copies always) — the same rule as
#     CapitalCommitment#docs_for_investor and DocumentPolicy#not_generated_or_approved.
# Each document opened is still authorised with `authorize doc, :show?` (X18).
#
# Data-room folders are deliberately NOT listed: they are browsed on the website, where the NDA
# gate (DocumentsController#ensure_nda_accepted) applies (lp-mobile-app E20).
class MobileDocuments
  OWNER_TYPES = %w[CapitalCommitment CapitalRemittance CapitalDistributionPayment].freeze

  # A generated document is visible to the investor only once approved; signed copies always.
  # The same rule as DocumentPolicy#not_generated_or_approved, in SQL.
  APPROVED_SQL = "documents.from_template_id IS NULL OR documents.owner_tag = 'Signed' OR documents.approved = TRUE".freeze

  # The newest notice the investor may see on a remittance (call notice) or distribution payment
  # (distribution notice), or nil when none has been generated / approved yet (lp-mobile-app H6,
  # E22). Used by capital_remittances/show.json and capital_distribution_payments/show.json.
  def self.notice_for(record)
    record.documents.not_template.where(APPROVED_SQL)
          .joins(:folder).where(folders: { private: false })
          .order(id: :desc).pick(:id)
  end

  def initialize(user:, scope:)
    @user = user
    @scope = scope
  end

  # Newest first; narrowed by commitment, search text or "to sign" when given
  def list(commitment_id: nil, query: nil, to_sign: false)
    docs = visible
    docs = docs.where(id: for_commitment_ids(commitment_id)) if commitment_id.present?
    docs = docs.where("documents.name LIKE ?", "%#{Document.sanitize_sql_like(query.to_s.strip)}%") if query.present?
    docs = docs.where(id: awaiting_signature.select(:id)) if to_sign
    docs.order(id: :desc)
  end

  # Documents sent for e-signature where THIS user's signature is still outstanding
  def awaiting_signature
    visible.where(sent_for_esign: true)
           .where(id: ESignature.not_signed.where(user_id: user.id).select(:document_id))
  end

  def visible
    Document.not_template
            .joins(:folder).where(folders: { private: false })
            .where(owner_clause)
            .where(APPROVED_SQL)
  end

  private

  attr_reader :user, :scope

  def commitment_ids
    @commitment_ids ||= scope.call(CapitalCommitment).pluck(:id)
  end

  # owner in (my commitments) OR (my remittances) OR (my distribution payments)
  def owner_clause
    owners_for(commitment_ids)
  end

  def for_commitment_ids(commitment_id)
    ids = commitment_ids & [commitment_id.to_i]
    Document.where(owners_for(ids)).select(:id)
  end

  def owners_for(ids)
    docs = Document.arel_table
    remittance_ids = CapitalRemittance.where(capital_commitment_id: ids).select(:id)
    payment_ids = CapitalDistributionPayment.where(capital_commitment_id: ids).select(:id)
    docs[:owner_type].eq("CapitalCommitment").and(docs[:owner_id].in(ids))
                     .or(docs[:owner_type].eq("CapitalRemittance").and(docs[:owner_id].in(remittance_ids.arel)))
                     .or(docs[:owner_type].eq("CapitalDistributionPayment").and(docs[:owner_id].in(payment_ids.arel)))
  end
end
