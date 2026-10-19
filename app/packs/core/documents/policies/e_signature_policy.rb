class ESignaturePolicy < ApplicationPolicy
  def index?
    user.enable_documents
  end

  def show?
    user.enable_documents &&
      belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.document)
  end

  def new?
    create?
  end

  def update?
    create? && !record.document.sent_for_esign
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
