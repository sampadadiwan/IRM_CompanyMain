class FormTypePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def search?
    true
  end

  def show?
    belongs_to_entity?(user, record) || support?
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || support?
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

  def rename_fcf?
    update?
  end

  def clone?
    true
  end
end
