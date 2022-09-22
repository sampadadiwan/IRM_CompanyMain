class InvestorAccessPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    user.has_cached_role?(:super) || user.entity_id == record.entity_id || user.entity_id == record.investor.investor_entity_id
  end

  def create?
    (user.has_cached_role?(:super) || user.entity_id == record.entity_id)
  end

  def request_access?
    user.entity_id == record.investor.investor_entity_id && !record.approved
  end

  def new?
    create?
  end

  def update?
    user.has_cached_role?(:super) || user.entity_id == record.entity_id
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
