class ValuationPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) ||
      (record.owner && owner_policy.show?) || super_user?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create? || super_user?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def owner_policy
    Pundit.policy(user, record.owner)
  end
end
