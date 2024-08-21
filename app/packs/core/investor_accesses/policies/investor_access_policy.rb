class InvestorAccessPolicy < ApplicationPolicy
  def index?
    # user.has_cached_role?(:company_admin)
    !user.investor_advisor?
  end

  def show?
    user.has_cached_role?(:company_admin) &&
      (belongs_to_entity?(user, record) || user.entity_id == record.investor.investor_entity_id)
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def request_access?
    user.entity_id == record.investor.investor_entity_id && !record.approved
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record)
  end

  def approve?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end
end
