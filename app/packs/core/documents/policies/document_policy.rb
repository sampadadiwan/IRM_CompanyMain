class DocumentPolicy < ApplicationPolicy
  def index?
    user.enable_documents || support?
  end

  def bulk_actions?
    index?
  end

  def show?
    record.public_visibility ||
      (
        user.enable_documents && belongs_to_entity?(user, record) &&
        (user.has_cached_role?(:company_admin) || (record.owner.present? && owner_policy.show? && !record.folder.private))
      ) ||
      (user.enable_documents && show_investor? && !user.investor_advisor?) ||
      (record.owner.present? && owner_policy.show? && !record.folder.private && not_generated_or_approved)
  end

  def not_generated_or_approved
    # Either is is not a generated doc or it is generated but approved
    record.from_template_id.nil? || record.approved
  end

  def create?
    (user.enable_documents && permissioned_employee?(:update)) ||
      (record.owner && owner_policy.update?) ||
      # The DealInvestor/CapitalCommitment are cases where other users can attach documents to the document owner which is not created by them
      (record.owner && record.owner_type == "DealInvestor" && owner_policy.show?)
    # || (record.owner && record.owner_type == "CapitalCommitment" && owner_policy.show?)
  end

  def new?
    create?
  end

  def download?
    index?
  end

  def update?
    (
      permissioned_employee?(:update) ||
      (record.owner && owner_policy.update?) ||
      allow_external?(:write)
    ) && !record.locked # Ensure locked documents cannot be changed
  end

  # remove user check in next iteration - only check email
  def send_for_esign?
    update? && !record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && !record.esign_expired? && record.approved
  end

  def resend_for_esign?
    update? && record.resend_for_esign?
  end

  def force_send_for_esign?
    update? && record.sent_for_esign && record.e_signatures.all? { |esign| esign.email.present? } && user.has_cached_role?(:company_admin)
  end

  def send_all_for_esign?
    user.enable_documents && user.has_cached_role?(:company_admin)
  end

  def cancel_esign?
    update? && user.has_cached_role?(:company_admin) && record.sent_for_esign && !record.esign_expired? && !record.esign_failed? && !record.esign_voided?
  end

  def fetch_esign_updates?
    res = update? && record.sent_for_esign && !record.esign_expired? && !record.esign_failed? && !record.esign_voided?
    if record.entity.entity_setting.esign_provider == "Docusign" && !Rails.env.test?
      # hit the docusign api every 15 minutes
      eligible_for_update = record.last_status_updated_at.nil? || record.last_status_updated_at < 900.seconds.ago
      res && eligible_for_update
    else
      res
    end
  end

  def edit?
    update?
  end

  def approve?
    update? && record.to_be_approved? && user.has_cached_role?(:approver)
  end

  def unapprove?
    update? && record.approved && user.has_cached_role?(:approver)
  end

  def destroy?
    (permissioned_employee?(:destroy) &&
    (!record.sent_for_esign || record.esign_expired? || record.esign_failed? || record.esign_voided?)) || support?
  end

  def show_investor?
    not_generated_or_approved && Document.for_investor(user, record.entity)
                                         .where("documents.id=?", record.id).first.present?
  end

  def send_document_notification?
    update?
  end
end
