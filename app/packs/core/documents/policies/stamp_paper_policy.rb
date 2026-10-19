class StampPaperPolicy < ApplicationPolicy
  def index?
    user.enable_documents
  end

  def show?
    user.enable_documents &&
      belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update? && (!record.owner&.sent_for_esign || user.has_cached_role?(:company_admin))
  end

  def destroy?
    update?
  end
end
