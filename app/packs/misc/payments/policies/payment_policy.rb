class PaymentPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    user.has_cached_role?(:super)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    false
  end
end
