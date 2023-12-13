class NotePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(user_id: user.id)
      end
    end

    def resolve_admin
      # scope.where(enable_support: true)
      scope.all
    end
  end

  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
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
