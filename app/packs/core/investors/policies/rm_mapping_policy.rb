class RmMappingPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:rm)
        scope.for_rm(user)
      else
        scope.none
      end
    end
  end

  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      belongs_to_entity?(user, record) && (user.has_cached_role?(:company_admin) || permissioned_rm?)
  end

  def create?
    belongs_to_entity?(user, record) && (user.has_cached_role?(:company_admin) || user.id == record.user_id)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
