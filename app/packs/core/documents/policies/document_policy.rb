class DocumentPolicy < ApplicationPolicy
  def index?
    user.enable_documents || support?
  end

  def bulk_actions?
    index?
  end

  def show?
    record.public_visibility ||
      (user && (
        (
          user.enable_documents && belongs_to_entity?(user, record) &&
          (user.has_cached_role?(:company_admin) || (record.owner && owner_policy.show?))
        ) ||
        (user.enable_documents && show_investor? && !user.investor_advisor?) ||
        (record.owner && owner_policy.show? && not_generated_or_approved)
      ))
  end

  def not_generated_or_approved
    # Either is is not a generated doc or it is generated but approved
    record.from_template_id.nil? || record.approved
  end

  def create?
    (belongs_to_entity?(user, record) && user.enable_documents) ||
      (record.owner && owner_policy.update?) ||
      # The DealInvestor/CapitalCommitment are cases where other users can attach documents to the document owner which is not created by them
      (record.owner && record.owner_type == "DealInvestor" && owner_policy.show?)
    # || (record.owner && record.owner_type == "CapitalCommitment" && owner_policy.show?)
  end

  def new?
    create?
  end

  def update?
    (
      create? ||
      (record.owner && owner_policy.update?) ||
      allow_external?(:write)
    ) && !record.locked # Ensure locked documents cannot be changed
  end

  # remove user check in next iteration - only check email
  def send_for_esign?
    update? && !record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && !record.esign_expired? && record.approved
  end

  def force_send_for_esign?
    update? && record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && user.has_cached_role?(:company_admin)
  end

  def send_all_for_esign?
    user.enable_documents && user.has_cached_role?(:company_admin)
  end

  def cancel_esign?
    update? && user.has_cached_role?(:company_admin) && record.sent_for_esign && !record.esign_expired? && !record.esign_failed?
  end

  def fetch_esign_updates?
    update? && record.sent_for_esign && !record.esign_expired? && !record.esign_failed?
  end

  def edit?
    update?
  end

  def approve?
    user.has_cached_role?(:company_admin) || user.has_cached_role?(:approver)
  end

  def destroy?
    (update? && record.entity_id == user.entity_id &&
    (!record.sent_for_esign || record.esign_expired? || record.esign_failed?)) || support?
  end

  def show_investor?
    not_generated_or_approved && Document.for_investor(user, record.entity)
                                         .where("documents.id=?", record.id).first.present?
  end
end
