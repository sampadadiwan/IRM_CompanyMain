class ValuationPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) ||
      (record.owner && owner_policy.show?)
  end

  def create?
    belongs_to_entity?(user, record) && Pundit.policy(user, record.owner).update?
  end

  def value_bridge?
    show?
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

  def owner_policy
    Pundit.policy(user, record.owner)
  end
end
