class AssistantTaskPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) && (user.has_cached_role?(:company_admin) || user.id == record.user_id)
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
