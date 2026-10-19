class ValuationPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) ||
      (record.owner && owner_policy.show?)
  end

  def create?
    # D: the owner (through its policy) and the instrument are in one of the user's firms
    belongs_to_entity?(user, record) && Pundit.policy(user, record.owner).update? && parent_in_users_firms?(record.investment_instrument)
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
