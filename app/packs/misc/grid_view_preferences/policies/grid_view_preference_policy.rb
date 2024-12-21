class GridViewPreferencePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def create?
    belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)
  end

  def show?
    create?
  end

  def edit?
    create?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def update_column_sequence?
    create?
  end

  def new?
    create?
  end
end
