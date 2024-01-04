class ReportPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: [user.entity_id, nil])
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || record.entity.nil? || super_user?
  end

  def create?
    belongs_to_entity?(user, record)
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
