class DocumentPolicy < ApplicationPolicy
  def index?
    user.enable_documents
  end

  def show?
    record.public_visibility ||
      (user && (
        (user.enable_documents && belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) ||
        (user.enable_documents && show_investor? && !user.investor_advisor?) ||
        (record.owner && owner_policy.show?) ||
        allow_external?(:read) || super_user?
      ))
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

  def send_for_esign?
    update? && !record.sent_for_esign && record.e_signatures.all? { |esign| esign.user&.email.present? } && record.esign_status&.downcase != "cancelled"
  end

  def force_send_for_esign?
    update? && record.sent_for_esign && record.e_signatures.all? { |esign| esign.user&.email.present? } && user.has_cached_role?(:company_admin)
  end

  def send_all_for_esign?
    user.enable_documents && user.has_cached_role?(:company_admin)
  end

  def cancel_esign?
    update? && user.has_cached_role?(:company_admin) && record.sent_for_esign && record.esign_status&.downcase != "cancelled"
  end

  def fetch_esign_updates?
    update? && record.sent_for_esign && record.esign_status&.downcase != "cancelled"
  end

  def edit?
    update?
  end

  def destroy?
    update? && record.entity_id == user.entity_id
  end

  def show_investor?
    Document.for_investor(user, record.entity)
            .where("documents.id=?", record.id).first.present?
  end

  def owner_policy
    Pundit.policy(user, record.owner)
  end
end
