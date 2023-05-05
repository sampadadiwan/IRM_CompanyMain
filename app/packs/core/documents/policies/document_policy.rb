class DocumentPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      case user.curr_role
      when "consultant"
        scope.joins(:permissions).where("permissions.user_id=?", user.id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_documents
  end

  def show?
    record.public_visibility ||
      (user && (
        (user.enable_documents && user.entity_id == record.entity_id) ||
        (user.enable_documents && show_investor? && !user.investor_advisor?) ||
        (record.owner && owner_policy.show?) ||
        allow_external?(:read)
      ))
  end

  def sign?
    record.signature_enabled && record.signed_by_id.blank? && show?
  end

  def create?
    (user.entity_id == record.entity_id && user.enable_documents) ||
      (record.owner && owner_policy.update?) ||
      # The DealInvestor/CapitalCommitment are cases where other users can attach documents to the document owner which is not created by them
      (record.owner && record.owner_type == "DealInvestor" && owner_policy.show?) ||
      (record.owner && record.owner_type == "CapitalCommitment" && owner_policy.show?)
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
